#!/bin/sh
set -e
cd "$(dirname "$0")"
[ -d .venv ] || python3 -m venv .venv
. .venv/bin/activate
mkdir -p resultados

for loss in 0 0.2; do
    echo "== Tests send/recv, LOSS=$loss"
    LOSS=$loss python server_test.py &
    sleep 0.5
    LOSS=$loss python client_test.py
    wait

    echo "== archivo.txt, LOSS=$loss"
    : > resultados/debug_$loss.txt
    LOSS=$loss DEBUG=1 python servidor.py localhost 8000 > resultados/recibido.txt 2>> resultados/debug_$loss.txt &
    sleep 0.5
    LOSS=$loss DEBUG=1 python cliente.py localhost 8000 < archivo.txt 2>> resultados/debug_$loss.txt
    wait
    cmp archivo.txt resultados/recibido.txt && echo "archivo.txt llegó íntegro"
done

echo "== Se pierde el último ACK del handshake"
: > resultados/debug_handshake.txt
DEBUG=1 python servidor.py localhost 8000 > resultados/recibido.txt 2>> resultados/debug_handshake.txt &
sleep 0.5
LOSE_HANDSHAKE_ACK=1 DEBUG=1 python cliente.py localhost 8000 < archivo.txt 2>> resultados/debug_handshake.txt
wait
cmp archivo.txt resultados/recibido.txt && echo "archivo.txt llegó íntegro"