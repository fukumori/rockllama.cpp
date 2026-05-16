# RKNPU2 bench tooling

Scripts de bench, captura de ambiente e análise de DDR usados nas fases 2, 6 e 7 do
plano de revalidação RKNPU2/RK3588 (2026-05-15). Snapshot versionado das ferramentas;
o working copy live está em `/home/fukumori/HomeAssistant/rockllama.cpp/scripts/`.

Os scripts contêm paths absolutos específicos do setup Rock 5B do autor
(`/home/fukumori/HomeAssistant/...`). Para usar em outra máquina, ajustar as
constantes no topo de cada script.

## Conteúdo

| Script | Função | Janela NPU? | Pré-req sudo? |
|---|---|---|---|
| [phase2-bench-protocol.sh](phase2-bench-protocol.sh) | Item C do plano: bench reproduzível (`llama-bench`) com env-report §7.1, profile switch via NOPASSWD, env vars do compose. Modos: `env`, `bench`, `profile`, `cpu`. | sim (modo bench/profile/cpu) | NOPASSWD em `rk3588-power-profile` |
| [phase2-dmc-snapshot.sh](phase2-dmc-snapshot.sh) | Item D' do plano: proxy DDR ceiling via `/sys/class/devfreq/dmc/trans_stat` (substitui `rw_amount` que não existe no driver RKNPU v0.9.8 deste kernel). Modos: `save`, `diff`, `instant`. Veredito automático DDR-bound / partial / compute-bound usando wall-clock como denominador. | não (só leitura de devfreq) | não (user-readable) |
| [build-bl-raw-msweep.sh](build-bl-raw-msweep.sh) | Constrói variante do harness allbilly `rk3588-matmul-bench` com M ∈ {1,2,4,8,16,32,64,128} (vs M=128 fixo do original). Saída: `bin/bench_local_msweep`. | não (só build) | não |
| [build-bl-raw-gemma.sh](build-bl-raw-gemma.sh) | Variante do harness allbilly focada em shapes do Gemma E2B: K={1536,2048,4096,6144,8192}, N={1536,2048,4096,6144,12288}, M={1,512}. Usada para derisk Item J. Saída: `bin/bench_local_gemma`. | não (só build) | não |

## Sequência típica para reproduzir o protocolo de bench

```bash
# 1. captura de ambiente (sem janela NPU; idle)
bash phase2-bench-protocol.sh env

# 2. snapshot dmc antes do bench
bash phase2-dmc-snapshot.sh save dmc-before.txt

# 3. bench full (cobre profile switch + env vars + taskset; prod parado)
docker stop rockllama.cpp
sudo /usr/local/sbin/rk3588-power-profile performance
# (rodar bench manual ou via phase2-bench-protocol.sh bench ...)

# 4. snapshot dmc depois + veredito
bash phase2-dmc-snapshot.sh save dmc-after.txt
bash phase2-dmc-snapshot.sh diff dmc-before.txt dmc-after.txt
#    emite: DDR-bound (>60% @ max) / partially (25-60%) / compute-bound (<25%)

# 5. restore
sudo /usr/local/sbin/rk3588-power-profile init
docker start rockllama.cpp
```

## Contexto

Plano de consenso completo em `/home/fukumori/plans/rockllama-rk3588-revalidation-perf-2026-05-15-consensus.md`
(fora deste repo). Audit logs das fases 2 (DDR-bound confirmado),
6 (Item J deprioritizado) e 7 (Item M abortado por PPL 11× pior em gemma)
ficam lá. Aqui só a infraestrutura de medição.
