#!/usr/bin/env bash

# Run reproducible two-stage LCRON comparisons on the development machine.
# Arguments: [variant] [root_path]
# Variants: baseline, no_down, no_detach, all (default: all)

set -euo pipefail

variant="${1:-all}"
root_path="${2:-${LCRON_EXP_ROOT:-$PWD/ablations}}"
data_path="${LCRON_EXP_DATA:-/share/ad/zhangzhen24/recflow/data}"
tau="${LCRON_EXP_TAU:-50}"
epochs="${LCRON_EXP_EPOCHS:-30}"
lr="${LCRON_EXP_LR:-1e-2}"
batch_size="${LCRON_EXP_BATCH_SIZE:-1024}"
export PYTHONPATH="${PWD}:${PWD}/deep_components${PYTHONPATH:+:${PYTHONPATH}}"

run_variant() {
  local name="$1"
  local cuda="$2"
  local use_down_loss="$3"
  local detach_permutation_matrix="$4"
  local run_root="${root_path}/${name}"

  mkdir -p "${run_root}/logs" "${run_root}/checkpoints"
  ln -sfn "${data_path}" "${run_root}/data"

  echo "[LCRON] ${name}: cuda=${cuda} use_down_loss=${use_down_loss} detach_permutation_matrix=${detach_permutation_matrix}"
  bash two_stage/run_x2.sh train lcron "${cuda}" "${tau}" "${epochs}" "${run_root}" \
    "${lr}" "${batch_size}" "${use_down_loss}" "${detach_permutation_matrix}"

  echo "[LCRON] ${name}: evaluating"
  CUDA_VISIBLE_DEVICES="${cuda}" \
    python3 -B -u deep_components/run_test2.py \
      --epochs="${epochs}" --loss_type=lcron --tau="${tau}" \
      --batch_size="${batch_size}" --infer_realshow_batch_size="${batch_size}" \
      --infer_recall_batch_size="${batch_size}" --emb_dim=8 --lr="${lr}" \
      --seq_len=50 --cuda="${cuda}" --root_path="${run_root}" \
      --print_freq=100 --tag=lcron-1st > "${run_root}/test.log" 2>&1
}

case "${variant}" in
  baseline)
    run_variant baseline "${LCRON_EXP_BASELINE_CUDA:-0}" 1 1
    ;;
  no_down)
    run_variant no_down "${LCRON_EXP_ABLATION_CUDA:-1}" 0 1
    ;;
  no_detach)
    run_variant no_detach "${LCRON_EXP_ABLATION_CUDA:-1}" 1 0
    ;;
  all)
    run_variant baseline "${LCRON_EXP_BASELINE_CUDA:-0}" 1 1
    run_variant no_down "${LCRON_EXP_ABLATION_CUDA:-1}" 0 1
    run_variant no_detach "${LCRON_EXP_ABLATION_CUDA:-2}" 1 0
    ;;
  *)
    echo "usage: $0 [baseline|no_down|no_detach|all] [root_path]" >&2
    exit 2
    ;;
esac
