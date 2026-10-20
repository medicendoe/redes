import socket
from dnslib import DNSRecord, RR, A
from dnslib.dns import CLASS, QTYPE
import dnslib

RESOLVER_IP='localhost'
RESOLVER_PORT=8000
ROOT_IP='198.41.0.4'
DEBUG=True

def has_a_record(dns_parsed) -> bool:
    return any(r.rtype == QTYPE.A for r in dns_parsed.rr)

'''resolver: bytes 
'''
def resolver(mensaje_consulta: bytes, ip_addr=ROOT_IP) -> bytes:


    parsed_mensaje = DNSRecord.parse(mensaje_consulta)
    query_name = str(parsed_mensaje.q.qname).strip('.')
    server_address = (ip_addr, 53)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if ip_addr == ROOT_IP and DEBUG:
        print(f"(debug) Consultando '{query_name}' a '.' con dirección IP '{ip_addr}'")

    try:
        sock.sendto(mensaje_consulta, server_address)
        data, addr = sock.recvfrom(4096)
        parsed_data = DNSRecord.parse(data)

        if has_a_record(parsed_data):
            return data
        else:
            ns_names = [str(r.rdata) for r in parsed_data.auth if r.rtype == QTYPE.NS]
            if ns_names:
                a_in_additional = [str(r.rdata) for r in parsed_data.ar if r.rtype == QTYPE.A]
        
                if a_in_additional:
                    fip = a_in_additional[0]

                    if DEBUG:
                        nsf = str(ns_names[0]).strip('.')
                        print(f"(debug) Consultando '{query_name}' a '{nsf}' con dirección IP '{fip}'")

                    return resolver(mensaje_consulta, fip)
                else:
                    nsf = ns_names[0]
                    
                    query_para_ns = DNSRecord.question(nsf, "A").pack()
                    
                    nsr_bytes = resolver(query_para_ns)
                    
                    if nsr_bytes:
                        nsr_parsed = DNSRecord.parse(nsr_bytes)
                        
                        if has_a_record(nsr_parsed):
                            if DEBUG:
                                ip_ns = str([r.rdata for r in nsr_parsed.rr if r.rtype == QTYPE.A][0])
                                print(f"(debug) Consultando '{query_name}' a '{nsf}' con dirección IP '{ip_ns}'")

                            return resolver(mensaje_consulta, ip_ns)
    finally:
        sock.close()
    
    return None

# Bucle principal
if __name__ == "__main__":
    recent_queries = []
    cache = {}

    client_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    try:
        client_socket.bind((RESOLVER_IP, RESOLVER_PORT))
        print(f"Escuchando en {RESOLVER_IP}:{RESOLVER_PORT}...")
        
        while True:
            data, addr = client_socket.recvfrom(4096)
            
            parsed_query = DNSRecord.parse(data)
            query_name = str(parsed_query.q.qname).strip('.')
            resolved_ip = None
            
            if query_name in cache:
                
                resolved_ip = cache[query_name]
                reply = parsed_query.reply()
                reply.add_answer(RR(query_name, QTYPE.A, rdata=A(resolved_ip), ttl=60))
                client_socket.sendto(reply.pack(), addr)
            else:
                resp = resolver(data)
                if resp is not None:
                    parsed_resp = DNSRecord.parse(resp)
                    for r in parsed_resp.rr:
                        if r.rtype == QTYPE.A and str(r.rname).strip('.') == query_name:
                            resolved_ip = str(r.rdata)
                            break
                    
                    client_socket.sendto(resp, addr)

            if resolved_ip:
                recent_queries.append((query_name, resolved_ip))
                if len(recent_queries) > 20:
                    recent_queries.pop(0)

                frecuencias = {}
                for dom, _ in recent_queries:
                    if dom in frecuencias:
                        frecuencias[dom] += 1
                    else:
                        frecuencias[dom] = 1
                
                dominios_ordenados = sorted(frecuencias.keys(), key=lambda d: frecuencias[d], reverse=True)
                top_3_dominios = dominios_ordenados[:3]
                
                cache.clear()
                for dom in top_3_dominios:
                    for dq, dip in reversed(recent_queries):
                        if dq == dom:
                            cache[dom] = dip
                            break

    finally:
        client_socket.close()