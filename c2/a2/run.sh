#!/bin/sh
set -e
cd "$(dirname "$0")"
[ -d .venv ] || python3 -m venv .venv
. .venv/bin/activate
mkdir -p resultados

echo "== CongestionControl"
python CongestionControl_test.py

for args in "stop_and_wait" "go_back_n" "go_back_n cc"; do
    mode=${args%% *}
    for loss in 0 0.2; do
        echo "== Tests send/recv, $args, LOSS=$loss"
        LOSS=$loss python server_test.py $mode &
        sleep 0.5
        LOSS=$loss python client_test.py $args
        wait

        echo "== archivo.txt, $args, LOSS=$loss"
        LOSS=$loss python servidor.py localhost 8000 $mode > resultados/recibido.txt &
        sleep 0.5
        LOSS=$loss python cliente.py localhost 8000 $args < archivo.txt
        wait
        cmp archivo.txt resultados/recibido.txt && echo "archivo.txt llegó íntegro"
    done
done

echo "== Modo debug de la ventana de congestión"
for loss in 0 0.2; do
    : > resultados/debug_$loss.txt
    LOSS=$loss DEBUG=1 python servidor.py localhost 8000 > /dev/null 2>> resultados/debug_$loss.txt &
    sleep 0.5
    LOSS=$loss DEBUG=1 python cliente.py localhost 8000 go_back_n cc < archivo.txt 2>> resultados/debug_$loss.txt
    wait
done

echo "== Go-Back-N con y sin control de congestión: 20 % de pérdida, timeout 0.5 s"
: > resultados/comparacion.txt
for cc in "" "cc"; do
    for i in 1 2 3 4 5; do
        LOSS=0.2 python servidor.py localhost 8000 > /dev/null &
        sleep 0.5
        echo "go_back_n $cc ($i) $(LOSS=0.2 python cliente.py localhost 8000 go_back_n $cc < archivo.txt)" | tee -a resultados/comparacion.txt
        wait
    done
done