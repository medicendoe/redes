import os
import random
import sys
import time

from CongestionControl import CongestionControl
from slidingWindowCC import SlidingWindowCC
from socketUDP import SocketUDP

LOSS = float(os.getenv("LOSS", 0))
TIMEOUT = float(os.getenv("TIMEOUT", 0.5))
DEBUG = os.getenv("DEBUG", "0") == "1"
HEADER_SIZE = 5
DATA_SIZE = 16
MSS = 8
GBN_WINDOW = 8


class SocketTCP:
    #__init__: None -> SocketTCP
    #TCP simplificado sobre un SocketUDP con timers.
    def __init__(self):
        self.socketUDP = SocketUDP()
        self.socketUDP.settimeout(TIMEOUT)
        self.address = None
        self.destination = None
        self.seq = 0
        self.left = 0
        self.buffer = b""
        self.congestion_control_on = False
        self.number_of_sent_segments = 0

    #set_congestion_control: bool -> None
    #Enciende o apaga el control de congestión.
    def set_congestion_control(self, on):
        self.congestion_control_on = on

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
            print(f"[{self.socketUDP.socket_udp.getsockname()[1]}] {msg}", file=sys.stderr)

    #_send: dict, bool -> None
    #Envía seg al destino; con timer=False el timer queda detenido.
    def _send(self, seg, timer=True):
        self.socketUDP.sendto(self.create_segment(seg), self.destination)
        self.number_of_sent_segments += 1
        self._log(f"-> {self.describe(seg)}")
        if not timer:
            self.socketUDP.stop_timer()

    #_recv_segment: None -> (dict, (str, int))
    #Recibe un segmento, descartando al azar con probabilidad LOSS.
    def _recv_segment(self):
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
                got, address = self._recv_segment()
                if ok(got):
                    self.socketUDP.stop_timer()
                    return got, address
            except TimeoutError:
                self._log("timeout")
                self.socketUDP.stop_timer()
                if tries is not None:
                    tries -= 1
                    if tries == 0:
                        return None, None
                self._send(seg)

    #bind: (str, int) -> None
    #Escucha en address.
    def bind(self, address):
        self.socketUDP.bind(address)
        self.address = self.socketUDP.socket_udp.getsockname()

    #connect: (str, int) -> None
    #Lado cliente del 3-way handshake.
    def connect(self, address):
        self.destination = address
        self.seq = random.randint(0, 100)
        _, self.destination = self._exchange(
            {"SYN": 1, "seq": self.seq},
            lambda s: s["SYN"] and s["ACK"] and s["seq"] == self.seq + 1)
        self.seq += 2
        self._send({"ACK": 1, "seq": self.seq}, timer=False)

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

    #send: bytes, str -> None
    #Envía message con el ARQ indicado en mode.
    def send(self, message, mode="stop_and_wait"):
        if mode == "stop_and_wait":
            self.send_using_stop_and_wait(message)
        elif mode == "go_back_n":
            self.send_using_go_back_n(message)

    #recv: int, str -> bytes
    #Recibe a lo más buff_size bytes con el ARQ indicado en mode.
    def recv(self, buff_size, mode="stop_and_wait"):
        if mode == "stop_and_wait":
            return self.recv_using_stop_and_wait(buff_size)
        elif mode == "go_back_n":
            return self.recv_using_go_back_n(buff_size)

    #send_using_stop_and_wait: bytes -> None
    #Envía el largo y luego trozos de 16 bytes, esperando el ACK de cada uno.
    def send_using_stop_and_wait(self, message):
        for chunk in [str(len(message)).encode()] + self.divide_message(message, DATA_SIZE):
            end = self.seq + len(chunk)
            self._exchange({"seq": self.seq, "data": chunk},
                           lambda s: s["ACK"] and not (s["SYN"] or s["FIN"]) and s["seq"] == end)
            self.seq = end

    #recv_using_stop_and_wait: int -> bytes
    #Retorna min(message_length, buff_size) bytes, guardando lo que sobre.
    def recv_using_stop_and_wait(self, buff_size):
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
            self._send({"ACK": 1, "seq": self.seq}, timer=False)
            if in_order:
                return seg["data"]

    #send_using_go_back_n: bytes -> None
    #Go-Back-N con ventana fija de 8 o dada por la cwnd de congestion_controler.
    def send_using_go_back_n(self, message):
        data_list = [str(len(message)).encode()] + self.divide_message(message, MSS)
        congestion_controler = CongestionControl(MSS)
        window_size = congestion_controler.get_MSS_in_cwnd() if self.congestion_control_on else GBN_WINDOW
        data_window = SlidingWindowCC(window_size, data_list, self.seq)
        if self.congestion_control_on:
            self._log_cc(congestion_controler, "inicio", window_size)
        sent = self._send_window(data_window, 0, window_size)
        while data_window.get_data(0) is not None:
            try:
                seg, _ = self._recv_segment()
            except TimeoutError:
                self._log(f"timeout, Go-Back-N desde seq={data_window.get_sequence_number(0)}")
                self.socketUDP.stop_timer()
                if self.congestion_control_on:
                    congestion_controler.event_timeout()
                    window_size = congestion_controler.get_MSS_in_cwnd()
                    data_window.update_window_size(window_size)
                    self._log_cc(congestion_controler, "timeout", window_size)
                sent = self._send_window(data_window, 0, window_size)
                continue
            moved = 0
            while self._acks(seg, data_window):
                data_window.move_window(1)
                moved += 1
            if moved:
                if self.congestion_control_on:
                    congestion_controler.event_ack_received()
                    window_size = congestion_controler.get_MSS_in_cwnd()
                    data_window.update_window_size(window_size)
                    self._log_cc(congestion_controler, "ack", window_size)
                start = max(sent - moved, 0)
                if data_window.get_data(start) is not None:
                    self.socketUDP.stop_timer()
                sent = self._send_window(data_window, start, window_size)
        self.socketUDP.stop_timer()
        self.seq += sum(len(data) for data in data_list)

    #recv_using_go_back_n: int -> bytes
    #El receptor de Go-Back-N es el mismo de Stop & Wait.
    def recv_using_go_back_n(self, buff_size):
        return self.recv_using_stop_and_wait(buff_size)

    #_acks: dict, SlidingWindowCC -> bool
    #True si seg es un ACK que cubre el primer elemento de la ventana.
    def _acks(self, seg, data_window):
        data = data_window.get_data(0)
        return (seg["ACK"] and not (seg["SYN"] or seg["FIN"]) and data is not None
                and seg["seq"] >= data_window.get_sequence_number(0) + len(data))

    #_send_window: SlidingWindowCC, int, int -> int
    #Envía los elementos start..window_size-1 de la ventana.
    def _send_window(self, data_window, start, window_size):
        for i in range(start, window_size):
            if data_window.get_data(i) is not None:
                self._send({"seq": data_window.get_sequence_number(i), "data": data_window.get_data(i)})
        return window_size

    #_log_cc: CongestionControl, str, int -> None
    #Modo debug de la ventana de congestión.
    def _log_cc(self, congestion_controler, event, window_size):
        self._log(f"[cc] {event}: {congestion_controler.current_state} cwnd={congestion_controler.get_cwnd():.2f} "
                  f"ssthresh={congestion_controler.get_ssthresh()} window_size={window_size}")

    #close: None -> None
    #Cierre desde Host A: FIN hasta 3 timeouts y luego el último ACK tres veces.
    def close(self):
        fin_ack, _ = self._exchange({"FIN": 1, "seq": self.seq},
                                    lambda s: s["FIN"] and s["ACK"] and s["seq"] == self.seq + 1, tries=3)
        if fin_ack:
            for _ in range(3):
                self._send({"ACK": 1, "seq": self.seq + 2}, timer=False)
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
                self._send({"ACK": 1, "seq": self.seq}, timer=False)
        self.seq = seg["seq"] + 1
        self._exchange({"FIN": 1, "ACK": 1, "seq": self.seq},
                       lambda s: s["ACK"] and not s["FIN"] and s["seq"] == self.seq + 1, tries=3)
        self.socketUDP.close()
