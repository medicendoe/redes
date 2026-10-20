import os
import random
import socket
import sys
import time

LOSS = float(os.getenv("LOSS", 0))
TIMEOUT = float(os.getenv("TIMEOUT", 0.5))
DEBUG = os.getenv("DEBUG", "0") == "1"
LOSE_HANDSHAKE_ACK = os.getenv("LOSE_HANDSHAKE_ACK", "0") == "1"
HEADER_SIZE = 5
DATA_SIZE = 16


class SocketTCP:
    #__init__: None -> SocketTCP
    #TCP simplificado con Stop & Wait sobre un socket UDP.
    def __init__(self):
        self.socketUDP = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.address = None
        self.destination = None
        self.seq = 0
        self.left = 0
        self.buffer = b""

    #parse_segment: bytes -> dict
    #Separa flags, seq y datos de un segmento.
    @staticmethod
    def parse_segment(segment):
        flags = segment[0]
        return {"SYN": flags & 1, "ACK": flags >> 1 & 1, "FIN": flags >> 2 & 1,
                "seq": int.from_bytes(segment[1:5], "big"), "data": segment[5:]}

    #create_segment: dict -> bytes
    #1 byte de flags (SYN|ACK|FIN), 4 bytes de seq y luego los datos.
    @staticmethod
    def create_segment(seg):
        flags = seg.get("SYN", 0) | seg.get("ACK", 0) << 1 | seg.get("FIN", 0) << 2
        return bytes([flags]) + seg["seq"].to_bytes(4, "big") + seg.get("data", b"")

    #divide_message: bytes, int -> list[bytes]
    #Trozos de a lo más size bytes.
    @staticmethod
    def divide_message(message, size):
        return [message[i:i + size] for i in range(0, len(message), size)]

    #describe: dict -> str
    #Resumen legible de un segmento para el modo debug.
    @staticmethod
    def describe(seg):
        flags = "+".join(f for f in ("SYN", "ACK", "FIN") if seg.get(f)) or "DATA"
        return f"{flags} seq={seg['seq']}" + (f" len={len(seg['data'])}" if seg.get("data") else "")

    #_is_data: dict -> bool
    #True si el segmento no lleva flags.
    @staticmethod
    def _is_data(seg):
        return not (seg["SYN"] or seg["ACK"] or seg["FIN"])

    #_log: str -> None
    #Imprime en stderr si DEBUG está activo.
    def _log(self, msg):
        if DEBUG:
            print(f"[{self.socketUDP.getsockname()[1]}] {msg}", file=sys.stderr)

    #_send: dict -> None
    #Envía seg al destino.
    def _send(self, seg):
        self.socketUDP.sendto(self.create_segment(seg), self.destination)
        self._log(f"-> {self.describe(seg)}")

    #_recv_segment: float | None -> (dict, (str, int))
    #Espera a lo más timeout segundos y descarta al azar con probabilidad LOSS.
    def _recv_segment(self, timeout=None):
        self.socketUDP.settimeout(timeout)
        while True:
            raw, address = self.socketUDP.recvfrom(HEADER_SIZE + DATA_SIZE)
            seg = self.parse_segment(raw)
            if random.random() >= LOSS:
                self._log(f"<- {self.describe(seg)}")
                return seg, address
            self._log(f"xx {self.describe(seg)} (pérdida simulada)")

    #_exchange: dict, func, int | None -> (dict, addr) | (None, None)
    #Envía seg y lo reenvía en cada timeout hasta recibir uno que cumpla ok.
    def _exchange(self, seg, ok, tries=None):
        self._send(seg)
        while True:
            try:
                got, address = self._recv_segment(TIMEOUT)
                if ok(got):
                    return got, address
            except socket.timeout:
                self._log("timeout")
                if tries is not None:
                    tries -= 1
                    if tries == 0:
                        return None, None
                self._send(seg)

    #bind: (str, int) -> None
    #Escucha en address.
    def bind(self, address):
        self.socketUDP.bind(address)
        self.address = self.socketUDP.getsockname()

    #connect: (str, int) -> None
    #Lado cliente del 3-way handshake; LOSE_HANDSHAKE_ACK simula perder el último ACK.
    def connect(self, address):
        self.destination = address
        self.seq = random.randint(0, 100)
        _, self.destination = self._exchange(
            {"SYN": 1, "seq": self.seq},
            lambda s: s["SYN"] and s["ACK"] and s["seq"] == self.seq + 1)
        self.seq += 2
        if LOSE_HANDSHAKE_ACK:
            self._log(f"xx ACK seq={self.seq} (pérdida forzada)")
        else:
            self._send({"ACK": 1, "seq": self.seq})

    #accept: None -> (SocketTCP, (str, int))
    #Lado servidor del handshake; datos con el seq esperado cuentan como ACK.
    def accept(self):
        while True:
            seg, address = self._recv_segment()
            if seg["SYN"] and not seg["ACK"]:
                break
        conn = SocketTCP()
        conn.bind((self.address[0], 0))
        conn.destination = address
        conn.seq = seg["seq"] + 1
        conn._exchange({"SYN": 1, "ACK": 1, "seq": conn.seq},
                       lambda s: not s["SYN"] and s["seq"] == conn.seq + 1)
        conn.seq += 1
        return conn, conn.address

    #send: bytes -> None
    #Envía el largo y luego trozos de 16 bytes, esperando el ACK de cada uno.
    def send(self, message):
        for chunk in [str(len(message)).encode()] + self.divide_message(message, DATA_SIZE):
            end = self.seq + len(chunk)
            self._exchange({"seq": self.seq, "data": chunk},
                           lambda s: s["ACK"] and not (s["SYN"] or s["FIN"]) and s["seq"] == end)
            self.seq = end

    #recv: int -> bytes
    #Retorna min(message_length, buff_size) bytes, guardando lo que sobre.
    def recv(self, buff_size):
        if self.left == 0:
            self.left = int(self._recv_data())
        n = min(self.left, buff_size)
        while len(self.buffer) < n:
            self.buffer += self._recv_data()
        out, self.buffer = self.buffer[:n], self.buffer[n:]
        self.left -= n
        return out

    #_recv_data: None -> bytes
    #Espera el siguiente segmento en orden y responde con ACK a todo segmento de datos.
    def _recv_data(self):
        while True:
            seg, _ = self._recv_segment()
            if not self._is_data(seg):
                continue
            in_order = seg["seq"] == self.seq
            if in_order:
                self.seq += len(seg["data"])
            self._send({"ACK": 1, "seq": self.seq})
            if in_order:
                return seg["data"]

    #close: None -> None
    #Cierre desde Host A: FIN hasta 3 timeouts y luego el último ACK tres veces.
    def close(self):
        fin_ack, _ = self._exchange({"FIN": 1, "seq": self.seq},
                                    lambda s: s["FIN"] and s["ACK"] and s["seq"] == self.seq + 1, tries=3)
        if fin_ack:
            for _ in range(3):
                self._send({"ACK": 1, "seq": self.seq + 2})
                time.sleep(TIMEOUT)
        self.socketUDP.close()

    #recv_close: None -> None
    #Cierre desde Host B: espera FIN, responde FIN+ACK y espera el ACK hasta 3 timeouts.
    def recv_close(self):
        while True:
            seg, _ = self._recv_segment()
            if seg["FIN"] and not seg["ACK"]:
                break
            if self._is_data(seg):
                self._send({"ACK": 1, "seq": self.seq})
        self.seq = seg["seq"] + 1
        self._exchange({"FIN": 1, "ACK": 1, "seq": self.seq},
                       lambda s: s["ACK"] and not s["FIN"] and s["seq"] == self.seq + 1, tries=3)
        self.socketUDP.close()
