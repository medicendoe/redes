#import "diagramas.typ": siete

#set document(title: "Informe 5: Forwarding básico", author: "Gabriel Gallardo R.")
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
  #text(size: 18pt, weight: "bold")[Informe 5: Forwarding básico] \
  #v(1em)
  #text(size: 12pt)[Gabriel Gallardo R.] \
  #link("https://github.com/medicendoe/redes")[github.com/medicendoe/redes]
]

= Declaración de uso de IA

Este trabajo utilizó modelos de Inteligencia Artificial. Se utilizó Claude (Anthropic) durante el
desarrollo del código y en la redacción de este informe.

= Ejecución del código

El código está en la carpeta `c3/a1` del repositorio. Se entrega solo la versión final, con TTL; para repetir
las pruebas sin TTL, la variable de entorno `NO_TTL=1` hace que el router ignore ese campo. Para correr todas
las pruebas:

```bash
./run.sh
```

`run.sh` corre los tests de `router_test.py` y levanta las redes de cada prueba. El log de cada router queda en
`resultados/<prueba>/R<n>.txt`. A mano, un router por terminal y luego los scripts de envío:

```bash
python3 router.py 127.0.0.1 8881 rutas/rutas_R1_v3.txt
python3 enviar.py "127.0.0.1;8885;10" "hola" 127.0.0.1 8881
python3 prueba_router.py "127.0.0.1;8885;10" 127.0.0.1 8881 < archivo.txt
```

Los headers van entre comillas porque en la shell `;` separa comandos.

= Nuestra tabla de rutas y una real

Las dos cumplen la misma función: para cada destino indican el siguiente salto, y el router no conoce el
camino completo, solo a quién entregarle el paquete. Las diferencias son:

- Una tabla real identifica el destino solo por red y máscara. La nuestra agrega un rango de puertos, porque
  todos los routers usan la IP `127.0.0.1` y el puerto los distingue.
- Un router real elige la ruta más específica (_longest prefix match_). El nuestro usa la primera que calza, en
  el orden del archivo.
- Una tabla real indica además la interfaz de salida y una métrica, y se llena con protocolos de ruteo. La
  nuestra es un archivo escrito a mano.

= Implementación

== Paquetes y scripts de envío

El header ocupa 7 bytes: 4 para la IP (un byte por número), 2 para el puerto y 1 para el TTL, seguidos del
mensaje. `parse_packet` lo convierte en un diccionario `{"IP", "puerto", "TTL", "mensaje"}` y `create_packet`
hace el camino de vuelta. Como `create_packet` retorna bytes, el test del enunciado se usa sin el `.encode()`.

`enviar.py` (paso 5) recibe los headers, el mensaje y la dirección a la que se envía el paquete:

```bash
python3 enviar.py "IP_destino;puerto_destino[;TTL]" "mensaje" IP_envío puerto_envío
```

El TTL es opcional y vale 64 por defecto. `prueba_router.py` usa los mismos headers y lee el archivo desde
stdin, enviando cada línea en su propio paquete.

== Round-robin

`check_routes` recorre la tabla en orden. La primera ruta que calza define el _área_: el trío (red, puerto
inicial, puerto final). Todas las líneas con esa misma área son rutas alternativas. Un diccionario global,
`round_robin`, guarda para cada área el índice de la última ruta usada, y en cada llamada avanza uno, módulo la
cantidad de alternativas. Así funciona con cualquier número de rutas, y el router recuerda la última ruta que
tomó en cada área por separado.

== Router default

La ruta default es `0.0.0.0/0 0 65535 127.0.0.1 7000`: cualquier IP y cualquier puerto. Por ejemplo, la tabla de
R2 queda:

```
127.0.0.1/24 8881 8881 127.0.0.1 8881
127.0.0.1/24 8883 8885 127.0.0.1 8883
127.0.0.1/24 8883 8885 127.0.0.1 8884
0.0.0.0/0 0 65535 127.0.0.1 7000
```

Las tablas de los otros routers suman la misma línea al final (`rutas_R*_v3_default.txt`). El router default
conoce una ruta directa a cada router.

*¿En qué posición de la tabla debería ir la ruta default?* En la última. `check_routes` usa la primera ruta que
calza y la default calza con todo; en cualquier otra posición taparía a las rutas que vienen después. Al final,
solo la usan los paquetes que no tienen otra ruta. En la prueba, un paquete a `127.0.0.1:9000` enviado a R1 llegó
al router default.

= Pruebas sin TTL

== Tabla de rutas mal configurada

Con la tabla de R2 cambiada por la del enunciado, R2 manda a R1 lo que va hacia R3, y R1 se lo devuelve a R2. El
paquete de R1 a R3 nunca llega y queda rebotando entre ambos: en poco más de un segundo y medio, hasta que se
apagaron los routers, R1 y R2 lo redirigieron 11~652 veces cada uno. No se detendría nunca. Los paquetes de R1 a
R2 y de R3 a R1 sí llegan, porque la línea mala solo afecta al destino R3.

== Cinco routers

Se enviaron 6 paquetes de R1 a R5, uno a la vez. Los caminos, sacados de los logs, alternan entre dos:

```
paquete 1, 3 y 5: R1 -> R2 -> R3 -> R2 -> R4 -> R2 -> R3 -> R5   (7 saltos)
paquete 2, 4 y 6: R1 -> R2 -> R4 -> R5                           (3 saltos)
```

*¿Cuántos saltos dan? ¿Siempre los mismos?* No: alternan entre 7 y 3, con un promedio de 5. *¿Cómo se compara con
el mínimo?* El mínimo es 3 (R1 → R2 → R3 → R5 o R1 → R2 → R4 → R5), así que la mitad de los paquetes toma un camino
mínimo y la otra mitad da 4 saltos de más. Pasa porque R3 y R4 también alternan, y una de sus rutas devuelve el
paquete a R2. Round-robin alterna entre rutas, pero no sabe cuál es más corta.

== Siete routers

#figure(siete, kind: image, caption: [Red del test 2 del paso 8: R0 (8880) se conecta a R1 y R2, y R6 (8886)
  a R2 y R3.]) <fig-siete>

Las tablas de la red de la @fig-siete (`rutas_R*_v4.txt`) siguen la lógica de la red de 5 routers: para cada
área, todos los vecinos desde los que se puede llegar.

```
# rutas_R0_v4.txt                        # rutas_R1_v4.txt
127.0.0.1/24 8881 8881 127.0.0.1 8881    127.0.0.1/24 8880 8880 127.0.0.1 8880
127.0.0.1/24 8882 8886 127.0.0.1 8882    127.0.0.1/24 8882 8886 127.0.0.1 8882

# rutas_R2_v4.txt                        # rutas_R3_v4.txt
127.0.0.1/24 8880 8881 127.0.0.1 8881    127.0.0.1/24 8880 8882 127.0.0.1 8882
127.0.0.1/24 8880 8881 127.0.0.1 8880    127.0.0.1/24 8880 8882 127.0.0.1 8886
127.0.0.1/24 8883 8886 127.0.0.1 8883    127.0.0.1/24 8884 8885 127.0.0.1 8882
127.0.0.1/24 8883 8886 127.0.0.1 8884    127.0.0.1/24 8884 8885 127.0.0.1 8885
127.0.0.1/24 8883 8886 127.0.0.1 8886    127.0.0.1/24 8886 8886 127.0.0.1 8886

# rutas_R4_v4.txt                        # rutas_R5_v4.txt
127.0.0.1/24 8880 8883 127.0.0.1 8882    127.0.0.1/24 8880 8884 127.0.0.1 8884
127.0.0.1/24 8880 8883 127.0.0.1 8885    127.0.0.1/24 8880 8884 127.0.0.1 8883
127.0.0.1/24 8885 8886 127.0.0.1 8882    127.0.0.1/24 8886 8886 127.0.0.1 8883
127.0.0.1/24 8885 8886 127.0.0.1 8885

# rutas_R6_v4.txt
127.0.0.1/24 8880 8882 127.0.0.1 8882
127.0.0.1/24 8883 8885 127.0.0.1 8883
127.0.0.1/24 8883 8885 127.0.0.1 8882
```

Se intercalaron 6 paquetes de R1 a R5 con 6 de R5 a R1. En el log de R2, los paquetes hacia R5 salieron por R3,
R4, R6, R3, R4, R6, ... y los paquetes hacia R1 por R1, R0, R1, R0, ...: cada área cicla por su cuenta aunque
los paquetes se intercalen. Los saltos fueron:

#figure(
  table(
    columns: 7,
    stroke: none,
    align: (left, center, center, center, center, center, center),
    table.hline(),
    [*paquete*], [1], [2], [3], [4], [5], [6],
    table.hline(stroke: 0.5pt),
    [R1 a R5], [8], [5], [5], [8], [3], [10],
    [R5 a R1], [3], [4], [6], [4], [3], [7],
    table.hline(),
  ),
  caption: [Saltos de cada paquete en la red de 7 routers.],
)

El mínimo sigue siendo 3 en ambos sentidos, pero ahora hay más variación (de 3 a 10 saltos): con más vecinos hay
más caminos posibles y también más formas de dar vueltas, por ejemplo R2 → R6 → R3 → R2.

= Pruebas con TTL

== Tabla de rutas mal configurada

Se repitió la prueba con TTL 10. El paquete rebota igual entre R1 y R2, pero con cada salto el TTL baja en uno, y
después de 10 saltos R1 lo recibe con TTL 0 y lo descarta:

```
==> R1.txt <==
redirigiendo paquete 127.0.0.1;8883;9;hola R3, desde R1 con destino final 127.0.0.1:8883 desde 127.0.0.1:8881 hacia 127.0.0.1:8882
redirigiendo paquete 127.0.0.1;8883;7;hola R3, desde R1 con destino final 127.0.0.1:8883 desde 127.0.0.1:8881 hacia 127.0.0.1:8882
...
Se recibió paquete 127.0.0.1;8883;0;hola R3, desde R1 con TTL 0
==> R2.txt <==
redirigiendo paquete 127.0.0.1;8883;8;hola R3, desde R1 con destino final 127.0.0.1:8883 desde 127.0.0.1:8882 hacia 127.0.0.1:8881
...
redirigiendo paquete 127.0.0.1;8883;0;hola R3, desde R1 con destino final 127.0.0.1:8883 desde 127.0.0.1:8882 hacia 127.0.0.1:8881
```

La diferencia es que el ciclo ya no es infinito: la tabla sigue mal y el paquete sigue sin llegar, pero da como
máximo 10 saltos y la red vuelve a quedar en silencio.

== Orden de los paquetes

Se envió `archivo.txt` (31 líneas) de R1 a R5 con `prueba_router.py` y TTL 10. R5 imprimió las líneas en este
orden:

```
4 8 12 16 20 24 28 3 7 11 15 19 23 27 31 14 30 13 29 2 18 1 17 6 21 10 25 22 9
```

*¿Qué ocurre con el orden?* Las líneas llegan desordenadas, y además faltan dos (la 5 y la 26), que se quedaron sin
TTL dando vueltas. Como cada línea toma un camino distinto según el round-robin, las que toman un camino corto
llegan antes que las que dan vueltas. Se ve en el patrón: las líneas 4, 8, 12, ... y 3, 7, 11, ... toman el camino
de 3 saltos y llegan primero. La capa de red no asegura ni el orden ni la llegada de los paquetes.

= Conclusiones

El mini-Internet funciona con un header de 7 bytes, un archivo de rutas y un loop. Las pruebas mostraron que una
tabla mal configurada basta para que un paquete dé vueltas para siempre, y que el TTL no corrige la tabla pero sí
limita el daño. Round-robin reparte el tráfico, pero sin saber de distancias hace que muchos paquetes den vueltas
de más, y al enviar un archivo las líneas llegaron desordenadas e incompletas.
