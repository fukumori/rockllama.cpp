#!/usr/bin/env bash
# Snapshot e diff de /sys/class/devfreq/dmc/trans_stat — substituto do
# rw_amount que o driver RKNPU v0.9.8 não expõe.
#
# trans_stat é cumulativo por estado de freq desde boot. Snapshot antes/depois
# de um workload → diff dá tempo gasto em cada freq. Razão (tempo @ max_freq /
# total) ≈ pressão sustentada na controladora DDR.
#
# Uso:
#   bash phase2-dmc-snapshot.sh save BEFORE.txt
#   <rode o bench>
#   bash phase2-dmc-snapshot.sh save AFTER.txt
#   bash phase2-dmc-snapshot.sh diff BEFORE.txt AFTER.txt

set -euo pipefail

DMC=/sys/class/devfreq/dmc

snap() {
    local out="$1"
    {
        echo "# $(date -Iseconds)"
        echo "# epoch_ms=$(date +%s%3N)"
        echo "## cur_freq"
        cat "$DMC/cur_freq"
        echo "## governor"
        cat "$DMC/governor"
        echo "## load"
        cat "$DMC/load" 2>/dev/null || echo "(no load file)"
        echo "## trans_stat"
        cat "$DMC/trans_stat"
    } > "$out"
    echo "[snap] -> $out"
}

extract_epoch_ms() {
    awk '/^# epoch_ms=/ { sub(/^# epoch_ms=/, ""); print; exit }' "$1"
}

# Parses trans_stat into "freq:ms" pairs. State-machine: só lê linhas entre
# `## trans_stat` e `Total transition`. Cada linha tem o formato:
#  * 534000000:         0        24         0      2302   6534203      (com space após *)
#  *1320000000:         0         0         0      62    258426        (sem space após *)
#   1968000000:         0         0         0         0         0
# Acha o token "<digits>:" entre os campos, NF >= 5.
extract_time_ms() {
    local file="$1"
    awk '
        /^## trans_stat/ { in_block=1; next }
        /^Total transition/ { in_block=0 }
        in_block && NF >= 5 {
            for (i=1; i<=NF; i++) {
                tok=$i
                sub(/^\*/, "", tok)
                if (tok ~ /^[0-9]+:$/) {
                    sub(/:$/, "", tok)
                    printf "%s %s\n", tok, $NF
                    break
                }
            }
        }
    ' "$file"
}

diff_snap() {
    local before="$1"
    local after="$2"
    declare -A before_ms after_ms

    while read -r freq ms; do before_ms["$freq"]="$ms"; done < <(extract_time_ms "$before")
    while read -r freq ms; do  after_ms["$freq"]="$ms"; done < <(extract_time_ms "$after")

    local epoch_before epoch_after wall_clock_ms
    epoch_before=$(extract_epoch_ms "$before")
    epoch_after=$(extract_epoch_ms "$after")
    wall_clock_ms=$(( epoch_after - epoch_before ))

    local total_delta=0
    declare -A delta_ms
    for freq in "${!after_ms[@]}"; do
        local b="${before_ms[$freq]:-0}"
        local d=$(( ${after_ms[$freq]} - b ))
        delta_ms["$freq"]=$d
        total_delta=$(( total_delta + d ))
    done

    echo "# DMC residency delta (before -> after)"
    echo "wall_clock_ms=$wall_clock_ms"
    echo "sum_delta_ms=$total_delta (lazy: só atualiza ao transicionar; saldo = residência no estado corrente sem ticks)"
    echo
    echo "freq_hz          delta_ms     %_of_wall_clock   %_of_recorded"
    # Sort freqs descending
    for freq in $(printf '%s\n' "${!delta_ms[@]}" | sort -nr); do
        local d="${delta_ms[$freq]}"
        local pct_wc pct_rec
        pct_wc=$(awk -v d="$d" -v t="$wall_clock_ms" 'BEGIN{ if(t==0){print "0.0"} else {printf "%.1f", 100.0*d/t} }')
        pct_rec=$(awk -v d="$d" -v t="$total_delta" 'BEGIN{ if(t==0){print "0.0"} else {printf "%.1f", 100.0*d/t} }')
        printf "%-16s %-12s %-16s %s%%\n" "$freq" "$d" "${pct_wc}%" "$pct_rec"
    done
    echo

    # GO/NO-GO: use wall-clock denominator (mais robusto contra lazy update).
    local max_freq
    max_freq=$(printf '%s\n' "${!delta_ms[@]}" | sort -nr | head -1)
    local d_max="${delta_ms[$max_freq]}"
    local pct_wc
    pct_wc=$(awk -v d="$d_max" -v t="$wall_clock_ms" 'BEGIN{ if(t==0){print "0.0"} else {printf "%.1f", 100.0*d/t} }')
    echo "max_freq=$max_freq delta_at_max_ms=$d_max %_of_wall_clock=$pct_wc"
    awk -v p="$pct_wc" 'BEGIN{
        if (p+0 >= 60) print "DDR-bound (>60% wall-clock @ max freq) — skip G/H/L, go to J/O";
        else if (p+0 >= 25) print "partially DDR-bound (25-60% wall-clock @ max) — G/H podem ajudar seletivamente";
        else print "compute-bound (<25% wall-clock @ max) — proceed with G/H/L";
    }'
}

case "${1:-help}" in
    save) snap "${2:-/tmp/dmc-snap.txt}" ;;
    diff) diff_snap "$2" "$3" ;;
    instant)
        # Quick one-shot summary
        echo "cur_freq=$(cat $DMC/cur_freq)"
        echo "load=$(cat $DMC/load 2>/dev/null || echo n/a)"
        echo "governor=$(cat $DMC/governor)"
        ;;
    help|*)
        sed -n '1,15p' "$0"
        ;;
esac
