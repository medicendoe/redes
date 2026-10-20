import sys
import time

import SocketTCP

# CLIENT
mode = sys.argv[3] if len(sys.argv) > 3 else "go_back_n"
client = SocketTCP.SocketTCP()
client.set_congestion_control("cc" in sys.argv)
client.connect((sys.argv[1], int(sys.argv[2])))
start = time.time()
client.send(sys.stdin.buffer.read(), mode)
print(f"tiempo: {time.time() - start:.2f} s, segmentos enviados: {client.number_of_sent_segments}")
client.close()
