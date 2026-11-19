# Actividad: Forwarding básico (CC4303)

Mini-Internet sobre sockets UDP: routers con tabla de rutas, round-robin entre rutas alternativas, router
default y TTL.

## Correr todo

```sh
./run.sh
```

Crea `.venv`, corre los tests de `router_test.py` y levanta las redes de 2, 3, 5 y 7 routers para las
pruebas del informe (unos 15 segundos). Los logs de cada router quedan en `resultados/`. Si `typst` está
instalado, compila `informe/main.pdf`.

## A mano

```sh
python3 router.py 127.0.0.1 8881 rutas/rutas_R1_v3.txt          # un router por terminal
python3 enviar.py "127.0.0.1;8885;10" "hola" 127.0.0.1 8881       # headers, mensaje, router inicial
python3 prueba_router.py "127.0.0.1;8885;10" 127.0.0.1 8881 < archivo.txt
```

- Los headers van como `IP;puerto;TTL`, entre comillas porque `;` separa comandos en la shell. El TTL es
  opcional (64 por defecto).
- `NO_TTL=1` hace que el router ignore el TTL, para reproducir la parte sin TTL.

## Archivos

| Archivo | Contenido |
|---|---|
| `router.py` | `parse_packet`, `create_packet`, `check_routes` con round-robin y el loop del router |
| `enviar.py` | Envía un paquete (paso 5) |
| `prueba_router.py` | Envía un archivo línea por línea desde stdin (parte con TTL, paso 4) |
| `router_test.py` | Tests de las funciones |
| `rutas/` | Tablas: `v1` y `v2` (ejemplos 1 y 2), `v2_mal`, `v3` (5 routers), `v3_default`, `v4` (7 routers) |
| `archivo.txt` | Archivo de 31 líneas para `prueba_router.py` |
| `informe/main.typ`, `informe/diagramas.typ` | Informe y sus diagramas |
