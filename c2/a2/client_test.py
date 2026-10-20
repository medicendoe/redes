import sys

import SocketTCP

address = ("localhost", 8000)
mode = sys.argv[1] if len(sys.argv) > 1 else "stop_and_wait"

# CLIENT
client_socketTCP = SocketTCP.SocketTCP()
client_socketTCP.set_congestion_control("cc" in sys.argv)
client_socketTCP.connect(address)
# test 1
message = "Mensje de len=16".encode()
client_socketTCP.send(message, mode)
# test 2
message = "Mensaje de largo 19".encode()
client_socketTCP.send(message, mode)
# test 3
message = "Mensaje de largo 19".encode()
client_socketTCP.send(message, mode)
# test 4
message = "Mensaje de largo 74, leido con dos recv de 37 bytes (37 no es multiplo 16)".encode()
client_socketTCP.send(message, mode)
client_socketTCP.close()
