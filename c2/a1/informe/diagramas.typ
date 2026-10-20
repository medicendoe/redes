#let azul = rgb("#2a78d6")
#let naranjo = rgb("#eb6834")
#let rojo = rgb("#e34948")

#let secuencia(alto, actores, cuerpo) = box(width: 100%, height: alto, {
  for (x, nombre) in actores {
    place(dx: x - 2.5cm, box(width: 5cm, align(center, text(8.5pt, weight: "bold", nombre))))
    place(line(start: (x, 0.6cm), end: (x, alto), stroke: (paint: luma(170), thickness: 0.6pt, dash: "dashed")))
  }
  cuerpo
})

#let flecha(p, q, etiqueta, perdida: false, color: black) = {
  let (x1, y1) = p
  let (x2, y2) = q
  let fin = if perdida { (x1 + (x2 - x1) * 0.62, y1 + (y2 - y1) * 0.62) } else { q }
  place(line(start: p, end: fin, stroke: 0.7pt + color))
  if perdida {
    place(dx: fin.at(0) - 3.5pt, dy: fin.at(1) - 7pt, text(11pt, fill: rojo, weight: "bold")[×])
  } else {
    let a = calc.atan2((x2 - x1) / 1pt, (y2 - y1) / 1pt)
    let (c, s) = (calc.cos(a), calc.sin(a))
    place(polygon(fill: color, q,
      (x2 - 6pt * c - 2.6pt * s, y2 - 6pt * s + 2.6pt * c),
      (x2 - 6pt * c + 2.6pt * s, y2 - 6pt * s - 2.6pt * c)))
  }
  let (mx, my) = ((x1 + x2) / 2, (y1 + y2) / 2)
  place(dx: mx - 3cm, dy: my - 0.42cm, box(width: 6cm, align(center, text(7.5pt, fill: color, raw(etiqueta)))))
}

#let activo(x, y1, y2, nombre, lado: left, color: azul) = {
  place(dx: x - 3pt, dy: y1, rect(width: 6pt, height: y2 - y1, fill: color.lighten(75%), stroke: 0.5pt + color))
  let dx = if lado == left { x - 3.1cm } else { x + 0.25cm }
  place(dx: dx, dy: y1, box(width: 2.85cm, align(if lado == left { right } else { left }, text(7.5pt, fill: color, raw(nombre)))))
}

#let nota(x, y, cuerpo, lado: left) = {
  let dx = if lado == left { x - 4.4cm } else { x + 0.25cm }
  place(dx: dx, dy: y - 0.2cm, box(width: 4.15cm, align(if lado == left { right } else { left }, text(7pt, style: "italic", fill: luma(80), cuerpo))))
}

#let handshake = secuencia(4.6cm, ((3.6cm, [Cliente]), (9cm, [Servidor: socket que escucha]),
                                   (14cm, [Servidor: socket nuevo])), {
  activo(3.6cm, 0.9cm, 3.75cm, "connect()")
  activo(9cm, 1.4cm, 2cm, "accept()", lado: right, color: naranjo)
  activo(14cm, 1.85cm, 4.25cm, "accept()", lado: right, color: naranjo)
  flecha((3.6cm, 1cm), (9cm, 1.5cm), "SYN seq=x")
  place(line(start: (9cm, 1.9cm), end: (14cm, 1.9cm), stroke: (paint: naranjo, thickness: 0.6pt, dash: "dotted")))
  place(dx: 11.2cm, dy: 1.55cm, text(7pt, style: "italic", fill: naranjo)[crea y hace bind])
  flecha((14cm, 2.15cm), (3.6cm, 2.85cm), "SYN+ACK seq=x+1")
  flecha((3.6cm, 3.15cm), (14cm, 3.85cm), "ACK seq=x+2")
  nota(14cm, 4.45cm, [retorna (socket nuevo, dirección)])
  nota(3.6cm, 3.95cm, [seq = x+2, listo para send])
})

#let sin-solucion = secuencia(5.4cm, ((4.5cm, [Cliente]), (11cm, [Servidor: socket nuevo])), {
  activo(11cm, 0.8cm, 5.3cm, "accept()", lado: right, color: naranjo)
  flecha((11cm, 0.9cm), (4.5cm, 1.4cm), "SYN+ACK seq=x+1")
  flecha((4.5cm, 1.65cm), (11cm, 2.15cm), "ACK seq=x+2", perdida: true)
  activo(4.5cm, 2.1cm, 5.3cm, "send()")
  flecha((4.5cm, 2.3cm), (11cm, 2.8cm), "DATA seq=x+2")
  nota(11cm, 3cm, [espera un ACK: ignora los datos], lado: right)
  nota(11cm, 3.45cm, [timeout], lado: right)
  flecha((11cm, 3.45cm), (4.5cm, 3.95cm), "SYN+ACK seq=x+1")
  nota(4.5cm, 4.15cm, [espera un ACK: ignora el SYN+ACK])
  nota(4.5cm, 4.6cm, [timeout])
  flecha((4.5cm, 4.6cm), (11cm, 5.1cm), "DATA seq=x+2")
  nota(11cm, 5.15cm, [... y así para siempre], lado: right)
})

#let con-solucion = secuencia(5.6cm, ((4.5cm, [Cliente]), (11cm, [Servidor: socket nuevo])), {
  activo(11cm, 0.8cm, 2.85cm, "accept()", lado: right, color: naranjo)
  flecha((11cm, 0.9cm), (4.5cm, 1.4cm), "SYN+ACK seq=x+1")
  flecha((4.5cm, 1.65cm), (11cm, 2.15cm), "ACK seq=x+2", perdida: true)
  activo(4.5cm, 2.1cm, 5.5cm, "send()")
  flecha((4.5cm, 2.3cm), (11cm, 2.8cm), "DATA seq=x+2")
  nota(11cm, 3.05cm, [seq esperado: lo toma como ACK, descarta los datos y retorna], lado: right)
  activo(11cm, 3.6cm, 5.5cm, "recv()", lado: right, color: naranjo)
  nota(4.5cm, 3.8cm, [timeout])
  flecha((4.5cm, 3.8cm), (11cm, 4.3cm), "DATA seq=x+2")
  flecha((11cm, 4.55cm), (4.5cm, 5.05cm), "ACK seq=x+2+len")
  nota(4.5cm, 5.3cm, [sigue con el siguiente trozo])
})
