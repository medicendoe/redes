import socket

BUFF_SIZE = 32
LINE_BREAK = '\r\n'
HEAD_SEPARATOR = '\r\n\r\n'
HEADER_SEPARATOR = ':'


''' HTTP_message
Clase utilitaria para almacenar de manera estructurada la informacion de un mensaje html.
'''
class HTTP_message:

    def __init__(self, start: str, head: dict, body: str):
        self.start = start
        self.head = head
        self.body = body

''' parse_HTTP_message: bytes -> HTTP_message
Toma un mensaje http bien estructurado en bytes y retorna su verision en la clase utilitaria antes creada.
'''
def parse_HTTP_message(http_message: bytes) -> HTTP_message:
    deco_message = http_message.decode()

    body = (deco_message.split(HEAD_SEPARATOR)[1]).strip()
    start = ""
    head = {}

    raw_head = deco_message.split(HEAD_SEPARATOR)[0]
    for index, header_raw in enumerate(raw_head.split(LINE_BREAK)):
        if index == 0:
            start = header_raw
            continue

        header_split = header_raw.split(HEADER_SEPARATOR)
        head[strip(header_split[0])] = strip(header_split[1])

    return HTTP_message(start, head, body)

''' create_HTTP_message: HTTP_message -> bytes
Toma un mensaje correctamente formado por nuestra estructura y retorna este mensaje formateado como bytes.
'''
def create_HTTP_message(http_message: HTTP_message) -> bytes:
    final_message = f'{http_message.start}{LINE_BREAK}'

    for key, value in http_message.head.item():
        final_message += f'{key}{HEADER_SEPARATOR} {value}{LINE_BREAK}'
    
    final_message += f'{LINE_BREAK}{http_message.body}'

    return final_message.encode

'''contains_end_of_head: string -> bool
Devuelve si la cadena contiene el final del head
'''
def contains_end_of_head(message: str) -> bool:
    return message.endswith(HEAD_SEPARATOR)

''' get_body_count: bytes -> int
Devuelve la cantidad de bytes recibidos en el body
'''
def get_body_count(message: bytes) -> int:
    index = message.rfind(HEAD_SEPARATOR)
    return len(message) - (index + 1)

'''get_body_length: str -> int
Toma el head de un http y entrega el largo del body
'''
def get_body_length(head: str) -> int:
    head_lower = head.lower()
    
    if 'content-length:' not in head_lower:
        return 0
        
    return int((head_lower.split('content-length:')[1].split(LINE_BREAK)[0]).strip())

''' receive_full_http_message: Socket -> bytes
Toma un socket y retorna el mensaje completo.
'''
def receive_full_http_message(connection_socket):

    recv_message = connection_socket.recv(BUFF_SIZE)
    full_message = recv_message

    while not contains_end_of_head(full_message.decode()):
        recv_message = connection_socket.recv(BUFF_SIZE)
        full_message += recv_message

    body_length = get_body_length(full_message)

    while body_length < get_body_count(full_message):
        recv_message = connection_socket.recv(BUFF_SIZE)
        full_message += recv_message
    
    if body_length == get_body_count(full_message):
        return full_message
    else:
        return full_message[:get_body_count(full_message)-body_length]


# Bucle principal
if __name__ == "__main__":
    end_of_message = "\n"
    server_socket_address = ('localhost', 5000)

    print('Creando socket - Servidor')
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)

    server_socket.bind(server_socket_address)

    server_socket.listen(3)

    print('... Esperando clientes')
    while True:
        new_socket, new_socket_address = server_socket.accept()

        recv_message = receive_full_message(new_socket, buff_size, end_of_message)

        print(f' -> Se ha recibido el siguiente mensaje: {recv_message}')

        response_message = f"Se ha sido recibido con éxito el mensaje: {recv_message}"

        new_socket.send(response_message.encode())

        new_socket.close()
        print(f"conexión con {new_socket_address} ha sido cerrada")