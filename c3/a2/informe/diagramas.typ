#let azul = rgb("#2a78d6")
#let naranjo = rgb("#eb6834")

// red: dibuja routers (nombre: (x, y, puerto)) y enlaces ((a, b) o (a, b, etiqueta)).
#let red(ancho, alto, nodos, enlaces) = box(width: ancho, height: alto, {
  for enlace in enlaces {
    let (a, b) = (nodos.at(enlace.at(0)), nodos.at(enlace.at(1)))
    place(line(start: (a.at(0), a.at(1)), end: (b.at(0), b.at(1)), stroke: 0.8pt + luma(130)))
    if enlace.len() > 2 {
      let (mx, my) = ((a.at(0) + b.at(0)) / 2, (a.at(1) + b.at(1)) / 2)
      place(dx: mx - 1cm, dy: my - 0.25cm, box(width: 2cm, align(center,
        box(fill: white, inset: 2pt, text(7.5pt, fill: naranjo, weight: "bold", enlace.at(2))))))
    }
  }
  for (nombre, (x, y, puerto)) in nodos {
    place(dx: x - 0.5cm, dy: y - 0.5cm, circle(radius: 0.5cm, fill: azul.lighten(82%), stroke: 0.8pt + azul,
      align(center + horizon, stack(spacing: 2pt, text(9pt, weight: "bold", nombre), text(6.5pt, puerto)))))
  }
})

#let cinco-mtu = red(8.2cm, 3.8cm, (
  R1: (1cm, 0.7cm, "8881"), R2: (4cm, 0.7cm, "8882"), R3: (7cm, 0.7cm, "8883"),
  R4: (4cm, 3cm, "8884"), R5: (7cm, 3cm, "8885"),
), (("R1", "R2", "MTU 100"), ("R2", "R3", "MTU 50"), ("R2", "R4", "MTU 80"), ("R3", "R5", "MTU 55"),
    ("R4", "R5", "MTU 140")))
