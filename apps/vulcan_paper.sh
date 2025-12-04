#!/usr/bin/env bash
set -euo pipefail

#############################################
# Basic env / paths (mirrors run_static.sh)
#############################################

HEMEM="/home/yuyi/HeMem"
OUTDIR="${HEMEM}/vulcan-paper"

export LD_LIBRARY_PATH="${HEMEM}/src:${LD_LIBRARY_PATH:-}"
echo 1000000 | sudo tee /proc/sys/vm/max_map_count >/dev/null

mkdir -p "${OUTDIR}/logs"
mkdir -p "${OUTDIR}/perf"

TAG="$(date +%Y%m%d-%H%M%S)"

#############################################
# Experiment configuration
#############################################

# CPU layout (physical core IDs)
CPU_LC="8-12"      # FlexKVS (LC)
CPU_BE1="13-17"    # GAPBS PageRank (BE1)
CPU_BE2="18-23"    # NAS BT (BE2)

MEM_NODE=0         # NUMA node for CPU + memory
START_CPU=8
MISS_RATIO=0.8

LIBHEMEM="${HEMEM}/src/libhemem.so"

#############################################
# Workload binaries
#############################################

FLEXKVS_BIN="${HEMEM}/apps/flexkvs/kvsbench"
GAPBS_PR_BIN="${HEMEM}/apps/gapbs/pr"
NAS_BT_BIN="${HEMEM}/apps/nas-bt-c-benchmark/NPB-OMP/bin/bt.E"

#############################################
# Workload arguments
#############################################

# ~45 GiB FlexKVS size, 250s total runtime
FLEXKVS_ARGS="-t 4 -T 250 -w 30 -h 0.15 127.0.0.1:11211 -S $((45*1024*1024*1024))"

# GAPBS PageRank: graph size 2^27, 50 iterations
GAPBS_ARGS="-n 50 -g 27"

#NAS_BT by default is 166GiB

#############################################
# Logging setup
#############################################

LC_LOG="${OUTDIR}/logs/flexkvs-lc-${TAG}.log"
BE1_LOG="${OUTDIR}/logs/gapbs-pr-be1-${TAG}.log"
BE2_LOG="${OUTDIR}/logs/nas-bt-be2-${TAG}.log"

echo "[INFO] Starting Vulcan experiment tag=${TAG}"
echo "[INFO] Output dir: ${OUTDIR}"
echo

#############################################
# 1. Start FlexKVS (LC) at t = 0
#############################################

echo "[T=0s] Launching FlexKVS (LC)..."

nice -20 numactl -N "${MEM_NODE}" -m "${MEM_NODE}" --physcpubind="${CPU_LC}" -- \
  env START_CPU="${START_CPU}" \
      MISS_RATIO="${MISS_RATIO}" \
      LC_WORKLOAD_OR_NOT=1 \
      LD_PRELOAD="${LIBHEMEM}" \
  "${FLEXKVS_BIN}" ${FLEXKVS_ARGS} \
  > "${LC_LOG}" 2>&1 &

PID_LC=$!
echo "[INFO] FlexKVS started as LC (PID=${PID_LC}), log=${LC_LOG}"
echo

#############################################
# 2. Start GAPBS PageRank (BE1) at 50s
#############################################

echo "[INFO] Sleeping 50 seconds before launching PageRank..."
sleep 50

echo "[T=50s] Launching GAPBS PageRank (BE1)..."

nice -20 numactl -N "${MEM_NODE}" -m "${MEM_NODE}" --physcpubind="${CPU_BE1}" -- \
  env START_CPU="${START_CPU}" \
      MISS_RATIO="${MISS_RATIO}" \
      LC_WORKLOAD_OR_NOT=0 \
      OMP_THREAD_LIMIT=8 \
      LD_PRELOAD="${LIBHEMEM}" \
  "${GAPBS_PR_BIN}" ${GAPBS_ARGS} \
  > "${BE1_LOG}" 2>&1 &

PID_BE1=$!
echo "[INFO] PageRank started as BE1 (PID=${PID_BE1}), log=${BE1_LOG}"
echo

#############################################
# 3. Start NAS BT (BE2) at 110s
#############################################

echo "[INFO] Sleeping 60 seconds before launching NAS BT..."
sleep 60

echo "[T=110s] Launching NAS BT (BE2)..."

nice -20 numactl -N "${MEM_NODE}" -m "${MEM_NODE}" --physcpubind="${CPU_BE2}" -- \
  env START_CPU="${START_CPU}" \
      MISS_RATIO="${MISS_RATIO}" \
      LC_WORKLOAD_OR_NOT=0 \
      OMP_THREAD_LIMIT=5 \
      LD_PRELOAD="${LIBHEMEM}" \
  "${NAS_BT_BIN}" \
  > "${BE2_LOG}" 2>&1 &

PID_BE2=$!
echo "[INFO] NAS BT started as BE2 (PID=${PID_BE2}), log=${BE2_LOG}"
echo

#############################################
# Run for 250 seconds total, then kill all
#############################################

echo "[INFO] Running all workloads..."
sleep 140

echo "[INFO] 250 seconds elapsed. Killing all workloads..."
kill -9 "${PID_LC}" 2>/dev/null || true
kill -9 "${PID_BE1}" 2>/dev/null || true
kill -9 "${PID_BE2}" 2>/dev/null || true

echo
echo "[INFO] Experiment completed at T=250s."
echo "  LC (FlexKVS): ${LC_LOG}"
echo "  BE1 (GAPBS BC): ${BE1_LOG}"
echo "  BE2 (NAS-BT): ${BE2_LOG}"
echo "[INFO] Experiment tag: ${TAG}"

