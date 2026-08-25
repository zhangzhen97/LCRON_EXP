#!/usr/bin/env python3
"""Poll the remote LCRON run and post a Markdown summary when complete."""

from __future__ import annotations

import argparse
import subprocess
import time
from pathlib import Path

from corp_rec.im import send_webhook


WEB_SHELL = Path(
    "/Users/zz/.codex/plugins/cache/universe-model-marketplace/"
    "universe-model/0.8.26/skills/webshell/scripts/webshell_cli.py"
)
REMOTE_URL = (
    "https://kml.corp.kuaishou.com/#/system/project/10049/"
    "machine-terminal/100000920?fullScreen=1&originPid=10049&provider=Ailurus"
)
VARIANTS = ("baseline", "no_down", "no_detach")
METRIC_NAMES = (
    "Joint/Recall@10@20",
    "Ranking/Recall@10@20",
    "Ranking/NDCG@10",
    "Retrieval/Recall@10@30",
    "Retrieval/NDCG@10",
)


def remote_exec(command: str) -> str:
    result = subprocess.run(
        [str(WEB_SHELL), "exec", "--url", REMOTE_URL, "--cmd", command, "--timeout", "60"],
        check=False,
        capture_output=True,
        text=True,
        timeout=90,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def completion_status(root: str) -> tuple[int, int]:
    command = (
        f"root={root!r}; "
        "active=$(ps -eo args= | grep \"$root\" | "
        "grep -E \"run_train2.py|run_test2.py\" | grep -v grep | "
        "wc -l | tr -d ' '); "
        "metrics=$(find \"$root\" -type f -name test.log "
        "-exec grep -l '^paper_metrics' {} \\; 2>/dev/null | "
        "wc -l | tr -d ' '); "
        "echo \"active=$active metrics=$metrics\""
    )
    output = remote_exec(command)
    line = next((line for line in output.splitlines() if line.startswith("active=")), "")
    fields = dict(item.split("=", 1) for item in line.split() if "=" in item)
    return int(fields.get("active", "-1")), int(fields.get("metrics", "-1"))


def markdown_from_summary(summary: str, root: str) -> str:
    rows = {}
    for line in summary.splitlines():
        fields = line.split("\t")
        if len(fields) == 7 and fields[1] == "mean±std" and fields[0] in VARIANTS:
            rows[fields[0]] = fields[2:]

    if set(rows) != set(VARIANTS):
        raise RuntimeError("summary does not contain all three variant mean±std rows")

    parts = [
        "# LCRON 实验结果", "",
        f"- 实验目录：`{root}`",
        "- 配置：优化版 loss、5 个 seed、8 卡并行",
        "- 指标：论文五列，均为 mean ± std", "",
    ]
    for variant in VARIANTS:
        parts.extend([f"## {variant}", ""])
        for name, value in zip(METRIC_NAMES, rows[variant]):
            parts.append(f"- **{name}**：{value}")
        parts.append("")
    parts.extend(["结果已由远端实验完成后自动汇总。", "", "@zhangzhen24"])
    return "\n".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--expected", type=int, default=15)
    parser.add_argument("--interval", type=int, default=300)
    parser.add_argument("--state", default="/tmp/lcron_exp_notify.sent")
    args = parser.parse_args()

    state = Path(args.state)
    if state.exists():
        print(f"notification already sent: {state}")
        return 0

    while True:
        try:
            active, metrics = completion_status(args.root)
            print(f"active={active} metrics={metrics}", flush=True)
            if active == 0 and metrics >= args.expected:
                summary = remote_exec(
                    "cd /home/zhangzhen24/experiments/LCRON_EXP && "
                    f"python3 scripts/summarize_lcron_runs.py {args.root}"
                )
                message = markdown_from_summary(summary, args.root)
                result = send_webhook(
                    message,
                    webhook_name="lcron-exp",
                    msgtype="markdown",
                    mentioned_users=["zhangzhen24"],
                )
                state.write_text("sent\n")
                print(result, flush=True)
                return 0
        except Exception as exc:
            print(f"poll failed: {exc}", flush=True)
        time.sleep(args.interval)


if __name__ == "__main__":
    raise SystemExit(main())
