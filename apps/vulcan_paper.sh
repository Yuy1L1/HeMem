#!/usr/bin/env bash
set -euo pipefail

# Experiment configuration

CPU_LC="8-12"        # FlexKVS (LC)
CPU_BE1="13-17"      # GAPBS PageRank (1st BE)
CPU_BE2="18-22"      # NAS BT (2nd BE)

MEM_NODE=0           # Preferred NUMA memory node
START_CPU=8
MISS_RATIO=0.8
LIBHEMEM="/home/yuyi/HeMem/src/libhemem.so"

OUTDIR="./vulcan_runs"
mkdir -p "$OUTDIR"

TAG="$(date +%Y%m%d-%H%M%S)"

# Paths to workloads

FLEXKVS_BIN="flexkvs/kvsbench"
GAPBS_PR_BIN="apps/gapbs/pr"
#TODO: nas bt benchmark not sure how to write???
NAS_BT_BIN="/home/yuyi/HeMem/apps/nas-bt-c-benchmark/bt"

# Arguments (adjust as needed)
FLEXKVS_ARGS="--json"    # or whatever FlexKVS accepts
GAPBS_ARGS="-g 29"       # huge graph (2^29 edges). Adjust if needed.
NAS_BT_ARGS="class=D"    # choose C/D/E depending on memory size

# Logging setup

LC_LOG="${OUTDIR}/flexkvs-lc-${TAG}.log"
BE1_LOG="${OUTDIR}/gapbs-pr-be1-${TAG}.log"
BE2_LOG="${OUTDIR}/nas-bt-be2-${TAG}.log"

echo "[INFO] Starting experiment tag=$TAG"
echo "[INFO] Output directory: $OUTDIR"
echo

# 1. Start FlexKVS (LC)

echo "[T=0s] Launching FlexKVS (LC)..."

nice -20 numactl -C "${CPU_LC}" -m "${MEM_NODE}" -- \
    env START_CPU="${START_CPU}" \
        MISS_RATIO="${MISS_RATIO}" \
        LC_WORKLOAD_OR_NOT=1 \
        LD_PRELOAD="${LIBHEMEM}" \
    "${FLEXKVS_BIN}" ${FLEXKVS_ARGS} \
    > "${LC_LOG}" 2>&1 &

PID_LC=$!
echo "[INFO] FlexKVS started as LC (PID ${PID_LC}), log=${LC_LOG}"
echo

# Delay before BE1

echo "[INFO] Sleeping 50 seconds before launching PageRank..."
sleep 50

# 2. Start GAPBS PageRank (BE1)

echo "[T=50s] Launching GAPBS PageRank (BE1)..."

nice -20 numactl -C "${CPU_BE1}" -m "${MEM_NODE}" -- \
    env START_CPU="${START_CPU}" \
        MISS_RATIO="${MISS_RATIO}" \
        LC_WORKLOAD_OR_NOT=0 \
        LD_PRELOAD="${LIBHEMEM}" \
    "${GAPBS_PR_BIN}" ${GAPBS_ARGS} \
    > "${BE1_LOG}" 2>&1 &

PID_BE1=$!
echo "[INFO] PageRank started as BE1 (PID ${PID_BE1}), log=${BE1_LOG}"
echo

# Delay before BE2

echo "[INFO] Sleeping 110 seconds before launching NAS BT..."
sleep 110

# 3. Start NAS BT (BE2)

echo "[T=160s] Launching NAS BT (BE2)..."

nice -20 numactl -C "${CPU_BE2}" -m "${MEM_NODE}" -- \
    env START_CPU="${START_CPU}" \
        MISS_RATIO="${MISS_RATIO}" \
        LC_WORKLOAD_OR_NOT=0 \
        LD_PRELOAD="${LIBHEMEM}" \
    "${NAS_BT_BIN}" ${NAS_BT_ARGS} \
    > "${BE2_LOG}" 2>&1 &

PID_BE2=$!
echo "[INFO] NAS BT started as BE2 (PID ${PID_BE2}), log=${BE2_LOG}"
echo

# Wait for all to finish

echo "[INFO] Waiting for all workloads to finish..."
wait "${PID_LC}"
wait "${PID_BE1}"
wait "${PID_BE2}"

echo
echo "[INFO] All workloads completed."
echo "  LC (FlexKVS): ${LC_LOG}"
echo "  BE1 (PageRank): ${BE1_LOG}"
echo "  BE2 (NAS-BT): ${BE2_LOG}"
echo "[INFO] Experiment tag: ${TAG}"

