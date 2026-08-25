#!/usr/bin/env bash

# Run two-stage LCRON comparisons with fixed data/model hyperparameters on the development machine.
# Arguments: [variant] [root_path]
# Variants: baseline, no_down, no_detach, cascade_topk, all (default: all)
# Default seeds: five independent runs, matching the paper; override with LCRON_EXP_SEEDS="...".
# By default all eight GPUs are used as independent workers; override with
# LCRON_EXP_GPUS="0 1 2" when some cards are occupied by other jobs.

set -euo pipefail

variant="${1:-all}"
root_path="${2:-${LCRON_EXP_ROOT:-$PWD/ablations}}"
data_path="${LCRON_EXP_DATA:-/share/ad/zhangzhen24/recflow/data}"
tau="${LCRON_EXP_TAU:-50}"
epochs="${LCRON_EXP_EPOCHS:-30}"
lr="${LCRON_EXP_LR:-1e-2}"
batch_size="${LCRON_EXP_BATCH_SIZE:-1024}"
seeds="${LCRON_EXP_SEEDS:-1024 2024 3407 4099 5113}"
gpu_list="${LCRON_EXP_GPUS:-0 1 2 3 4 5 6 7}"
if [ -n "${LCRON_EXP_PYTHON:-}" ]; then
  python_bin="${LCRON_EXP_PYTHON}"
elif [ -x /share/ad/zq3/lcron/python3_7/bin/python ]; then
  python_bin="/share/ad/zq3/lcron/python3_7/bin/python"
else
  python_bin="python3"
fi
export LCRON_PYTHON="${python_bin}"
export PYTHONPATH="${PWD}:${PWD}/deep_components${PYTHONPATH:+:${PYTHONPATH}}"
echo "[LCRON] python=${python_bin}"

run_variant() {
  local name="$1"
  local cuda="$2"
  local use_down_loss="$3"
  local detach_permutation_matrix="$4"
  local seed="$5"
  local loss_type="$6"
  local recall_tau_scale="$7"
  local run_root="${root_path}/seed_${seed}/${name}"

  mkdir -p "${run_root}/logs" "${run_root}/checkpoints"
  ln -sfn "${data_path}" "${run_root}/data"

  echo "[LCRON] ${name}: loss=${loss_type} seed=${seed} cuda=${cuda} recall_tau_scale=${recall_tau_scale} use_down_loss=${use_down_loss} detach_permutation_matrix=${detach_permutation_matrix}"
  # Bind the process before Python/Torch is imported. Passing --cuda alone is
  # insufficient because run_train2.py selects cuda:0 after parsing args.
  CUDA_VISIBLE_DEVICES="${cuda}" \
    bash two_stage/run_x2.sh train "${loss_type}" "${cuda}" "${tau}" "${epochs}" "${run_root}" \
      "${lr}" "${batch_size}" "${use_down_loss}" "${detach_permutation_matrix}" "${seed}" \
      "${recall_tau_scale}"

  echo "[LCRON] ${name}: evaluating"
  CUDA_VISIBLE_DEVICES="${cuda}" \
    "${python_bin}" -B -u deep_components/run_test2.py \
      --epochs="${epochs}" --loss_type="${loss_type}" --tau="${tau}" \
      --batch_size="${batch_size}" --infer_realshow_batch_size="${batch_size}" \
      --infer_recall_batch_size="${batch_size}" --emb_dim=8 --lr="${lr}" \
      --seq_len=50 --cuda="${cuda}" --root_path="${run_root}" \
      --print_freq=100 --tag="${loss_type}-1st" > "${run_root}/test.log" 2>&1
}

task_names=()
task_down=()
task_detach=()
task_seeds=()
task_loss=()
task_tau_scale=()

add_tasks() {
  local name="$1"
  local use_down_loss="$2"
  local detach_permutation_matrix="$3"
  local loss_type="$4"
  local recall_tau_scale="$5"
  for seed in ${seeds}; do
    task_names+=("${name}")
    task_down+=("${use_down_loss}")
    task_detach+=("${detach_permutation_matrix}")
    task_seeds+=("${seed}")
    task_loss+=("${loss_type}")
    task_tau_scale+=("${recall_tau_scale}")
  done
}

case "${variant}" in
  baseline)
    add_tasks baseline 1 1 lcron 1.0
    ;;
  no_down)
    add_tasks no_down 0 1 lcron 1.0
    ;;
  no_detach)
    add_tasks no_detach 1 0 lcron 1.0
    ;;
  cascade_topk)
    add_tasks cascade_topk 1 1 lcron_topk 1.0
    ;;
  tau_sweep)
    tau_sweep="${LCRON_EXP_TAU_SWEEP:-0.25 0.5 1.0 2.0}"
    for scale in ${tau_sweep}; do
      scale_name="${scale/./}"
      add_tasks "cascade_tau${scale_name}" 1 1 lcron_topk "${scale}"
    done
    ;;
  all)
    add_tasks baseline 1 1 lcron 1.0
    add_tasks no_down 0 1 lcron 1.0
    add_tasks no_detach 1 0 lcron 1.0
    ;;
  *)
    echo "usage: $0 [baseline|no_down|no_detach|cascade_topk|tau_sweep|all] [root_path]" >&2
    exit 2
    ;;
esac

read -r -a gpus <<< "${gpu_list}"
if [ "${#gpus[@]}" -eq 0 ]; then
  echo "[LCRON] no GPUs configured; set LCRON_EXP_GPUS" >&2
  exit 2
fi

task_count="${#task_names[@]}"
worker_count="${#gpus[@]}"
if [ "${worker_count}" -gt "${task_count}" ]; then
  worker_count="${task_count}"
fi
mkdir -p "${root_path}/logs"
echo "[LCRON] parallel workers=${worker_count} gpus=${gpu_list} tasks=${task_count}"

worker() {
  local worker_id="$1"
  local cuda="$2"
  local task_idx="${worker_id}"
  while [ "${task_idx}" -lt "${task_count}" ]; do
    run_variant "${task_names[task_idx]}" "${cuda}" "${task_down[task_idx]}" \
      "${task_detach[task_idx]}" "${task_seeds[task_idx]}" "${task_loss[task_idx]}" \
      "${task_tau_scale[task_idx]}"
    task_idx=$((task_idx + worker_count))
  done
}

pids=()
for ((worker_id = 0; worker_id < worker_count; worker_id++)); do
  worker "${worker_id}" "${gpus[worker_id]}" \
    > "${root_path}/logs/worker_gpu-${gpus[worker_id]}.log" 2>&1 &
  pids+=("$!")
done

failed=0
for pid in "${pids[@]}"; do
  if ! wait "${pid}"; then
    failed=1
  fi
done
exit "${failed}"
