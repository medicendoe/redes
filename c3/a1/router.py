import ipaddress
import os
import socket
import sys

NO_TTL = os.getenv("NO_TTL", "0") == "1"
HEADER_SIZE = 7
BUFF_SIZE = 4096

# Última ruta usada en cada área: (red, puerto_inicial, puerto_final) -> índice
round_robin = {}


#parse_packet: bytes -> dict
#4 bytes de IP, 2 de puerto, 1 de TTL y luego el mensaje.
def parse_packet(IP_packet):
    return {"IP": socket.inet_ntoa(IP_packet[0:4]),
            "puerto": int.from_bytes(IP_packet[4:6], "big"),
            "TTL": IP_packet[6],
            "mensaje": IP_packet[HEADER_SIZE:]}


#create_packet: dict -> bytes
#Camino de vuelta de parse_packet.
def create_packet(parsed_IP_packet):
    return (socket.inet_aton(parsed_IP_packet["IP"])
            + parsed_IP_packet["puerto"].to_bytes(2, "big")
            + bytes([parsed_IP_packet["TTL"]])
            + parsed_IP_packet["mensaje"])


#describe: dict -> str
#El paquete en la notación de los headers de prueba_router.py, con el mensaje recortado.
def describe(parsed_IP_packet):
    mensaje = parsed_IP_packet["mensaje"].decode(errors="replace")
    mensaje = mensaje if len(mensaje) <= 24 else mensaje[:21] + "..."
    return f"{parsed_IP_packet['IP']};{parsed_IP_packet['puerto']};{parsed_IP_packet['TTL']};{mensaje}"


#address: (str, int) -> str
#ip:puerto
def address(addr):
    return f"{addr[0]}:{addr[1]}"


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


#check_routes: str, (str, int) -> (str, int) | None
#Revisa la tabla en orden. La primera ruta que calza define el área (red y rango de puertos); si el área
#tiene varias rutas, se alternan con round-robin.
def check_routes(routes_file_name, destination_address):
    routes = read_routes(routes_file_name)
    for route in routes:
        if matches(route, destination_address):
            area = tuple(route[:3])
            options = [(r[3], int(r[4])) for r in routes if tuple(r[:3]) == area]
            round_robin[area] = (round_robin.get(area, -1) + 1) % len(options)
            return options[round_robin[area]]
    return None


if __name__ == "__main__":
    sys.stdout.reconfigure(line_buffering=True)
    router_IP, router_puerto, router_rutas = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    router_address = (router_IP, router_puerto)
    router = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    router.bind(router_address)

    while True:
        IP_packet, _ = router.recvfrom(BUFF_SIZE)
        packet = parse_packet(IP_packet)
        destination_address = (packet["IP"], packet["puerto"])
        if packet["TTL"] == 0 and not NO_TTL:
            print(f"Se recibió paquete {describe(packet)} con TTL 0")
        elif destination_address == router_address:
            print(packet["mensaje"].decode(errors="replace"))
        else:
            next_hop = check_routes(router_rutas, destination_address)
            if next_hop is None:
                print(f"No hay rutas hacia {address(destination_address)} para paquete {describe(packet)}")
                continue
            if not NO_TTL:
                packet["TTL"] -= 1
            print(f"redirigiendo paquete {describe(packet)} con destino final {address(destination_address)} "
                  f"desde {address(router_address)} hacia {address(next_hop)}")
            router.sendto(create_packet(packet), next_hop)
