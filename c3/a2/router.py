import ipaddress
import os
import socket
import sys

DEBUG = os.getenv("DEBUG", "0") == "1"
HEADER_SIZE = 20
BUFF_SIZE = 4096

# Última ruta usada en cada área: (red, puerto_inicial, puerto_final) -> índice
round_robin = {}


#parse_packet: bytes -> dict
#4 bytes de IP, 2 de puerto, 1 de TTL, 4 de ID, 4 de offset, 4 de tamaño, 1 de FLAG y luego el mensaje.
def parse_packet(IP_packet):
    size = int.from_bytes(IP_packet[15:19], "big")
    return {"IP": socket.inet_ntoa(IP_packet[0:4]),
            "puerto": int.from_bytes(IP_packet[4:6], "big"),
            "TTL": IP_packet[6],
            "ID": int.from_bytes(IP_packet[7:11], "big"),
            "offset": int.from_bytes(IP_packet[11:15], "big"),
            "tamaño": size,
            "FLAG": IP_packet[19],
            "mensaje": IP_packet[HEADER_SIZE:HEADER_SIZE + size]}


#create_packet: dict -> bytes
#Camino de vuelta de parse_packet.
def create_packet(parsed_IP_packet):
    p = parsed_IP_packet
    return (socket.inet_aton(p["IP"]) + p["puerto"].to_bytes(2, "big") + bytes([p["TTL"]])
            + p["ID"].to_bytes(4, "big") + p["offset"].to_bytes(4, "big") + p["tamaño"].to_bytes(4, "big")
            + bytes([p["FLAG"]]) + p["mensaje"])


#describe: dict -> str
#IP;puerto;TTL;ID;offset;tamaño;FLAG;mensaje, con el mensaje recortado.
def describe(parsed_IP_packet):
    p = parsed_IP_packet
    mensaje = p["mensaje"].decode(errors="replace")
    mensaje = mensaje if len(mensaje) <= 16 else mensaje[:13] + "..."
    return f"{p['IP']};{p['puerto']};{p['TTL']};{p['ID']};{p['offset']};{p['tamaño']};{p['FLAG']};{mensaje}"


#address: (str, int) -> str
#ip:puerto
def address(addr):
    return f"{addr[0]}:{addr[1]}"


#log: str -> None
#Imprime en stderr si DEBUG está activo.
def log(msg):
    if DEBUG:
        print(msg, file=sys.stderr)


#read_routes: str -> list[list[str]]
#Líneas de la tabla de rutas, sin vacías ni comentarios.
def read_routes(routes_file_name):
    with open(routes_file_name) as f:
        return [line.split() for line in f if line.strip() and not line.startswith("#")]


#matches: list[str], (str, int) -> bool
#True si destination_address cae en la red y el rango de puertos de la ruta.
def matches(route, destination_address):
    red, inicio, fin = route[:3]
    ip, puerto = destination_address
    return (ipaddress.ip_address(ip) in ipaddress.ip_network(red, strict=False)
            and int(inicio) <= puerto <= int(fin))


#check_routes: str, (str, int) -> ((str, int), int) | None
#Igual que en forwarding básico, pero retorna también el MTU del enlace: (next_hop, MTU).
def check_routes(routes_file_name, destination_address):
    routes = read_routes(routes_file_name)
    for route in routes:
        if matches(route, destination_address):
            area = tuple(route[:3])
            options = [((r[3], int(r[4])), int(r[5])) for r in routes if tuple(r[:3]) == area]
            round_robin[area] = (round_robin.get(area, -1) + 1) % len(options)
            return options[round_robin[area]]
    return None


#fragment_IP_packet: bytes, int -> list[bytes]
#Fragmentos de a lo más MTU bytes con header incluido. Sirve también para fragmentar un fragmento: los
#offsets parten del suyo y solo el último trozo hereda su FLAG.
def fragment_IP_packet(IP_packet, MTU):
    if len(IP_packet) <= MTU:
        return [IP_packet]
    if MTU <= HEADER_SIZE:
        raise ValueError(f"MTU {MTU} no deja espacio para datos")
    packet = parse_packet(IP_packet)
    mensaje, chunk = packet["mensaje"], MTU - HEADER_SIZE
    fragments = []
    for i in range(0, len(mensaje), chunk):
        trozo = mensaje[i:i + chunk]
        last = i + chunk >= len(mensaje)
        fragments.append(create_packet(packet | {"offset": packet["offset"] + i, "tamaño": len(trozo),
                                                 "FLAG": packet["FLAG"] if last else 1, "mensaje": trozo}))
    return fragments


#reassemble_IP_packet: list[bytes] -> bytes | None
#Ordena por offset y pega los mensajes. None si falta el comienzo, un trozo intermedio o el último (FLAG 0).
def reassemble_IP_packet(fragment_list):
    fragments = sorted(map(parse_packet, fragment_list), key=lambda p: p["offset"])
    mensaje = b""
    for fragment in fragments:
        if fragment["offset"] != len(mensaje):
            return None
        mensaje += fragment["mensaje"]
    if not fragments or fragments[-1]["FLAG"] == 1:
        return None
    return create_packet(fragments[0] | {"tamaño": len(mensaje), "FLAG": 0, "mensaje": mensaje})


if __name__ == "__main__":
    sys.stdout.reconfigure(line_buffering=True)
    router_IP, router_puerto, router_rutas = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    router_address = (router_IP, router_puerto)
    router = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    router.bind(router_address)
    fragments = {}  # ID -> fragmentos o paquetes recibidos con ese ID

    while True:
        IP_packet, _ = router.recvfrom(BUFF_SIZE)
        packet = parse_packet(IP_packet)
        destination_address = (packet["IP"], packet["puerto"])
        if packet["TTL"] == 0:
            print(f"Se recibió paquete {describe(packet)} con TTL 0")
        elif destination_address == router_address:
            fragments.setdefault(packet["ID"], []).append(IP_packet)
            log(f"llegó {describe(packet)} ({len(fragments[packet['ID']])} con ID {packet['ID']})")
            reassembled = reassemble_IP_packet(fragments[packet["ID"]])
            if reassembled is not None:
                del fragments[packet["ID"]]
                print(parse_packet(reassembled)["mensaje"].decode(errors="replace"))
        else:
            route = check_routes(router_rutas, destination_address)
            if route is None:
                print(f"No hay rutas hacia {address(destination_address)} para paquete {describe(packet)}")
                continue
            next_hop, MTU = route
            packet["TTL"] -= 1
            for fragment in fragment_IP_packet(create_packet(packet), MTU):
                print(f"redirigiendo paquete {describe(parse_packet(fragment))} con destino final "
                      f"{address(destination_address)} desde {address(router_address)} hacia {address(next_hop)}")
                router.sendto(fragment, next_hop)
