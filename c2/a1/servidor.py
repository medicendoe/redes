import sys

import SocketTCP

# SERVER
server = SocketTCP.SocketTCP()
server.bind((sys.argv[1], int(sys.argv[2])))
connection, address = server.accept()
sys.stdout.buffer.write(connection.recv(1 << 20))
sys.stdout.flush()
connection.recv_close()
