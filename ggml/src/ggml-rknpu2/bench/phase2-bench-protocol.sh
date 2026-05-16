#!/usr/bin/env bash
# Phase 2 — protocolo de bench formalizado (Item C do plano de consenso 2026-05-15).
#
# Reúne a higiene da seção 7.2 do plano em um único entrypoint reproduzível:
#   - captura de ambiente (§7.1)
#   - switch de profile para "performance" (NPU 1 GHz, A76 cluster pinned)
#   - taskset -c 4-7 + chrt -f 50 + env vars completos do compose
#   - captura de route_stats no backend_free + dmesg tail
#   - reversão de profile para "init" (ondemand) ao fim
#
# Uso:
#   bash phase2-bench-protocol.sh env                       # só env-report
#   bash phase2-bench-protocol.sh bench [IMG] [MODEL]       # 5x pp512 + 5x tg128
#   bash phase2-bench-protocol.sh profile bench [IMG] [...] # bench + RKNPU_PROFILE_CSV
#
# Variáveis opcionais (override por env):
#   IMG, MODEL, ROUNDS, OUT_DIR, BENCH_ARGS, PROFILE_CSV
#
# Pré-condições (operador prepara):
#   - rockllama.cpp produção parado se IMG ocupa NPU (`docker stop rockllama.cpp`)
#   - voz Tsukai pausada / aviso ao usuário
#   - sudoers NOPASSWD para /usr/local/sbin/rk3588-power-profile {performance,init}
#
# Saída:
#   $OUT_DIR/env-report.md
#   $OUT_DIR/<preset>-bench.log
#   $OUT_DIR/<preset>-route-stats.log (se IMG é RKNPU build)
#   $OUT_DIR/<preset>-dmesg-tail.log
#   $OUT_DIR/<preset>-profile.csv (opcional)

set -euo pipefail

MODELS=/home/fukumori/HomeAssistant/gguf-models
DEFAULT_IMG="local/rockllama.cpp:latest"
DEFAULT_MODEL="/models/gemma-4-E2B-it-Q8_0.gguf"
TS=$(date +%Y-%m-%d-%H%M%S)
OUT_DIR="${OUT_DIR:-/home/fukumori/HomeAssistant/rockllama.cpp/baselines/phase2-bench-protocol-${TS}}"
ROUNDS="${ROUNDS:-5}"
BENCH_ARGS="${BENCH_ARGS:--p 512 -n 128 -t 4 --progress}"

mkdir -p "$OUT_DIR"

capture_env() {
    local out="$OUT_DIR/env-report.md"
    {
        echo "# env-report — $TS"
        echo
        echo "## uname"
        uname -a
        echo
        echo "## NPU devfreq"
        echo "governor=$(cat /sys/class/devfreq/fdab0000.npu/governor)"
        echo "cur_freq=$(cat /sys/class/devfreq/fdab0000.npu/cur_freq)"
        echo "available=$(cat /sys/class/devfreq/fdab0000.npu/available_frequencies)"
        echo
        echo "## DMC devfreq"
        echo "governor=$(cat /sys/class/devfreq/dmc/governor)"
        echo "cur_freq=$(cat /sys/class/devfreq/dmc/cur_freq)"
        echo
        echo "## CPU policies"
        for p in /sys/devices/system/cpu/cpufreq/policy*; do
            echo "$(basename "$p") governor=$(cat "$p/scaling_governor") cur=$(cat "$p/scaling_cur_freq") max=$(cat "$p/scaling_max_freq") min=$(cat "$p/scaling_min_freq")"
        done
        echo
        echo "## Thermal"
        for z in /sys/class/thermal/thermal_zone*; do
            echo "$(cat "$z/type"): $(cat "$z/temp")"
        done
        echo
        echo "## /proc/meminfo (head)"
        head -5 /proc/meminfo
        echo
        echo "## dmesg | grep RKNPU (tail 30)"
        dmesg 2>/dev/null | grep -i -E 'rknpu|rknn|iommu|dma|cma' | tail -30 || echo "(dmesg restricted or empty)"
        echo
        echo "## Container state"
        docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | grep -E 'rockllama|home|searx|piper|whisper|wyoming' || true
        echo
        echo "## librknnrt.so SHA256 (host)"
        sha256sum /home/fukumori/HomeAssistant/rockllama.cpp/local-src/ggml/src/ggml-rknpu2/libs/librknnrt.so 2>/dev/null || true
    } > "$out"
    echo "env-report -> $out"
}

set_profile_performance() {
    echo "[profile] switching to performance"
    sudo -n /usr/local/sbin/rk3588-power-profile performance
    local g cur
    g=$(cat /sys/class/devfreq/fdab0000.npu/governor)
    cur=$(cat /sys/class/devfreq/fdab0000.npu/cur_freq)
    echo "[profile] NPU governor=$g cur_freq=$cur"
    if [ "$g" != "performance" ] || [ "$cur" != "1000000000" ]; then
        echo "[profile] WARN: NPU not pinned at 1 GHz performance" >&2
    fi
}

restore_profile_init() {
    echo "[profile] reverting to init"
    sudo -n /usr/local/sbin/rk3588-power-profile init || true
}

run_bench() {
    local img="${1:-$DEFAULT_IMG}"
    local model="${2:-$DEFAULT_MODEL}"
    local tag="${3:-bench}"
    local csv_path="${PROFILE_CSV:-}"
    local out_log="$OUT_DIR/${tag}-bench.log"
    local route_log="$OUT_DIR/${tag}-route-stats.log"
    local dmesg_log="$OUT_DIR/${tag}-dmesg-tail.log"

    echo "[bench] img=$img model=$model tag=$tag rounds=$ROUNDS"
    echo "[bench] -> $out_log"

    local csv_args=()
    if [ -n "$csv_path" ]; then
        # csv_path é local-host; map para /tmp/profile.jsonl dentro do container
        csv_args=(-v "$(dirname "$csv_path")":/profile-out -e "RKNPU_PROFILE_CSV=/profile-out/$(basename "$csv_path")")
        echo "[bench] RKNPU_PROFILE_CSV=$csv_path"
    fi

    # NOTA: o original §7.2 do plano sugeriu `sudo taskset -c 4-7 chrt -f 50` outer.
    # Removido aqui porque (a) NOPASSWD do fukumori cobre só rk3588-power-profile;
    # (b) `--cpuset-cpus=4-7` em docker já pin a CPU exatamente nos A76 big cores;
    # (c) chrt -f 50 é nice-to-have mas não crítico em janela de bench >25s. Decisão
    # registrada na entrada de audit log "Fase 2.B" de 2026-05-16. Se quiser RT prio,
    # adicione `(root) NOPASSWD: /usr/bin/taskset, /usr/bin/chrt` no sudoers e
    # reintroduza o prefixo aqui.
    docker run --rm \
            --cpuset-cpus="4-7" --cap-add SYS_NICE --ulimit nofile=65535:65535 \
            --device /dev/dri --device /dev/dma_heap --device /dev/mpp_service --device /dev/rga \
            -v /proc/device-tree/compatible:/proc/device-tree/compatible:ro \
            -v "$MODELS":/models:ro \
            -e RKNPU_DEVICE=RK3588 \
            -e RKNPU_CORES=0,1,2 \
            -e RKNPU_BATCHED_MM_ENABLE=1 \
            "${csv_args[@]}" \
            --entrypoint llama-bench \
            "$img" \
            -m "$model" $BENCH_ARGS -r "$ROUNDS" 2>&1 | tee "$out_log" || true

    # route stats: o backend imprime no backend_free (final do programa); o log acima já captura.
    grep -E "RKNPU_ROUTE_STATS|rejected_buckets|ctx_create|tensor_buffer" "$out_log" > "$route_log" 2>/dev/null || true

    dmesg 2>/dev/null | tail -30 > "$dmesg_log" 2>/dev/null || true
}

run_bench_cpu_only() {
    # BL-CPU: imagem sem o backend RKNPU. Não precisa de NPU exclusivo,
    # mas mantém o pin 4-7 via docker --cpuset-cpus para coerência metodológica.
    # (sudo+chrt outer removido pelo mesmo motivo de run_bench acima.)
    local img="${1:-local/rockllama.cpp:cpu-only}"
    local model="${2:-$DEFAULT_MODEL}"
    local out_log="$OUT_DIR/bl-cpu-bench.log"
    echo "[bl-cpu] img=$img -> $out_log"
    docker run --rm \
            --cpuset-cpus="4-7" --cap-add SYS_NICE --ulimit nofile=65535:65535 \
            -v "$MODELS":/models:ro \
            --entrypoint llama-bench \
            "$img" \
            -m "$model" $BENCH_ARGS -r "$ROUNDS" 2>&1 | tee "$out_log" || true
}

case "${1:-help}" in
    env)
        capture_env
        ;;
    bench)
        shift
        capture_env
        set_profile_performance
        run_bench "${1:-$DEFAULT_IMG}" "${2:-$DEFAULT_MODEL}" "${3:-bench}"
        restore_profile_init
        ;;
    profile)
        # bench + RKNPU_PROFILE_CSV (op-profile-base.jsonl)
        shift
        : "${PROFILE_CSV:?defina PROFILE_CSV=/host/path/op-profile.jsonl}"
        capture_env
        set_profile_performance
        run_bench "${1:-$DEFAULT_IMG}" "${2:-$DEFAULT_MODEL}" "${3:-profile}"
        restore_profile_init
        ;;
    cpu)
        shift
        capture_env
        set_profile_performance
        run_bench_cpu_only "${1:-local/rockllama.cpp:cpu-only}" "${2:-$DEFAULT_MODEL}"
        restore_profile_init
        ;;
    help|*)
        sed -n '1,30p' "$0"
        exit 0
        ;;
esac

echo
echo "[done] artefatos em $OUT_DIR"
ls -la "$OUT_DIR"
