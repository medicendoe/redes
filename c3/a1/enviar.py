import socket
import sys

from router import create_packet

DEFAULT_TTL = 64


#parse_headers: str -> dict
#"IP;puerto;TTL" a un paquete sin mensaje; el TTL es opcional.
def parse_headers(headers):
    campos = headers.split(";")
    ttl = int(campos[2]) if len(campos) > 2 else DEFAULT_TTL
    return {"IP": campos[0], "puerto": int(campos[1]), "TTL": ttl}


# python3 enviar.py "IP_destino;puerto_destino[;TTL]" "mensaje" IP_envío puerto_envío
if __name__ == "__main__":
    packet = parse_headers(sys.argv[1]) | {"mensaje": sys.argv[2].encode()}
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sender.sendto(create_packet(packet), (sys.argv[3], int(sys.argv[4])))
    sender.close()
