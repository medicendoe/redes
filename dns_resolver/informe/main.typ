#set page(paper: "a4", margin: 2.5cm)
#set text(font: "New Computer Modern", size: 11pt, lang: "es")
#set heading(numbering: "1.1")
#show heading: it => block(spacing: 1.2em, [ #strong(it) ])

#align(center)[
  #text(size: 18pt, weight: "bold")[Informe 2: DNS Resolver] \
  #v(1em)
  #text(size: 12pt)[Gabriel Gallardo R.] \
  #link("https://github.com/medicendoe/redes")[Repositorio en GitHub]
]

#v(2em)

== 1. Declaración de uso de IA
Este trabajo #strong[sí] utilizó modelos de Inteligencia Artificial.
- *Redacción y Consultas:* Se utilizó exclusivamente Gemini para la estructuración y redacción de este informe en Typst, así como para consultas específicas. No se utilizó IA para generar la lógica de programación base.

== 2. Ejecución del código
Para ejecutar el resolver DNS, inicie el servidor en la máquina virtual o terminal local utilizando:
```bash
python resolver.py

```

El resolver quedará escuchando peticiones en el puerto 8000. Para probarlo como cliente desde otra terminal, utilice el comando `dig` especificando dicho puerto. Ejemplo: `dig -p8000 @IP_VM example.com`.

== 3. Decisiones de Diseño e Implementación
=== 3.1. Tipo de Socket utilizado
Para la recepción e intercambio de mensajes DNS, se implementó un socket de tipo *UDP* (`SOCK_DGRAM`). Esto se debe a que el protocolo DNS se comunica nativamente utilizando este esquema de transporte no orientado a conexión.

=== 3.2. Limitaciones del Diseño actual
En la implementación actual, si la función `resolver()` recibe una respuesta que no es directa (Answer tipo A) ni una delegación estricta a otro Name Server (Authority tipo NS), esta es ignorada.
*Limitaciones de este enfoque:* El resolver no permite ningún tipo de redirección. Si el dominio consultado está redirigiendo (por ejemplo, mediante registros CNAME), el evento es ignorado por completo y el resolver no devuelve ninguna respuesta al cliente, cortando el flujo de resolución.

== 4. Pruebas de Funcionalidad y Experimentos
=== 4.1. Consultas básicas e implementanción de Caché
Al consultar el dominio `eol.uchile.cl` utilizando el comando `dig`, el resolver arrojó un total de *11 respuestas* (direcciones IP).
Al realizar una segunda consulta consecutiva al mismo dominio, el resolver identificó exitosamente el registro en la memoria caché, devolviendo la misma dirección IP sin necesidad de consultar nuevamente a los Name Servers externos, confirmando así el correcto funcionamiento del almacenamiento temporal.

=== 4.2. Experimento: Dominio webofscience.com
*Observaciones:* El programa *no logra* resolver este dominio. Durante la ejecución, el resolver se queda atrapado con referencias loopeadas (en bucle).
*Explicación y solución:* Esto ocurre porque el dominio hace uso de redirecciones que la implementación actual ignora y no procesa, generando un ciclo de consultas sin salida. Para solucionar este problema, sería necesario modificar el código para que analice, considere y siga las redirecciones (ej. procesar explícitamente los alias o CNAMEs) en lugar de simplemente ignorar cualquier respuesta que no sea de tipo A o NS.

=== 4.3. Experimento: Dominio cc4303.bachmann.cl
*Nota: Este experimento no fue realizado debido a limitaciones de tiempo durante el desarrollo de la actividad.*

=== 4.4. Experimento: Consultas múltiples y Name Servers
*Nota: Este experimento no fue realizado debido a limitaciones de tiempo durante el desarrollo de la actividad.*