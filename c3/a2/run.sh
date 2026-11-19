#!/bin/sh
set -e
cd "$(dirname "$0")"
[ -d .venv ] || python3 -m venv .venv
. .venv/bin/activate
rm -rf resultados
mkdir -p resultados
export DEBUG=1

# 20 bytes de header + 130 de mensaje = 150 bytes
MENSAJE="Un paquete de 150 bytes: 20 de header y 130 de mensaje, justo lo necesario para que ningún enlace de la red lo deje pasar entero."
pids=""

# levantar escenario N...: un router RN en el puerto 888N con rutas/rutas_RN_v3_mtu.txt
# y su log en resultados/escenario/RN.txt
levantar() {
    dir=resultados/$1
    shift
    mkdir -p $dir
    for r in "$@"; do
        python router.py 127.0.0.1 888$r rutas/rutas_R${r}_v3_mtu.txt > $dir/R$r.txt 2>&1 &
        pids="$pids $!"
    done
    sleep 0.5
}

# bajar: deja que la red se vacíe y apaga los routers
bajar() {
    sleep 0.5
    kill $pids 2> /dev/null || true
    wait $pids 2> /dev/null || true
    pids=""
}

# enviar headers mensaje N: envía un paquete al router RN y espera a que llegue
enviar() {
    python enviar.py "$1" "$2" 127.0.0.1 888$3
    sleep 0.2
}

# mostrar escenario: imprime los logs del escenario
mostrar() {
    tail -n +1 resultados/$1/*.txt
}

echo "== Tests de parse_packet, create_packet, check_routes, fragment_IP_packet y reassemble_IP_packet"
python router_test.py

echo "== Paso 7: dos listas de fragmentos enviadas a mano a R5"
levantar paso7 5
python fragmentos_test.py
bajar
mostrar paso7

echo "== 'hola!' de R1 a R5 con TTL 10, cuatro veces (ID 347 a 350)"
levantar hola 1 2 3 4 5
for i in 0 1 2 3; do
    enviar "127.0.0.1;8885;10;$((347 + i));0;5;0" "hola!" 1
done
bajar
for id in 347 348 349 350; do
    echo "ID $id: $(cat resultados/hola/*.txt | grep -c "^redirigiendo paquete [^;]*;[0-9]*;[0-9]*;$id;") saltos"
done
cat resultados/hola/R5.txt

echo "== Paquete de 150 bytes de R1 a R5, cuatro veces (ID 1001 a 1004)"
levantar 150_R1 1 2 3 4 5
for i in 1 2 3 4; do
    enviar "127.0.0.1;8885;10;$((1000 + i))" "$MENSAJE" 1
done
bajar
mostrar 150_R1

echo "== Paquete de 150 bytes desde otros routers"
levantar 150_otros 1 2 3 4 5
enviar "127.0.0.1;8881;10;5001" "$MENSAJE" 5
enviar "127.0.0.1;8881;10;4001" "$MENSAJE" 4
enviar "127.0.0.1;8881;10;3001" "$MENSAJE" 3
enviar "127.0.0.1;8885;10;2001" "$MENSAJE" 2
bajar
mostrar 150_otros

if command -v typst > /dev/null; then
    typst compile informe/main.typ
fi
