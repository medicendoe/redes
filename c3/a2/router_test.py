from router import check_routes, create_packet, fragment_IP_packet, parse_packet, reassemble_IP_packet

# Test parse_packet y create_packet con el paquete "hola!" del enunciado
IP_packet_v1 = (bytes([127, 0, 0, 1]) + (8885).to_bytes(2, "big") + bytes([10]) + (347).to_bytes(4, "big")
                + (0).to_bytes(4, "big") + (5).to_bytes(4, "big") + bytes([0]) + "hola!".encode())
parsed_IP_packet = parse_packet(IP_packet_v1)
IP_packet_v2 = create_packet(parsed_IP_packet)
print("IP_packet_v1 == IP_packet_v2 ? {}".format(IP_packet_v1 == IP_packet_v2))

# Test check_routes con MTU
print("R1 hacia R5:", check_routes("rutas/rutas_R1_v3_mtu.txt", ("127.0.0.1", 8885)))
print("R2 hacia R5:", check_routes("rutas/rutas_R2_v3_mtu.txt", ("127.0.0.1", 8885)))

# Test fragment_IP_packet con un paquete de 150 bytes (20 de header y 130 de mensaje)
mensaje = ("Un paquete de 150 bytes: 20 de header y 130 de mensaje, justo lo necesario para que "
           "ningún enlace de la red lo deje pasar entero.").encode()
IP_packet_v1 = create_packet({"IP": "127.0.0.1", "puerto": 8885, "TTL": 10, "ID": 1, "offset": 0,
                              "tamaño": len(mensaje), "FLAG": 0, "mensaje": mensaje})
for MTU in (150, 100, 50):
    fragment_list = fragment_IP_packet(IP_packet_v1, MTU)
    print(f"MTU {MTU}: {len(fragment_list)} fragmentos de {[len(f) for f in fragment_list]} bytes")

# Test fragment_IP_packet y reassemble_IP_packet
fragment_list = fragment_IP_packet(IP_packet_v1, 50)
IP_packet_v2 = reassemble_IP_packet(fragment_list)
print("IP_packet_v1 = IP_packet_v2 ? {}".format(IP_packet_v1 == IP_packet_v2))
print("en desorden:", reassemble_IP_packet(fragment_list[::-1]) == IP_packet_v1)
print("sin el último fragmento:", reassemble_IP_packet(fragment_list[:-1]))

# Test re-fragmentar: MTU 100 (R1 -> R2) y luego MTU 50 (R2 -> R3)
fragment_list = [g for f in fragment_IP_packet(IP_packet_v1, 100) for g in fragment_IP_packet(f, 50)]
print("re-fragmentado (offset, tamaño, FLAG):",
      [(p["offset"], p["tamaño"], p["FLAG"]) for p in map(parse_packet, fragment_list)])
print("IP_packet_v1 = IP_packet_v2 ? {}".format(IP_packet_v1 == reassemble_IP_packet(fragment_list)))
