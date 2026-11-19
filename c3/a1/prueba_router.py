import socket
import sys

from enviar import parse_headers
from router import create_packet

# python3 prueba_router.py "IP;puerto;TTL" IP_router_inicial puerto_router_inicial < archivo.txt
# Cada línea de stdin viaja en su propio paquete, sin esperar entre uno y otro.
if __name__ == "__main__":
    headers = parse_headers(sys.argv[1])
    router_inicial = (sys.argv[2], int(sys.argv[3]))
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    for line in sys.stdin.buffer:
        sender.sendto(create_packet(headers | {"mensaje": line.rstrip(b"\n")}), router_inicial)
    sender.close()
