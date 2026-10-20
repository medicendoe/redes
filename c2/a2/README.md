# Actividad: Control de congestión (CC4303)

TCP simplificado sobre UDP con Stop & Wait, Go-Back-N y control de congestión estilo TCP Tahoe.

## Correr todo

```sh
./run.sh
```

Crea `.venv`, corre el test de `CongestionControl`, los tests en los tres modos con y sin pérdida, el modo
debug y la comparación con y sin control de congestión (unos 8 minutos por los timeouts), y compila
`informe/main.pdf`.

## A mano

```sh
python3 servidor.py localhost 8000 [modo] > recibido.txt
python3 cliente.py localhost 8000 [modo] [cc] < archivo.txt
```

- `modo`: `stop_and_wait` o `go_back_n` (por defecto).
- `cc`: activa el control de congestión.
- Variables de entorno: `LOSS=0.2` (pérdida simulada), `TIMEOUT=0.5`, `DEBUG=1`.

## Archivos

| Archivo | Contenido |
|---|---|
| `CongestionControl.py` | Parte 1: slow start y congestion avoidance |
| `SocketTCP.py` | Handshake, cierre, Stop & Wait, Go-Back-N y control de congestión |
| `socketUDP.py`, `slidingWindowCC.py`, `CongestionControl_test.py` | Archivos del curso, sin cambios |
| `client_test.py`, `server_test.py` | Tests del curso con el modo como argumento, más un Test 4 y el cierre |
| `cliente.py`, `servidor.py` | Envío de un archivo por stdin |
| `informe/main.typ` | Informe |
