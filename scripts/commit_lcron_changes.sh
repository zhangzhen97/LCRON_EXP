#!/usr/bin/env bash

# Commit and push only the LCRON experiment code. Runtime data, logs, checkpoints,
# connection credentials, and local environment files are intentionally excluded.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"
message="${1:-实验：增加 LCRON down-loss 与 detach 消融开关}"

files=(
  deep_components/loss/two_stage/lcron.py
  deep_components/loss/three_stage/lcron.py
  deep_components/run_train2.py
  deep_components/run_train3.py
  deep_components/metrics.py
  deep_components/run_test2.py
  deep_components/collect_metrics.py
  two_stage/run_x2.sh
  three_stage/run_x3.sh
  scripts/run_lcron_compare.sh
  scripts/summarize_lcron_runs.py
  scripts/commit_lcron_changes.sh
)

git diff --check
git add -- "${files[@]}"

if git diff --cached --quiet; then
  echo "没有待提交的 LCRON 代码改动。"
  exit 0
fi

git commit -m "${message}"
git push origin HEAD
