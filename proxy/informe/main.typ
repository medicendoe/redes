#set page(paper: "a4", margin: 2.5cm)
#set text(font: "New Computer Modern", size: 11pt, lang: "es")
#set heading(numbering: "1.1")
#show heading: it => block(spacing: 1.2em, [ #strong(it) ])

#align(center)[
  #text(size: 18pt, weight: "bold")[Informe 1: Proxy HTTP] \
  #v(1em)
  #text(size: 12pt)[Gabriel Gallardo R.] \
  #link("https://github.com/medicendoe/redes")[Repositorio en GitHub]
]

#v(2em)

== 1. Declaración de uso de IA
Este trabajo #strong[sí] utilizó modelos de Inteligencia Artificial.
- *Redacción y Código:* Se utilizó exclusivamente Gemini para la estructuración y redacción de este informe en Typst, así como para consultas específicas sobre el uso de librerías. No se utilizó IA para generar la lógica de programación base del proxy.

== 2. Ejecución del código
Para ejecutar el proxy, utilice el siguiente comando en la máquina virtual o terminal local:
```bash
python proxy.py
```

== 3. Arquitectura y Flujo de Comunicación (Diagrama)
El proxy implementado actúa como intermediario utilizando sockets orientados a conexión TCP. Se requiere un mínimo de *dos sockets* concurrentes por petición:

1. *Socket Servidor:* Escucha peticiones del cliente (Browser/cURL).
2. *Socket Cliente:* Se conecta al servidor destino para reenviar la petición original.

Según el diagrama diseñado, el flujo se divide en tres escenarios principales:

- *Tráfico normal:* Cliente $->$ Proxy $->$ Servidor, seguido de Servidor $->$ Proxy $->$ Cliente.
- *Bloqueo (Control Parental):* Cliente $->$ Proxy. El proxy detecta el dominio prohibido y retorna directamente un HTTP 403 al Cliente sin contactar al servidor final.
- *Reemplazo de contenido:* Cliente $->$ Proxy $->$ Servidor. Al recibir la respuesta, el proxy filtra el *body* reemplazando strings prohibidos antes de enviarlo al Cliente.

== 4. Decisiones de Diseño e Implementación

=== 4.1. Recepción de mensajes y manejo de Buffers
Para manejar buffers de recepción más pequeños que el mensaje total, se implementó una lectura iterativa (`recv` en un ciclo):

- *¿Cómo sé que el HEAD llegó completo?* Buscando la secuencia de doble salto de línea `\r\n\r\n` dentro del buffer acumulado.
- *¿Qué pasa si los headers no caben en mi buffer?* Si el buffer es menor al head, el ciclo continúa iterando y haciendo append a la variable de los datos hasta encontrar el final del head.
- *¿Cómo sé que el BODY llegó completo?* Al parsear los headers se extrae el valor esperado de `Content-Length`. Luego, se cuenta y compara el largo de los bytes recibidos del cuerpo iterativamente, y el ciclo continúa hasta terminar de recibir la cantidad exacta.

=== 4.2. Bloqueo de dominios (Imágenes en 403)
Para mostrar la imagen local en el error 403, se determinó que son necesarios *2* ciclos HTTP en total:

1. Un ciclo para regresar la estructura y el código HTML del 403.
2. Un ciclo adicional para regresar el archivo de la imagen que es solicitada mediante la etiqueta `<img>` de dicho HTML.

== 5. Resultados de Pruebas

=== 5.1. Comportamiento en Navegador

- Al acceder a `http://cc4303.bachmann.cl/secret`, el proxy bloqueó la conexión correctamente, retornando un error 403 y renderizando la imagen almacenada localmente.
- Al acceder a `http://cc4303.bachmann.cl/replace`, las palabras prohibidas indicadas en el JSON fueron modificadas correctamente sin alterar la estructura del HTML original.

=== 5.2. Pruebas de Buffer Limitado

- *Buffer < Mensaje, pero Buffer > Headers:* El proxy procesa correctamente los headers en la primera lectura, extrae el `Content-Length` y procede a leer iterativamente el resto del socket hasta alcanzar la longitud esperada para completar el mensaje.
- *Buffer < Headers, pero Buffer > Start line:* El proxy detecta que no ha llegado la marca `\r\n\r\n` en la primera iteración, por lo que bloquea el parseo y continúa extrayendo bytes del socket de forma segura hasta recibir la totalidad de los headers.

=== Diagramas
#v(1em)
#align(center)[
  #grid(
    columns: 1,
    gutter: 1.5em,
    // Escenario 1
    rect(stroke: 1pt + black, inset: 15pt, radius: 5pt, width: 95%)[
      #align(left)[*Escenario 1: Tráfico Normal*]
      #v(0.5em)
      #align(center)[
        #box[Cliente] $scripts(-------"Query"------)>$ #box[Proxy] $scripts(-------"Query"------)>$ #box[Servidor] \
        #v(0.5em)
        #box[Cliente] $scripts(<----"Response"----)$ #box[Proxy] $scripts(<----"Response"----)$ #box[Servidor]
      ]
    ],
    // Escenario 2
    rect(stroke: 1pt + black, inset: 15pt, radius: 5pt, width: 95%)[
      #align(left)[*Escenario 2: Bloqueo de dominios (Control Parental)*]
      #v(0.5em)
      #align(center)[
        #box[Cliente] $scripts(-------"Query"------)>$ #box[Proxy] $quad quad quad quad quad quad$ #box(text(fill: gray)[Servidor]) \
        #v(0.5em)
        #box[Cliente] $scripts(<---------"403"---------)$ #box[Proxy] $quad quad quad quad quad quad$ $quad quad quad quad$
      ]
    ],
    // Escenario 3
    rect(stroke: 1pt + black, inset: 15pt, radius: 5pt, width: 95%)[
      #align(left)[*Escenario 3: Reemplazo de contenido inadecuado*]
      #v(0.5em)
      #align(center)[
        #box[Cliente] $scripts(-------"Query"------)>$ #box[Proxy] $scripts(-------"Query"------)>$ #box[Servidor] \
        #v(0.5em)
        #box[Cliente] $scripts(<--"Filtered Resp"--)$ #box[Proxy] $scripts(<----"Response"----)$ #box[Servidor]
      ]
    ]
  )
]
#v(1em)