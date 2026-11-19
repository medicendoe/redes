import socket
import time
from itertools import zip_longest

from router import create_packet, fragment_IP_packet, parse_packet

# Paso 7: dos listas de fragmentos con distinto ID, enviadas a mano a R5 (127.0.0.1:8885), que debe estar
# corriendo. Cada caso usa IDs nuevos.
R5 = ("127.0.0.1", 8885)


#fragments_for: int, str -> list[bytes]
#Fragmentos con MTU 30 (10 bytes de mensaje cada uno) de un paquete hacia R5.
def fragments_for(ID, mensaje):
    mensaje = mensaje.encode()
    return fragment_IP_packet(create_packet({"IP": R5[0], "puerto": R5[1], "TTL": 10, "ID": ID, "offset": 0,
                                             "tamaño": len(mensaje), "FLAG": 0, "mensaje": mensaje}), 30)


cases = {
    "en orden": lambda a, b: a + b,
    "en desorden": lambda a, b: a[::-1] + b[::-1],
    "intercalando ID": lambda a, b: [f for par in zip_longest(a, b) for f in par if f],
}
sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
for i, (name, order) in enumerate(cases.items()):
    fragments = order(fragments_for(2 * i + 1, f"Caso '{name}', mensaje A."),
                      fragments_for(2 * i + 2, f"Caso '{name}', mensaje B, un poco más largo."))
    print(f"{name}: " + " ".join(f"{p['ID']}:{p['offset']}" for p in map(parse_packet, fragments)))
    for fragment in fragments:
        sender.sendto(fragment, R5)
    time.sleep(0.2)
sender.close()
