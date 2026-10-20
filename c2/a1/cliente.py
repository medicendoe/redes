import sys

import SocketTCP

# CLIENT
client = SocketTCP.SocketTCP()
client.connect((sys.argv[1], int(sys.argv[2])))
client.send(sys.stdin.buffer.read())
client.close()
