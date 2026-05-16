#!/usr/bin/env bash
# Constrói o harness allbilly/rk3588-matmul-bench com M-sweep ativado para
# o BL-RAW da Fase 2 (M ∈ {1, 2, 4, 8, 16, 32, 64, 128}).
#
# Linka contra os headers/lib do nosso fork (libs/include/ + librknnrt.so).
# Saída: /home/fukumori/HomeAssistant/rockllama.cpp/bin/bench_local_msweep
#
# Idempotente: se /tmp/rk3588-matmul-bench/ existe, só aplica o patch e recompila.

set -euo pipefail

REPO_DIR=/home/fukumori/HomeAssistant/rockllama.cpp
BENCH_DIR=/tmp/rk3588-matmul-bench
OUT_DIR="$REPO_DIR/bin"
OUT_BIN="$OUT_DIR/bench_local_msweep"

mkdir -p "$OUT_DIR"

if [ ! -d "$BENCH_DIR" ]; then
    git clone --depth 1 https://github.com/allbilly/rk3588-matmul-bench "$BENCH_DIR"
fi

cd "$BENCH_DIR"

# Patch idempotente: troca a linha hardcoded M={128} pelo M-sweep comentado.
# Antes: std::vector<int> m = {128};
# Depois: std::vector<int> m = {1, 2, 4, 8, 16, 32, 64, 128};
if grep -q 'std::vector<int> m = {128};' bench.cpp; then
    echo "[patch] aplicando M-sweep"
    sed -i 's|std::vector<int> m = {128};|std::vector<int> m = {1, 2, 4, 8, 16, 32, 64, 128};|' bench.cpp
elif grep -q 'std::vector<int> m = {1, 2, 4, 8, 16, 32, 64, 128};' bench.cpp; then
    echo "[patch] já aplicado"
else
    echo "[patch] ERRO: nem o original nem o patcheado encontrados; bench.cpp mudou?" >&2
    exit 2
fi

g++ -O3 -std=c++20 \
    -I "$REPO_DIR/local-src/ggml/src/ggml-rknpu2/libs/include" \
    bench.cpp \
    "$REPO_DIR/local-src/ggml/src/ggml-rknpu2/libs/librknnrt.so" \
    -o "$OUT_BIN"

echo "[build] $OUT_BIN"
file "$OUT_BIN"
