SLOW_START = "slow_start"
CONGESTION_AVOIDANCE = "congestion_avoidance"


class CongestionControl:
    #__init__: int -> CongestionControl
    #Parte en slow start con cwnd = 1 MSS y sin ssthresh.
    def __init__(self, MSS):
        self.MSS = MSS
        self.cwnd = MSS
        self.ssthresh = None
        self.current_state = SLOW_START

    #get_cwnd: None -> int
    #Tamaño de la ventana de congestión en bytes.
    def get_cwnd(self):
        return self.cwnd

    #get_MSS_in_cwnd: None -> int
    #Cantidad de MSS completos que caben en cwnd.
    def get_MSS_in_cwnd(self):
        return int(self.cwnd // self.MSS)

    #get_ssthresh: None -> int | None
    #Umbral de slow start.
    def get_ssthresh(self):
        return self.ssthresh

    #is_state_slow_start: None -> bool
    #True si estamos en slow start.
    def is_state_slow_start(self):
        return self.current_state == SLOW_START

    #is_state_congestion_avoidance: None -> bool
    #True si estamos en congestion avoidance.
    def is_state_congestion_avoidance(self):
        return self.current_state == CONGESTION_AVOIDANCE

    #event_ack_received: None -> None
    #Crece 1 MSS en slow start o MSS/(MSS en cwnd) en congestion avoidance.
    def event_ack_received(self):
        if self.is_state_slow_start():
            self.cwnd += self.MSS
            if self.ssthresh is not None and self.cwnd >= self.ssthresh:
                self.current_state = CONGESTION_AVOIDANCE
        else:
            self.cwnd += self.MSS / self.get_MSS_in_cwnd()

    #event_timeout: None -> None
    #ssthresh = int(cwnd/2), cwnd = 1 MSS y vuelta a slow start.
    def event_timeout(self):
        self.ssthresh = int(self.cwnd / 2)
        self.cwnd = self.MSS
        self.current_state = SLOW_START
