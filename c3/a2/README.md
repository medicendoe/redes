# Actividad: Fragmentación (CC4303)

El mini-Internet de forwarding básico, ahora con MTU por enlace: los routers fragmentan los datagramas
(y los fragmentos) que no caben, y el router de destino los reensambla.

## Correr todo

```sh
./run.sh
```

Crea `.venv`, corre `router_test.py`, envía fragmentos a mano a R5 (paso 7) y levanta la red de 5 routers
con MTU para las pruebas del informe (unos 10 segundos). Los logs de cada router quedan en `resultados/`. Si
`typst` está instalado, compila `informe/main.pdf`.

## A mano

```sh
python3 router.py 127.0.0.1 8881 rutas/rutas_R1_v3_mtu.txt                    # un router por terminal
python3 enviar.py "127.0.0.1;8885;10;347;0;5;0" "hola!" 127.0.0.1 8881         # headers, mensaje, router inicial
```

- Headers: `IP;puerto;TTL;ID;offset;tamaño;FLAG`. Desde el TTL son opcionales: TTL 64, ID al azar, offset 0,
  tamaño el del mensaje y FLAG 0.
- `DEBUG=1` imprime en stderr cada trozo que llega a su destino.

## Archivos

| Archivo | Contenido |
|---|---|
| `router.py` | Header de 20 bytes, `check_routes` con MTU, `fragment_IP_packet`, `reassemble_IP_packet` y el router |
| `enviar.py` | El script de envío de forwarding básico con el header nuevo |
| `router_test.py` | Tests de las funciones (pasos 1 a 5) |
| `fragmentos_test.py` | Envía a R5 dos listas de fragmentos en orden, en desorden e intercaladas (paso 7) |
| `rutas/` | Tablas de rutas con MTU de la red de 5 routers |
| `informe/main.typ`, `informe/diagramas.typ` | Informe y su diagrama |
