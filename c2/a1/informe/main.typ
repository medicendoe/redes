#import "diagramas.typ": handshake, sin-solucion, con-solucion

#set document(title: "Informe 3: Sockets orientados a conexión con Stop & Wait", author: "Gabriel Gallardo R.")
#set page(paper: "a4", margin: 2.5cm, numbering: "1")
#set text(font: "New Computer Modern", size: 11pt, lang: "es")
#set par(justify: true)
#set heading(numbering: "1.1.")
#set list(spacing: 0.8em)
#show heading: set block(above: 1.4em, below: 0.8em)
#show raw.where(block: true): set text(size: 7.5pt)
#show raw.where(block: true): it => block(fill: luma(246), inset: 8pt, radius: 3pt, width: 100%, it)
#show figure.caption: set text(size: 9pt)

#align(center)[
  #text(size: 18pt, weight: "bold")[Informe 3: Sockets orientados a conexión con Stop & Wait] \
  #v(1em)
  #text(size: 12pt)[Gabriel Gallardo R.] \
  #link("https://github.com/medicendoe/redes")[github.com/medicendoe/redes]
]

= Declaración de uso de IA

Este trabajo utilizó modelos de Inteligencia Artificial. Se utilizó Claude (Anthropic) durante el
desarrollo del código y en la redacción de este informe.

= Ejecución del código

UDP es un cartero sin memoria: entrega cuando puede y no promete nada. En esta actividad le construimos
encima un TCP simplificado, la clase `SocketTCP`, con 3-way handshake, envío confiable con Stop & Wait y
cierre de conexión, todo sobre un socket UDP y su `settimeout`. El código está en la carpeta `a1` del
repositorio. Para correr todas las pruebas:

```bash
./run.sh
```

`run.sh` crea un entorno virtual, corre los tests del curso (`server_test.py` y `client_test.py`) y envía
`archivo.txt` con y sin pérdida. Para transmitir un archivo a mano, en dos terminales:

```bash
python3 servidor.py localhost 8000 > recibido.txt
python3 cliente.py localhost 8000 < archivo.txt
```

Las variables de entorno `LOSS`, `TIMEOUT`, `DEBUG` y `LOSE_HANDSHAKE_ACK` controlan la pérdida simulada, el
timeout, el modo debug y el caso borde del handshake (@perdidas).

= Diseño

== Segmentos

#figure(
  table(
    columns: (3.2cm, 4cm, 3.6cm),
    align: center + horizon,
    inset: 6pt,
    [*flags*], [*seq*], [*datos*],
    [1 byte \ `SYN` `ACK` `FIN`], [4 bytes, _big-endian_], [hasta 16 bytes],
  ),
  caption: [Formato del segmento: 5 bytes de header seguidos de los datos.],
) <segmento>

Los headers son bytes crudos (@segmento): un byte con los flags SYN, ACK y FIN en sus bits 0, 1 y 2, y cuatro
bytes con el número de secuencia. `parse_segment` los convierte en un diccionario
`{"SYN", "ACK", "FIN", "seq", "data"}` y `create_segment` hace el camino de vuelta. Un header fijo de 5 bytes
permite que el buffer del socket UDP sea siempre de 5 + 16 = 21 bytes, independiente del `buff_size` que
pida la aplicación. Los números de secuencia cuentan bytes y los ACK llevan el siguiente byte que el receptor
espera.

== 3-way handshake

#figure(handshake, kind: image, caption: [3-way handshake y las funciones que ejecutan cada paso.]) <fig-handshake>

`connect` elige $x$ al azar entre 0 y 100, envía SYN y espera el SYN+ACK reenviando ante cada timeout.
`accept` espera un SYN en el socket que escucha, crea un `SocketTCP` nuevo con la misma IP y puerto 0, para
que el sistema operativo le asigne uno libre, y responde el SYN+ACK _desde ese socket nuevo_. Así el cliente
aprende la dirección de la conexión mirando el origen del SYN+ACK, y el socket que escucha queda libre
(@fig-handshake). Ambos extremos terminan con `seq` = $x+2$, el número del primer byte de datos.

== Stop & Wait

Estas son las decisiones de diseño del paso 5:

- *`send(message)`* envía primero un segmento con `str(len(message))` y luego el mensaje en trozos de 16
  bytes. Cada trozo espera su ACK (`seq + len`) con un timeout fijo de 0.5 s; si vence, se reenvía. Cada
  llamada parte desde el último `seq` almacenado.
- *`recv(buff_size)`* usa dos atributos: `left`, los bytes del mensaje actual que aún no se entregan, y
  `buffer`, lo recibido que todavía no sale. Si `left` es 0, el próximo segmento es un `message_length`.
  Luego recibe hasta juntar `min(left, buff_size)` bytes, entrega exactamente eso y guarda el resto. Un
  segmento de 16 bytes puede traer más de lo pedido (por ejemplo con `recv(14)`), pero lo que sobra espera
  en `buffer` a la siguiente llamada: nunca se entregan más de `buff_size` bytes y nada se pierde.
- El receptor responde a *todo* segmento de datos con el ACK del siguiente byte esperado. Si llega un
  duplicado, porque se perdió un ACK, lo descarta y vuelve a confirmar.

== Cierre

`close()` (Host A) envía FIN y espera FIN+ACK, reenviando hasta 3 timeouts. Si llega, envía el último ACK
tres veces con un timeout entre cada uno; si no, asume que la contraparte se cerró. `recv_close()` (Host B)
espera el FIN, contestando mientras tanto cualquier dato atrasado, responde FIN+ACK y espera el ACK final
hasta 3 timeouts.

== Caso borde: se pierde el último ACK del handshake

#figure(sin-solucion, kind: image, caption: [Sin solución: cada lado ignora lo que envía el otro.]) <fig-sin>

Si el ACK $x+2$ se pierde, el cliente ya cree estar conectado y empieza a enviar datos, mientras el servidor
sigue en `accept` esperando un ACK. Cada uno ignora lo que manda el otro y ambos retransmiten para siempre
(@fig-sin). La solución sale del mismo diagrama: un segmento de datos con `seq` = $x+2$ solo puede venir de
un cliente que recibió el SYN+ACK. Por lo tanto `accept` lo acepta como confirmación implícita, descarta sus
datos y retorna; el cliente, sin ACK para ese segmento, lo reenvía tras su timeout y `recv` lo recibe
normalmente (@fig-con).

#figure(con-solucion, kind: image, caption: [Con solución: los datos con el seq esperado
  cuentan como ACK.]) <fig-con>

== Pérdidas y modo debug <perdidas>

Las pérdidas se simulan a mano, sin netem: cada socket descarta lo que recibe con probabilidad `LOSS`
(variable de entorno o global en `SocketTCP.py`). Como ambos extremos descartan, hay pérdidas en las dos
direcciones, incluidos handshake y cierre. Para probar el caso borde anterior, `LOSE_HANDSHAKE_ACK=1` hace
que el cliente no envíe el último ACK del handshake. Con `DEBUG=1` cada línea muestra el puerto del socket y
un evento: `->` envío, `<-` recepción, `xx` pérdida y `timeout`.

```
LOSS=0.2 DEBUG=1 python3 servidor.py localhost 8000 > recibido.txt
LOSS=0.2 DEBUG=1 python3 cliente.py localhost 8000 < archivo.txt
```

== Otras situaciones borde <bordes>

- `settimeout` reinicia la espera con cada recepción, así que un segmento inesperado alarga el timeout en
  curso. No rompe la corrección, pero puede retrasar un reenvío.
- Si se pierde el ACK del último trozo, el emisor reenvía cuando el receptor ya salió de `recv`. La
  siguiente llamada a `recv` o `recv_close` lo vuelve a confirmar.
- Si se pierden todos los FIN del cliente, `recv_close` espera indefinidamente; el enunciado le pide cerrar
  una vez que el FIN llega, y el cliente se rinde tras 3 timeouts.
- Los números de secuencia no dan la vuelta: con 4 bytes, una conexión alcanza para unos 4 GB.

= Pruebas

== Integridad

`server_test.py` y `client_test.py` son los tests del curso (Tests 1 a 3). Se les agregó solo lo necesario
para correrlos (el `import` de `SocketTCP` y la dirección), las líneas de cierre que pide el paso 6 y un Test 4
con el mismo formato: 74 bytes leídos con dos `recv(37)`, pues 37 no es múltiplo de 16. También se envió
`archivo.txt` (1316 bytes) con `cliente.py` y `servidor.py`, comparando lo recibido con el original mediante
`cmp`. Todo se corrió sin pérdida y con `LOSS=0.2` (@integridad).

#figure(
  table(
    columns: 3,
    stroke: none,
    align: (left, center, center),
    table.hline(),
    [*prueba*], [*sin pérdida*], [*20 % de pérdida*],
    table.hline(stroke: 0.5pt),
    [Tests 1 a 4], [Passed], [Passed],
    [`archivo.txt` con `cmp`], [íntegro], [íntegro],
    [Cierre de ambos extremos], [sí], [sí],
    [Último ACK del handshake perdido], [íntegro], [-],
    table.hline(),
  ),
  caption: [Resultados de `./run.sh`.],
) <integridad>

== Manejo de pérdidas

Inicio del modo debug al enviar `archivo.txt` con 20 % de pérdida. Se ven pérdidas en ambas direcciones
(`xx`), los timeouts que las detectan y los reenvíos que las reparan; cuando lo perdido es un ACK, el
receptor recibe un duplicado y vuelve a confirmar. En todo el envío, contando ambos extremos, hubo 50 pérdidas y 50 timeouts.

```
[51946] -> SYN seq=11
[8000] <- SYN seq=11
[38977] -> SYN+ACK seq=12
[51946] <- SYN+ACK seq=12
[51946] -> ACK seq=13
[38977] <- ACK seq=13
[51946] -> DATA seq=13 len=4
[38977] <- DATA seq=13 len=4
[38977] -> ACK seq=17
[51946] <- ACK seq=17
[51946] -> DATA seq=17 len=16
[38977] <- DATA seq=17 len=16
[38977] -> ACK seq=33
[51946] xx ACK seq=33 (pérdida simulada)
[51946] timeout
[51946] -> DATA seq=17 len=16
[38977] <- DATA seq=17 len=16
[38977] -> ACK seq=33
[51946] <- ACK seq=33
[51946] -> DATA seq=33 len=16
...
[51946] -> DATA seq=65 len=16
[38977] xx DATA seq=65 len=16 (pérdida simulada)
[51946] timeout
[51946] -> DATA seq=65 len=16
[38977] <- DATA seq=65 len=16
```

== ACK final del handshake perdido

Con `LOSE_HANDSHAKE_ACK=1` el cliente nunca envía el ACK $x+2$. El servidor recibe los datos con
`seq` = $x+2$, los toma como confirmación y la transferencia sigue tras un timeout del cliente, tal como en la
@fig-con:

```
[36566] -> SYN seq=76
[8000] <- SYN seq=76
[59967] -> SYN+ACK seq=77
[36566] <- SYN+ACK seq=77
[36566] xx ACK seq=78 (pérdida forzada)
[36566] -> DATA seq=78 len=4
[59967] <- DATA seq=78 len=4
[36566] timeout
[36566] -> DATA seq=78 len=4
[59967] <- DATA seq=78 len=4
[59967] -> ACK seq=82
[36566] <- ACK seq=82
```

== Cierre con pérdidas

En todas las corridas ambos extremos cerraron. El final del envío con pérdida es un buen ejemplo: se perdieron
dos FIN y dos FIN+ACK, así que el cliente agotó sus 3 timeouts y cerró asumiendo que la contraparte ya lo
había hecho, y el servidor, sin recibir el ACK final, hizo lo mismo tras los suyos.

```
[51946] -> FIN seq=1333
[38977] xx FIN seq=1333 (pérdida simulada)
[51946] timeout
[51946] -> FIN seq=1333
[38977] <- FIN seq=1333
[38977] -> ACK+FIN seq=1334
[51946] xx ACK+FIN seq=1334 (pérdida simulada)
[38977] timeout
[51946] timeout
[51946] -> FIN seq=1333
[38977] -> ACK+FIN seq=1334
[51946] xx ACK+FIN seq=1334 (pérdida simulada)
[38977] xx FIN seq=1333 (pérdida simulada)
[38977] timeout
[51946] timeout
[38977] -> ACK+FIN seq=1334
[38977] timeout
```

= Conclusiones

Con un header de 5 bytes, un timer y algo de paciencia, UDP terminó entregando archivos completos aunque una
de cada cinco cosas se perdiera en el camino. El precio es la velocidad: Stop & Wait mantiene un solo
segmento en vuelo y cada pérdida cuesta un timeout completo; enviar `archivo.txt` con 20 % de pérdida costó cerca de
50 timeouts de medio segundo. Ese cuello de botella es precisamente lo que resuelve la siguiente actividad con
Go-Back-N.
