#set document(title: "Informe 4: Control de congestión", author: "Gabriel Gallardo R.")
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
  #text(size: 18pt, weight: "bold")[Informe 4: Control de congestión] \
  #v(1em)
  #text(size: 12pt)[Gabriel Gallardo R.] \
  #link("https://github.com/medicendoe/redes")[github.com/medicendoe/redes]
]

= Declaración de uso de IA

Este trabajo utilizó modelos de Inteligencia Artificial. Se utilizó Claude (Anthropic) durante el 
desarrollo del código y en la redacción del informe.

= Ejecución del código

Nuestro TCP de la actividad anterior era confiable, pero tenía algo de ventanilla de banco: atendía un
segmento a la vez y no llamaba al siguiente hasta recibir su ACK. En esta actividad le enseñamos dos
cosas. Primero, a mantener varios segmentos en vuelo con Go-Back-N. Segundo, a no abusar de esa libertad,
con un control de congestión inspirado en TCP Tahoe (_slow start_ y _congestion avoidance_) que ajusta la
ventana según lo que la red deja pasar.

El código está en la carpeta `a2` del repositorio. `CongestionControl.py` resuelve la parte 1 y
`SocketTCP.py`, copia del de la actividad anterior, suma Go-Back-N y control de congestión. `socketUDP.py`,
`slidingWindowCC.py` y `CongestionControl_test.py` se usan tal como los entrega el curso. Para correr todas
las pruebas:

```bash
./run.sh
```

`run.sh` crea un entorno virtual y corre el test de `CongestionControl`, los tests del curso
(`server_test.py` y `client_test.py`) en los tres modos con y sin pérdida, el modo debug y la comparación de
la @comparar. Para transmitir un archivo a mano, en dos terminales:

```bash
python3 servidor.py localhost 8000 go_back_n > recibido.txt
python3 cliente.py localhost 8000 go_back_n cc < archivo.txt
```

El modo puede ser `stop_and_wait` o `go_back_n`, y `cc` activa el control de congestión. Las variables de
entorno `LOSS`, `TIMEOUT` y `DEBUG` controlan la pérdida simulada, el timeout y el modo debug.

= Antes de programar

*¿Por qué partir desde Stop & Wait? ¿Qué tienen en común?* Porque Stop & Wait _es_ Go-Back-N con ventana
de tamaño 1. Ambos usan un único timer, retransmiten ante un timeout y confían en un receptor que solo
acepta segmentos en orden. El ejemplo de la sección anterior ya escribe Stop & Wait sobre `SlidingWindowCC`:
una ventana, un `move_window(1)` cuando llega el ACK y un reenvío cuando vence el timer. Go-Back-N solo
agranda la ventana y cambia tres detalles: un ACK puede avanzarla $k$ espacios (los ACK son acumulativos),
esos $k$ elementos nuevos se envían de corrido, y ante un timeout se reenvía la ventana entera en vez de un
segmento.

*¿Qué pasa con `recv`? ¿Cambia con `SocketUDP` y `SlidingWindowCC`?* No cambia. El receptor de Go-Back-N
tiene ventana de tamaño 1: acepta únicamente el segmento con el número de secuencia esperado, descarta el
resto y responde siempre con el ACK del último byte recibido en orden. Eso es justo lo que ya hacía el
receptor de Stop & Wait. Tampoco necesita las clases nuevas: una ventana de un elemento cabe en una variable
(`self.seq`) y el receptor nunca retransmite, así que no requiere timers. Por eso `recv_using_go_back_n`
simplemente llama a `recv_using_stop_and_wait`. El único cuidado es que en `SocketUDP` todo `sendto` inicia un
timer, de modo que el receptor lo detiene tras cada ACK para no recibir timeouts que nunca pidió.

= Implementación y decisiones de diseño

== Segmentos y números de secuencia

#figure(
  table(
    columns: (3.2cm, 4cm, 5cm),
    align: center + horizon,
    inset: 6pt,
    [*flags*], [*seq*], [*datos*],
    [1 byte \ `SYN` `ACK` `FIN`], [4 bytes, _big-endian_], [hasta 16 bytes \ (8 en Go-Back-N)],
  ),
  caption: [Formato del segmento: 5 bytes de header seguidos de los datos.],
) <segmento>

El header ocupa 5 bytes (@segmento). Los números de secuencia cuentan bytes, igual que `SlidingWindowCC`,
y los ACK son acumulativos: llevan el siguiente byte que el receptor espera. El handshake usa $x$, $x+1$ y
$x+2$, con $x$ aleatorio entre 0 y 100, y el cierre repite el patrón a partir del último número de secuencia.
El primer segmento de cada mensaje lleva su largo, como en la actividad anterior.

== CongestionControl

La clase sigue el enunciado: parte en _slow start_ con `cwnd` = 1 MSS y `ssthresh = None`. Las decisiones
que el enunciado deja abiertas fueron:

- En _slow start_ cada ACK suma 1 MSS; en _congestion avoidance_ suma `MSS / get_MSS_in_cwnd()`, así que
  `cwnd` puede quedar fraccionario. `get_MSS_in_cwnd()` usa división entera, `cwnd // MSS`.
- El paso a _congestion avoidance_ se revisa después de cada aumento (`cwnd >= ssthresh`).
- Todo timeout, no solo el primero, deja `cwnd` en 1 MSS, vuelve a _slow start_ y hace
  `ssthresh = int(cwnd/2)`: el test del curso espera un entero (`int(5/2*MSS)`). Si `ssthresh` queda bajo
  1 MSS, el salto a _congestion avoidance_ ocurre con el siguiente ACK.

`CongestionControl_test.py` pasa con su `MSS = 7` y, cambiando esa variable, también con 1, 4, 8 y 13.

== Go-Back-N

`send_using_go_back_n` divide el mensaje en trozos de MSS = 8 bytes (`data_list`), antecedidos por el
segmento con el largo, y los carga en una `SlidingWindowCC` (`data_window`). Un único timer (el índice 0 de
`SocketUDP`) vigila la ventana. Cada ACK mueve la ventana de a un paso mientras cubra al primer elemento, y
luego se envían, uno tras otro, los elementos que entraron. Ante un timeout se reenvía la ventana completa.
Sin control de congestión la ventana mide 8 segmentos.

Avanzar de a un paso resuelve de paso el caso borde del enunciado: si la ventana se achicó justo después de
enviar su último elemento y llega un ACK que la sobrepasa, el ciclo sigue avanzando hasta que el ACK cae
dentro.

El timer requiere dos cuidados, porque `SocketUDP` no reinicia un timer que ya está corriendo y un timer
vencido no puede volver a partir. Ante un timeout se llama a `stop_timer()` antes de reenviar; sin eso,
`sendto` falla con `RuntimeError`. Y cuando un ACK hace avanzar la ventana, el timer se detiene justo antes
de enviar los elementos nuevos, que lo vuelven a iniciar. Si no hay elementos nuevos, el timer sigue
corriendo, para que ningún segmento en vuelo quede sin timeout.

== Integración del control de congestión

Dentro de `send_using_go_back_n` se crea `congestion_controler = CongestionControl(8)`, y con
`congestion_control_on = True` (vía `set_congestion_control`) la ventana `data_window` se inicializa con
`window_size = congestion_controler.get_MSS_in_cwnd()`.

*¿Qué valor debería tener `window_size` en ese punto?* 1. La `cwnd` parte en 1 MSS = 8 bytes, y en 8 bytes
cabe exactamente un MSS. Así se ve en el modo debug: la primera línea `[cc]` del registro de la @sin-perdida
dice `inicio: slow_start cwnd=8.00 ssthresh=None window_size=1`.

`event_ack_received()` se invoca una vez por cada ACK que hace avanzar la ventana, aunque confirme varios
segmentos; los ACK duplicados se ignoran, pues esta versión de Tahoe no implementa _fast retransmit_.
`event_timeout()` se invoca en cada timeout, antes de reenviar. Tras cada evento, `window_size` toma el valor
de `get_MSS_in_cwnd()` y la ventana se ajusta con `update_window_size`: si crece, los elementos nuevos se
envían de inmediato; si se achica, los que quedan fuera se reenviarán cuando vuelvan a entrar.

== Handshake, cierre, pérdidas y modo debug

Handshake y cierre se heredan sin cambios de la actividad anterior: funcionan con Stop & Wait y el cierre
se rinde tras 3 timeouts. Si se pierde el último ACK del handshake, el socket nuevo del servidor acepta como
confirmación implícita un segmento de datos con el número de secuencia esperado ($x+2$). Además,
`recv_close` vuelve a confirmar datos atrasados, por si el último ACK de la transferencia se perdió en el
camino.

Las pérdidas se simulan a mano: cada socket descarta lo que recibe con probabilidad `LOSS` (variable de
entorno). Como ambos extremos descartan, hay pérdidas en las dos direcciones, incluidos handshake y cierre.
Con `DEBUG=1` cada línea indica el puerto del socket y un evento: `->` envío, `<-` recepción, `xx` pérdida
simulada, `timeout`, y `[cc]` con estado, `cwnd`, `ssthresh` (ambos en bytes) y `window_size` (en
segmentos) tras cada evento de control de congestión. Por ejemplo:

```
LOSS=0.2 DEBUG=1 python3 servidor.py localhost 8000 > recibido.txt
LOSS=0.2 DEBUG=1 python3 cliente.py localhost 8000 go_back_n cc < archivo.txt
```

= Pruebas

== Integridad

`server_test.py` y `client_test.py` son los tests del curso (Tests 1 a 3). Se les agregó solo lo necesario
para correrlos (el `import` y la dirección), el modo como argumento, el cierre de conexión y un Test 4 con el
mismo formato: 74 bytes leídos con dos `recv(37)`, pues 37 no es múltiplo de 8 ni de 16.
Además se envió `archivo.txt` (1316 bytes) con `cliente.py` y `servidor.py`, comparando lo recibido con el
original mediante `cmp`. Todo se corrió en los tres modos, sin pérdida y con `LOSS=0.2` (@integridad).

#figure(
  table(
    columns: 4,
    stroke: none,
    align: (left, center, center, center),
    table.hline(),
    [*prueba*], [*Stop & Wait*], [*Go-Back-N*], [*Go-Back-N + CC*],
    table.hline(stroke: 0.5pt),
    [Tests 1 a 4, sin pérdida], [Passed], [Passed], [Passed],
    [Tests 1 a 4, 20 % de pérdida], [Passed], [Passed], [Passed],
    [`archivo.txt`, sin pérdida], [íntegro], [íntegro], [íntegro],
    [`archivo.txt`, 20 % de pérdida], [íntegro], [íntegro], [íntegro],
    [tiempo de `send` con 20 % de pérdida], [25.72 s], [22.71 s], [33.72 s],
    table.hline(),
  ),
  caption: [Resultados de `./run.sh`.],
) <integridad>

== Sin pérdida <sin-perdida>

En localhost no hubo timeouts espontáneos: el RTT es de fracciones de milisegundo, muy lejos de los 0.5 s
del timer. Cada uno de los 166 segmentos del archivo recibe su ACK, así que `cwnd` sube 1 MSS por ACK hasta
167 MSS (1336 bytes), más que el archivo completo. La conexión nunca sale de _slow start_: `ssthresh` sigue
en `None` porque ningún timeout llegó a definirlo. El inicio del registro muestra además que el socket que
atiende la conexión (50285) tiene un puerto distinto al que escucha (8000). Como cliente y servidor escriben
en el mismo archivo, algunas líneas aparecen en desorden:

```
[8000] <- SYN seq=12
[45960] -> SYN seq=12
[45960] <- SYN+ACK seq=13
[45960] -> ACK seq=14
[50285] -> SYN+ACK seq=13
[50285] <- ACK seq=14
[45960] [cc] inicio: slow_start cwnd=8.00 ssthresh=None window_size=1
[50285] <- DATA seq=14 len=4
[45960] -> DATA seq=14 len=4
[50285] -> ACK seq=18
[45960] <- ACK seq=18
[45960] [cc] ack: slow_start cwnd=16.00 ssthresh=None window_size=2
[50285] <- DATA seq=18 len=8
[45960] -> DATA seq=18 len=8
[50285] -> ACK seq=26
[45960] -> DATA seq=26 len=8
...
[45960] [cc] ack: slow_start cwnd=1328.00 ssthresh=None window_size=166
[45960] [cc] ack: slow_start cwnd=1336.00 ssthresh=None window_size=167
```

== Con pérdida

Con 20 % de pérdida hubo 63 timeouts en un solo envío. Cada uno deja `ssthresh` en la mitad de la ventana y
`cwnd` en 1 MSS; _slow start_ la hace crecer de a 1 MSS hasta `ssthresh`, y desde ahí _congestion
avoidance_ suma fracciones de MSS. A este ritmo la ventana nunca pasó de 53.33 bytes (6.7 MSS). El extracto
muestra solo las líneas de pérdidas, timeouts y `[cc]`. El segmento con el largo se pierde dos veces con
`cwnd` = 1 MSS, así que `ssthresh` queda en 4 bytes y el siguiente ACK salta directo a _congestion
avoidance_. La red no da tiempo para ilusionarse. Desde ahí la ventana crece de a fracciones (16 → 20 → 24 →
26.67 bytes) hasta 53.33 bytes, cuando un nuevo timeout la devuelve a 1 MSS con `ssthresh` =
`int(53.33/2)` = 26:

```
[45733] [cc] inicio: slow_start cwnd=8.00 ssthresh=None window_size=1
[60921] xx DATA seq=97 len=4 (pérdida simulada)
[45733] timeout, Go-Back-N desde seq=97
[45733] [cc] timeout: slow_start cwnd=8.00 ssthresh=4 window_size=1
[60921] xx DATA seq=97 len=4 (pérdida simulada)
[45733] timeout, Go-Back-N desde seq=97
[45733] [cc] timeout: slow_start cwnd=8.00 ssthresh=4 window_size=1
[45733] [cc] ack: congestion_avoidance cwnd=16.00 ssthresh=4 window_size=2
[45733] [cc] ack: congestion_avoidance cwnd=20.00 ssthresh=4 window_size=2
[45733] [cc] ack: congestion_avoidance cwnd=24.00 ssthresh=4 window_size=3
[45733] [cc] ack: congestion_avoidance cwnd=26.67 ssthresh=4 window_size=3
...
[45733] [cc] ack: congestion_avoidance cwnd=48.00 ssthresh=4 window_size=6
[45733] [cc] ack: congestion_avoidance cwnd=49.33 ssthresh=4 window_size=6
[60921] xx DATA seq=245 len=8 (pérdida simulada)
[45733] [cc] ack: congestion_avoidance cwnd=50.67 ssthresh=4 window_size=6
[45733] [cc] ack: congestion_avoidance cwnd=52.00 ssthresh=4 window_size=6
[45733] [cc] ack: congestion_avoidance cwnd=53.33 ssthresh=4 window_size=6
[45733] timeout, Go-Back-N desde seq=245
[45733] [cc] timeout: slow_start cwnd=8.00 ssthresh=26 window_size=1
[45733] [cc] ack: slow_start cwnd=16.00 ssthresh=26 window_size=2
```

== Go-Back-N con y sin control de congestión <comparar>

Se envió `archivo.txt` cinco veces con cada variante, con 20 % de pérdida y timeout de 0.5 s
#footnote[El enunciado pide un archivo de 100 B, pero la pregunta habla de más de 1000 B; se usó
`archivo.txt`, de 1316 bytes, para que la ventana tuviera espacio para crecer.]. `cliente.py` informa el
tiempo de `send` y `number_of_sent_segments`, que incluye los dos segmentos del handshake; sin pérdidas
bastan 168 (@comparacion).

#figure(
  table(
    columns: 5,
    stroke: none,
    column-gutter: (0pt, 0pt, 1em),
    align: center,
    table.hline(),
    [], table.cell(colspan: 2)[*Go-Back-N*], table.cell(colspan: 2)[*Go-Back-N + CC*],
    table.hline(start: 1, end: 3, stroke: 0.5pt),
    table.hline(start: 3, stroke: 0.5pt),
    [*envío*], [*tiempo [s]*], [*segmentos*], [*tiempo [s]*], [*segmentos*],
    table.hline(stroke: 0.5pt),
    [1], [21.72], [494], [22.20], [270],
    [2], [28.72], [619], [38.79], [312],
    [3], [23.69], [518], [37.29], [312],
    [4], [25.21], [562], [23.70], [278],
    [5], [24.66], [546], [40.29], [320],
    table.hline(stroke: 0.5pt),
    [promedio], [24.80], [547.8], [32.45], [298.4],
    table.hline(),
  ),
  caption: [Cinco envíos por variante con 20 % de pérdida.],
) <comparacion>

*¿Cuál toma menos tiempo?* Go-Back-N sin control de congestión: 24.80 s en promedio contra 32.45 s. El
tiempo lo dominan los timeouts, que cuestan 0.5 s cada uno mientras el resto del envío dura milisegundos, y
con ventanas pequeñas hay más. Si se pierde el ACK del único segmento en vuelo, no queda un ACK posterior que
lo cubra y el emisor espera el timer completo; con 8 segmentos en vuelo, el siguiente ACK acumulativo suele
tapar la pérdida. Además, Tahoe interpreta toda pérdida como congestión y castiga la ventana, aunque aquí las
pérdidas sean aleatorias y achicarla no las evite.

*¿Cómo se comparan?* El control de congestión gana donde le importa a la red: envía 298 segmentos en
promedio contra 548, cerca de un 46 % menos. Sin control, cada timeout reenvía los 8 segmentos de la ventana
aunque casi todos vayan a ser descartados, y se termina mandando 3.3 veces lo necesario. Con control, el
emisor retrocede a 1 MSS y tantea antes de volver a acelerar. El precio es un tiempo mayor y más variable:
entre 22 y 40 s, contra 22 a 29 s sin control.

= Conclusiones

Go-Back-N resultó ser un Stop & Wait con más ambición: el mismo receptor, el mismo timer y una ventana más
grande. El control de congestión, por su parte, no hizo más rápida la transferencia en este escenario, pero sí
más austera: entregó el mismo archivo con bastante menos tráfico. Es la idea de _fairness_ del enunciado vista
en pequeño; el control de congestión no está para ganar la carrera, sino para que la red alcance para todos.
Queda pendiente _fast retransmit_, que con tres ACK duplicados ahorraría buena parte de los timeouts que
dominan los tiempos medidos.
