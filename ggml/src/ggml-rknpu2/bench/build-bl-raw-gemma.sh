#!/usr/bin/env bash
# Constrói uma variante do harness allbilly/rk3588-matmul-bench com shapes
# exatos do gemma-4-E2B-it-Q8_0 (derivados do op-profile-base.jsonl da Fase 1.B+C).
#
# K ∈ {1536, 2048, 4096, 6144, 8192}              (todos os K do gemma)
# N ∈ {1536, 2048, 4096, 6144, 12288}             (todos os N do gemma; pula N=262144 vocab)
# M ∈ {1, 512}                                     (decode + prefill)
# Tipos: INT8, FP16 (W8A8 + W16A16; gemma não usa INT4)
#
# Saída: bin/bench_local_gemma. Usado para derriskar Item J da Fase 6.

set -euo pipefail

REPO_DIR=/home/fukumori/HomeAssistant/rockllama.cpp
BENCH_DIR=/tmp/rk3588-matmul-bench
OUT_BIN="$REPO_DIR/bin/bench_local_gemma"
PATCHED_SRC=/tmp/rk3588-matmul-bench/bench_gemma.cpp

mkdir -p "$REPO_DIR/bin"

if [ ! -d "$BENCH_DIR" ]; then
    git clone --depth 1 https://github.com/allbilly/rk3588-matmul-bench "$BENCH_DIR"
fi

# Trabalha em um arquivo separado para não interferir com build-bl-raw-msweep.sh.
cp "$BENCH_DIR/bench.cpp" "$PATCHED_SRC"

# Encontrar e substituir os arrays m, k, n. Aceita tanto o arquivo original
# quanto o patched do msweep — a substituição alvo o array antigo de m={...}.
# Faz três substituições com sed.

# m: gemma usa M=1 (decode) e M=512 (prefill). Pula M=4096 (output proj, raro).
# Aceita qualquer estado prévio do array m: {128} (original) ou {1,2,4,...} (msweep patch).
sed -i -E 's|std::vector<int> m = \{[^}]*\};|std::vector<int> m = {1, 512};|' "$PATCHED_SRC"

# k: 5 valores do gemma
sed -i -E 's|std::vector<int> k = \{[^}]*\};|std::vector<int> k = {1536, 2048, 4096, 6144, 8192};|' "$PATCHED_SRC"

# n: 5 valores do gemma (12288 já entra; vocab=262144 omitido por tamanho)
sed -i -E 's|std::vector<int> n = \{[^}]*\};|std::vector<int> n = {1536, 2048, 4096, 6144, 12288};|' "$PATCHED_SRC"

echo "=== patched bench source ==="
grep -E 'std::vector<int> [mkn] = \{' "$PATCHED_SRC"

g++ -O3 -std=c++20 \
    -I "$REPO_DIR/local-src/ggml/src/ggml-rknpu2/libs/include" \
    "$PATCHED_SRC" \
    "$REPO_DIR/local-src/ggml/src/ggml-rknpu2/libs/librknnrt.so" \
    -o "$OUT_BIN"

echo "[build] $OUT_BIN"
file "$OUT_BIN"
