from router import check_routes, create_packet, parse_packet, round_robin

R = lambda puerto: ("127.0.0.1", puerto)

# Test parse_packet y create_packet (con TTL)
IP_packet_v1 = bytes([127, 0, 0, 1]) + (8885).to_bytes(2, "big") + bytes([10]) + "hola".encode()
parsed_IP_packet = parse_packet(IP_packet_v1)
IP_packet_v2 = create_packet(parsed_IP_packet)
print("IP_packet_v1 == IP_packet_v2 ? {}".format(IP_packet_v1 == IP_packet_v2))

# Test check_routes con los routers del ejemplo 2
print("R1 hacia R3:", check_routes("rutas/rutas_R1_v2.txt", R(8883)))
print("R2 hacia R3:", check_routes("rutas/rutas_R2_v2.txt", R(8883)))
print("R3 hacia R1:", check_routes("rutas/rutas_R3_v2.txt", R(8881)))
print("R1 hacia 127.0.0.1:8884:", check_routes("rutas/rutas_R1_v2.txt", R(8884)))

# Test round-robin: R2 de la red de 5 routers hacia R5, y R3 alternando entre dos áreas
round_robin.clear()
print("R2 hacia R5 cuatro veces:", [check_routes("rutas/rutas_R2_v3.txt", R(8885))[1] for _ in range(4)])
round_robin.clear()
print("R3 hacia R5, R1, R5, R1:", [check_routes("rutas/rutas_R3_v3.txt", R(p))[1] for p in (8885, 8881, 8885, 8881)])
