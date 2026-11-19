import random
import socket
import sys

from router import create_packet

DEFAULT_TTL = 64


#parse_headers: str, bytes -> dict
#"IP;puerto;TTL;ID;offset;tamaño;FLAG" a un paquete con mensaje. Desde el TTL todos son opcionales: TTL 64,
#ID al azar, offset 0, tamaño el del mensaje y FLAG 0.
def parse_headers(headers, mensaje=b""):
    campos = headers.split(";")
    valor = lambda i, default: int(campos[i]) if len(campos) > i else default
    return {"IP": campos[0], "puerto": int(campos[1]), "TTL": valor(2, DEFAULT_TTL),
            "ID": valor(3, random.randint(0, 9999)), "offset": valor(4, 0), "tamaño": valor(5, len(mensaje)),
            "FLAG": valor(6, 0), "mensaje": mensaje}


# python3 enviar.py "IP_destino;puerto_destino[;TTL;ID[;offset;tamaño;FLAG]]" "mensaje" IP_envío puerto_envío
if __name__ == "__main__":
    packet = parse_headers(sys.argv[1], sys.argv[2].encode())
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sender.sendto(create_packet(packet), (sys.argv[3], int(sys.argv[4])))
    sender.close()
