# Actividad: Sockets orientados a conexión con Stop & Wait (CC4303)

TCP simplificado sobre UDP: 3-way handshake, Stop & Wait y cierre de conexión.

## Correr todo

```sh
./run.sh
```

Crea `.venv`, corre los tests con y sin pérdida (alrededor de un minuto) y compila `informe/main.pdf`.

## A mano

```sh
python3 servidor.py localhost 8000 > recibido.txt
python3 cliente.py localhost 8000 < archivo.txt
```

Variables de entorno: `LOSS=0.2` (pérdida simulada), `TIMEOUT=0.5`, `DEBUG=1`, `LOSE_HANDSHAKE_ACK=1`.

## Archivos

| Archivo | Contenido |
|---|---|
| `SocketTCP.py` | Segmentos, handshake, Stop & Wait y cierre |
| `cliente.py`, `servidor.py` | Envío de un archivo por stdin |
| `client_test.py`, `server_test.py` | Tests del curso, más un Test 4 y el cierre |
| `informe/main.typ`, `informe/diagramas.typ` | Informe y sus diagramas |
