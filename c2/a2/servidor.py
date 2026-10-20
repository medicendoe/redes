import sys

import SocketTCP

# SERVER
host, port = sys.argv[1], int(sys.argv[2])
mode = sys.argv[3] if len(sys.argv) > 3 else "go_back_n"
server = SocketTCP.SocketTCP()
server.bind((host, port))
connection, address = server.accept()
sys.stdout.buffer.write(connection.recv(1 << 20, mode))
sys.stdout.flush()
connection.recv_close()
