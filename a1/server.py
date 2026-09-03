import socket

BUFF_SIZE = 32
LINE_BRAKE = '\r\n'
SEPARATOR = '\r\n'
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

    body = strip(deco_message.split(SEPARATOR)[1])
    start = ""
    head = {}

    raw_head = deco_message.split(SEPARATOR)[0]
    for index, header_raw in enumerate(raw_head.split(LINE_BRAKE)):
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
    final_message = f'{http_message.start}{SEPARATOR}'

    for key, value in http_message.head.item():
        final_message += f'{key}: {value}{SEPARATOR}'
    
    final_message += f'{SEPARATOR}{http_message.body}'

    return final_message.encode









def receive_full_message(connection_socket):

    recv_message = connection_socket.recv(BUFF_SIZE)
    full_message = recv_message

    is_end_of_message = contains_end_of_message(full_message.decode())

    while not is_end_of_message:
        recv_message = connection_socket.recv(BUFF_SIZE)

        full_message += recv_message

        is_end_of_message = contains_end_of_message(full_message.decode())

    full_message = remove_end_of_message(full_message.decode())

    return full_message

''' contains_end_of_message: String -> Bool
Retorna true si la primera string contiene el caracter de cierre o no.
'''
def contains_end_of_message(message: str):
    return message.endswith(END_SEQ)

''' remove_end_of_message: String -> String
Retorna una subcadena de la primera excluyendo todo lo que viene luego del caracter de cierre especificado.
'''
def remove_end_of_message(full_message):
    index = full_message.rfind(END_SEQ)
    return full_message[:index]



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