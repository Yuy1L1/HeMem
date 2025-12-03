#!/usr/bin/env bash
set -euo pipefail

# --- config you can tweak ---
CPU1="8,9"
CPU2="10,11"
CPU3="12,13"
MEM_NODE=0
START_CPU=8
MISS_RATIO=0.8

LIBHEMEM="/home/yuyi/HeMem/src/libhemem.so"
GUPS_BIN="./gups-pebs"

# GUPS arguments:
#   threads   = 2
#   ???      = 0
#   log2size = 36   (64 GiB)
#   ???      = 8
#   ???      = 35
#   ???      = 0
#   output   = path
GUPS_ARGS_COMMON="2 0 36 8 35 0"

OUTDIR="./vulcan_runs"
mkdir -p "$OUTDIR"

# timestamp tag for this experiment
TAG="$(date +%Y%m%d-%H%M%S)"

echo "[INFO] Starting LC GUPS (tag=$TAG)..."

LC_LOG="${OUTDIR}/gups-lc-${TAG}.log"
LC_RES="${OUTDIR}/gups-lc-${TAG}.txt"

nice -20 numactl -C "${CPU1}" -m "${MEM_NODE}" -- \
  env START_CPU="${START_CPU}" \
      MISS_RATIO="${MISS_RATIO}" \
      LC_WORKLOAD_OR_NOT=1 \
      LD_PRELOAD="${LIBHEMEM}" \
  "${GUPS_BIN}" ${GUPS_ARGS_COMMON} "${LC_RES}" \
  >"${LC_LOG}" 2>&1 &

LC_PID=$!
echo "[INFO] LC GUPS started with pid=${LC_PID}, log=${LC_LOG}"

echo "[INFO] Sleeping 5 seconds before starting BE GUPS..."
sleep 5

echo "[INFO] Starting BE GUPS..."

BE_LOG="${OUTDIR}/gups-be-${TAG}.log"
BE_RES="${OUTDIR}/gups-be-${TAG}.txt"

nice -20 numactl -C "${CPU2}" -m "${MEM_NODE}" -- \
  env START_CPU="${START_CPU}" \
      MISS_RATIO="${MISS_RATIO}" \
      LC_WORKLOAD_OR_NOT=0 \
      LD_PRELOAD="${LIBHEMEM}" \
  "${GUPS_BIN}" ${GUPS_ARGS_COMMON} "${BE_RES}" \
  >"${BE_LOG}" 2>&1 &

BE_PID=$!
echo "[INFO] BE GUPS started with pid=${BE_PID}, log=${BE_LOG}"

sleep 5

echo "[INFO] Starting SECOND BE GUPS..."

BE2_LOG="${OUTDIR}/gups-be2-${TAG}.log"
BE2_RES="${OUTDIR}/gups-be2-${TAG}.txt"

nice -20 numactl -C "${CPU3}" -m "${MEM_NODE}" -- \
  env START_CPU="${START_CPU}" \
      MISS_RATIO="${MISS_RATIO}" \
      LC_WORKLOAD_OR_NOT=0 \
      LD_PRELOAD="${LIBHEMEM}" \
  "${GUPS_BIN}" ${GUPS_ARGS_COMMON} "${BE2_RES}" \
  >"${BE2_LOG}" 2>&1 &

BE2_PID=$!
echo "[INFO] SECOND BE GUPS started with pid=${BE2_PID}, log=${BE2_LOG}"

echo "[INFO] Waiting for GUPS to finish..."
wait "${LC_PID}"
echo "[INFO] LC GUPS finished."
wait "${BE_PID}"
echo "[INFO] BE GUPS finished."
wait "${BE2_PID}"
echo "[INFO] SECOND BE GUPS finished."

echo "[INFO] Done. Logs:"
echo "  LC: ${LC_LOG}"
echo "  BE: ${BE_LOG}"
echo "  LC result: ${LC_RES}"
echo "  BE result: ${BE_RES}"
echo "  SECOND BE result: ${BE2_RES}"
echo "[INFO] Experiment tag: ${TAG}"
