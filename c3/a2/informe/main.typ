#import "diagramas.typ": cinco-mtu

#set document(title: "Informe 6: Fragmentación", author: "Gabriel Gallardo R.")
#set page(paper: "a4", margin: 2.5cm, numbering: "1")
#set text(font: "New Computer Modern", size: 11pt, lang: "es")
#set par(justify: true)
#set heading(numbering: "1.1.")
#set list(spacing: 0.8em)
#show heading: set block(above: 1.4em, below: 0.8em)
#show raw.where(block: true): set text(size: 7.5pt)
#show raw.where(block: true): it => block(fill: luma(246), inset: 8pt, radius: 3pt, width: 100%, it)
#show figure.caption: set text(size: 9pt)
#show table: set par(justify: false)

#align(center)[
  #text(size: 18pt, weight: "bold")[Informe 6: Fragmentación] \
  #v(1em)
  #text(size: 12pt)[Gabriel Gallardo R.] \
  #link("https://github.com/medicendoe/redes")[github.com/medicendoe/redes]
]

= Declaración de uso de IA

Este trabajo utilizó modelos de Inteligencia Artificial. Se utilizó Claude (Anthropic) durante el
desarrollo del código y en la redacción de este informe.

= Ejecución del código

El código está en la carpeta `c3/a2` del repositorio y parte de una copia de la actividad de forwarding básico
con TTL. Para correr todas las pruebas:

```bash
./run.sh
```

`run.sh` corre los tests de `router_test.py` y `fragmentos_test.py` y levanta la red de 5 routers con MTU para
las pruebas. El log de cada router queda en `resultados/<prueba>/R<n>.txt`. A mano, un router por terminal y
luego el script de envío de forwarding básico, ahora con el header completo:

```bash
python3 router.py 127.0.0.1 8881 rutas/rutas_R1_v3_mtu.txt
python3 enviar.py "127.0.0.1;8885;10;347;0;5;0" "hola!" 127.0.0.1 8881
```

Los headers son `IP;puerto;TTL;ID;offset;tamaño;FLAG`. Desde el TTL son opcionales (TTL 64, ID al azar, offset
0, tamaño el del mensaje y FLAG 0). Con `DEBUG=1`, el router imprime cada fragmento que le llega como destino.

= Implementación

== Header

#figure(
  table(
    columns: 8,
    align: center + horizon,
    inset: 6pt,
    [*IP*], [*puerto*], [*TTL*], [*ID*], [*offset*], [*tamaño*], [*FLAG*], [*mensaje*],
    [4 bytes], [2 bytes], [1 byte], [4 bytes], [4 bytes], [4 bytes], [1 byte], [tamaño bytes],
  ),
  caption: [Formato del paquete IP: 20 bytes de header seguidos del mensaje.],
) <header>

El header queda de 20 bytes (@header). Al ID se le dieron 4 bytes para que sea difícil que dos paquetes
compartan ID. Al offset también 4 bytes, igual que al tamaño, porque un fragmento puede empezar en cualquier byte
del mensaje. El FLAG ocupa 1 byte con valor 0 o 1, que es más simple que guardarlo en un bit.

== Fragmentación

`check_routes` ahora lee la sexta columna de la tabla y retorna `(next_hop, MTU)`. Antes de reenviar, el router
llama a `fragment_IP_packet` con ese MTU y envía cada fragmento al siguiente salto.

`fragment_IP_packet` retorna `[IP_packet]` si el paquete completo, con header, cabe en el MTU. Si no, corta el
mensaje en trozos de `MTU - 20` bytes y a cada uno le pone una copia del header con su propio offset y tamaño.
Todos llevan FLAG 1, menos el último, que mantiene el FLAG del paquete original. Para que un fragmento se pueda
volver a fragmentar, los offsets se suman al offset del fragmento y no parten de 0, y si el fragmento original
tenía FLAG 1, todos sus trozos quedan con FLAG 1.

== Reensamblaje

Un paquete sin fragmentar tiene offset 0 y FLAG 0; un fragmento tiene offset mayor que 0 o FLAG 1.
`reassemble_IP_packet` ordena la lista por offset y va juntando los mensajes. Cada offset debe ser igual a la
cantidad de bytes ya juntados, y el último trozo debe tener FLAG 0; si no se cumple, falta algún fragmento y
retorna `None`. Si se cumple, arma el paquete con el header del primer trozo, offset 0, FLAG 0 y el tamaño total.
Un paquete sin fragmentar pasa estas condiciones y se retorna igual.

El router guarda lo que le llega en un diccionario `ID → lista de fragmentos` y, cada vez que recibe algo,
intenta reensamblar la lista de ese ID. Si lo logra, imprime el mensaje y borra el ID del diccionario.

`router_test.py` comprueba los tests del enunciado: `create_packet(parse_packet(p)) == p`, que un paquete
pequeño da una lista de 1 elemento y uno de 150 bytes da 2 fragmentos con MTU 100 y 5 con MTU 50, y que
fragmentar y reensamblar devuelve el mismo paquete, también re-fragmentando y en desorden. `fragmentos_test.py`
envía a R5 fragmentos de dos paquetes en orden, en desorden e intercalando ID, y R5 reensambló los seis
mensajes.

= Pruebas

#figure(cinco-mtu, kind: image, caption: [Red de 5 routers con el MTU de cada enlace.]) <fig-mtu>

== TTL y round-robin

Se envió cuatro veces el paquete del enunciado de R1 a R5 (TTL 10, mensaje `hola!`, ID 347 a 350). Mide 25
bytes, así que no se fragmenta. Los paquetes alternaron entre 7 y 3 saltos, igual que en forwarding básico, y los
cuatro llegaron: el TTL y el round-robin siguen funcionando.

== Paquete de 150 bytes de R1 a R5

Se envió cuatro veces de R1 a R5 un paquete de 150 bytes (20 de header y 130 de mensaje) con TTL 10, en la red de
la @fig-mtu. Los cuatro se reensamblaron en R5. Por ejemplo, para el ID 1002 R1 lo cortó en dos fragmentos (80 y
50 bytes de mensaje) para el enlace de MTU 100. R2 mandó el primero hacia R4 (MTU 80), cortándolo de nuevo en
60 y 20, y el segundo hacia R3 (MTU 50), cortándolo en 30 y 20. A R5 le llegaron cuatro trozos, desordenados:

```
llegó 127.0.0.1;8885;7;1002;0;60;1;Un paquete de... (1 con ID 1002)
llegó 127.0.0.1;8885;7;1002;110;20;0;o deje pasar ... (2 con ID 1002)
llegó 127.0.0.1;8885;5;1002;60;20;1;o lo necesari... (3 con ID 1002)
llegó 127.0.0.1;8885;1;1002;80;30;1;que ningún en... (4 con ID 1002)
Un paquete de 150 bytes: 20 de header y 130 de mensaje, justo lo necesario para que ningún enlace de la red lo deje pasar entero.
```

El último trozo llegó con TTL 1, porque dio varias vueltas entre R2, R3 y R4 antes de llegar a R5.

== Desde otros routers

Luego se envió el mismo paquete desde R5, R4 y R3 hacia R1, y desde R2 hacia R5. Todos se reensamblaron:

#figure(
  table(
    columns: (1.8cm, 5.2cm, 1fr),
    stroke: none,
    align: (left, left, left),
    table.hline(),
    [*envío*], [*trozos (offset + tamaño)*], [*qué pasó*],
    table.hline(stroke: 0.5pt),
    [R5 a R1], [0+60, 60+60, 120+10], [R5 → R4 (MTU 140) corta 120 + 10, R4 → R2 (MTU 80) corta el de 120 en 60 + 60],
    [R4 a R1], [0+60, 60+60, 120+10], [R4 → R2 (MTU 80) lo corta en tres de una vez],
    [R3 a R1], [0+35, 35+30, 65+5, 70+35, 105+25], [R3 → R5 (MTU 55) lo corta en trozos de 35, y R3 → R2 (MTU 50) corta un trozo de 35 en 30 + 5],
    [R2 a R5], [0+30, 30+30, 60+30, 90+30, 120+10], [R2 → R3 (MTU 50) lo corta en cinco de una vez],
    table.hline(),
  ),
  caption: [Fragmentos que llegaron a destino según el router de origen.],
)

*¿Cómo cambia el comportamiento si se envía desde otros routers?* Cambia cuántos fragmentos se generan y de qué
tamaño, porque depende de los MTU de los enlaces por los que pasa cada parte. Si el primer enlace tiene un MTU
chico, como R2 → R3 o R3 → R5, el paquete se corta en muchos trozos de inmediato; si es grande, como R5 → R4, al
principio casi no se corta. Además los trozos nunca se vuelven a juntar en el camino, así que el paquete llega
cortado según el enlace más chico que encontró cada parte.

*¿El código logra re-fragmentar un fragmento?* Sí. Desde R5, el fragmento de 120 bytes se volvió a cortar en
60 + 60 en R4, y desde R3 un fragmento de 35 bytes se cortó en 30 + 5 en R3. En ambos casos el destino
reensambló el paquete completo.

= Conclusiones

Los routers fragmentan los paquetes que no caben en el enlace y el router de destino los reensambla, aunque los
trozos lleguen desordenados, por caminos distintos y cortados más de una vez. Las pruebas mostraron que cada
fragmento viaja por su cuenta y que un paquete puede terminar dividido en varios trozos pequeños, cada uno con su
propio header de 20 bytes.
