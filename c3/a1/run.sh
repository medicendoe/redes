#!/bin/sh
set -e
cd "$(dirname "$0")"
[ -d .venv ] || python3 -m venv .venv
. .venv/bin/activate
rm -rf resultados
mkdir -p resultados

pids=""

# levantar escenario version N...: un router RN en el puerto 888N con rutas/rutas_RN_version.txt
# y su log en resultados/escenario/RN.txt
levantar() {
    dir=resultados/$1 version=$2
    shift 2
    mkdir -p $dir
    for r in "$@"; do
        python router.py 127.0.0.1 888$r rutas/rutas_R${r}_$version.txt > $dir/R$r.txt 2>&1 &
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
    sleep 0.1
}

# mostrar escenario: imprime los logs del escenario
mostrar() {
    tail -n +1 resultados/$1/*.txt
}

echo "== Tests de parse_packet, create_packet y check_routes"
python router_test.py

echo "== Ejemplo 1: R1 <-> R2"
levantar ejemplo1 v1 1 2
enviar "127.0.0.1;8881" "hola R1, desde R1" 1
enviar "127.0.0.1;8882" "hola R2, desde R1" 1
bajar
mostrar ejemplo1

echo "== Ejemplo 2: R1 <-> R2 <-> R3"
levantar ejemplo2 v2 1 2 3
enviar "127.0.0.1;8883" "hola R3, desde R1" 1
enviar "127.0.0.1;8881" "hola R1, desde R3" 3
enviar "127.0.0.1;8882" "hola R2, desde R1" 1
enviar "127.0.0.1;8884" "hola" 1
bajar
mostrar ejemplo2

echo "== Ejemplo 2 con la tabla de R2 mal configurada, sin TTL (NO_TTL=1)"
export NO_TTL=1
levantar mal_sin_ttl v2_mal 1 2 3
enviar "127.0.0.1;8882" "hola R2, desde R1" 1
enviar "127.0.0.1;8881" "hola R1, desde R3" 3
enviar "127.0.0.1;8883" "hola R3, desde R1" 1
sleep 1
bajar
unset NO_TTL
for r in 1 2 3; do
    echo "R$r: $(grep -c redirigiendo resultados/mal_sin_ttl/R$r.txt) redirecciones"
done

echo "== 5 routers: 6 paquetes de R1 a R5, uno a la vez"
levantar v3 v3 1 2 3 4 5
for i in 1 2 3 4 5 6; do
    enviar "127.0.0.1;8885" "paquete $i" 1
done
bajar
for i in 1 2 3 4 5 6; do
    echo "paquete $i: $(cat resultados/v3/*.txt | grep -c ";paquete $i con") saltos"
done

echo "== 7 routers (R0 y R6): paquetes intercalados de R1 a R5 y de R5 a R1"
levantar v4 v4 0 1 2 3 4 5 6
for i in 1 2 3 4 5 6; do
    enviar "127.0.0.1;8885" "R1 a R5, $i" 1
    enviar "127.0.0.1;8881" "R5 a R1, $i" 5
done
bajar
for i in 1 2 3 4 5 6; do
    echo "R1 a R5, $i: $(cat resultados/v4/*.txt | grep -c ";R1 a R5, $i con") saltos," \
         "R5 a R1, $i: $(cat resultados/v4/*.txt | grep -c ";R5 a R1, $i con") saltos"
done
echo "Decisiones de R2:"
sed 's/.*destino final 127.0.0.1:\([0-9]*\) .* hacia 127.0.0.1:\([0-9]*\)/hacia \1 por \2/' resultados/v4/R2.txt

echo "== 5 routers con router default en 127.0.0.1:7000"
mkdir -p resultados/default
python router.py 127.0.0.1 7000 rutas/rutas_default.txt > resultados/default/default.txt 2>&1 &
pids="$!"
levantar default v3_default 1 2 3 4 5
enviar "127.0.0.1;9000" "hacia 127.0.0.1:9000" 1
enviar "127.0.0.1;8885" "hacia R5" 1
bajar
mostrar default

echo "== TTL=1 de R1 a R3 (ejemplo 2)"
levantar ttl1 v2 1 2 3
enviar "127.0.0.1;8883;1" "hola" 1
bajar
mostrar ttl1

echo "== Ejemplo 2 con la tabla de R2 mal configurada, TTL=10"
levantar mal_ttl v2_mal 1 2 3
enviar "127.0.0.1;8883;10" "hola R3, desde R1" 1
bajar
mostrar mal_ttl

echo "== archivo.txt de R1 a R5 con prueba_router.py y TTL=10"
levantar archivo v3 1 2 3 4 5
python prueba_router.py "127.0.0.1;8885;10" 127.0.0.1 8881 < archivo.txt
bajar
echo "llegaron $(grep -c . resultados/archivo/R5.txt) de $(grep -c . archivo.txt) líneas"
echo "descartadas por TTL: $(cat resultados/archivo/*.txt | grep -c "TTL 0")"
echo "orden de llegada: $(awk 'NR == FNR { n[$0] = NR; next } { printf "%s ", n[$0] }' archivo.txt resultados/archivo/R5.txt)"

if command -v typst > /dev/null; then
    typst compile informe/main.typ
fi
