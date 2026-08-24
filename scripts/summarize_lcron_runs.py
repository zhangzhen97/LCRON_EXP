#!/usr/bin/env python3

"""Summarize two-stage LCRON runs in the paper's five-metric format."""

import argparse
import re
from collections import defaultdict
from pathlib import Path
from statistics import mean, pstdev


PAPER_HEADER = re.compile(
    r"^paper_metrics\t[^\t]+\t"
    r"Joint/Recall@10@20\tRanking/Recall@10@20\tRanking/NDCG@10\t"
    r"Retrieval/Recall@10@30\tRetrieval/NDCG@10$"
)
PAPER_VALUE = re.compile(
    r"^paper_metrics\t[^\t]+\t"
    r"(?P<joint>[-+]?\d+(?:\.\d+)?)\t"
    r"(?P<ranking_recall>[-+]?\d+(?:\.\d+)?)\t"
    r"(?P<ranking_ndcg>[-+]?\d+(?:\.\d+)?)\t"
    r"(?P<retrieval_recall>[-+]?\d+(?:\.\d+)?)\t"
    r"(?P<retrieval_ndcg>[-+]?\d+(?:\.\d+)?)$"
)


def parse_paper_metrics(lines):
    for idx, line in enumerate(lines[:-1]):
        if PAPER_HEADER.match(line.strip()):
            match = PAPER_VALUE.match(lines[idx + 1].strip())
            if match:
                return tuple(float(match.group(name)) for name in (
                    "joint",
                    "ranking_recall",
                    "ranking_ndcg",
                    "retrieval_recall",
                    "retrieval_ndcg",
                ))
    return None


def parse_legacy_metrics(lines):
    """Parse old logs that predate paper_metrics output."""
    result = {}
    for idx, line in enumerate(lines[:-1]):
        header = line.strip().split("\t")
        values = lines[idx + 1].strip().split("\t")
        if len(header) != len(values) or len(header) < 4:
            continue
        if not header[0].startswith("metrics"):
            continue
        stage = header[2]
        if stage == "joint" and header[3] == "joint_recall":
            result["joint"] = float(values[3])
        elif stage == "prerank":
            metrics = dict(zip(header[3:], values[3:]))
            if "RECALL@10@20" in metrics and "NDCG@10@20" in metrics:
                result["ranking_recall"] = float(metrics["RECALL@10@20"])
                result["ranking_ndcg"] = float(metrics["NDCG@10@20"])
        elif stage == "retrival":
            metrics = dict(zip(header[3:], values[3:]))
            if "RECALL@10@30" in metrics and "NDCG@10@30" in metrics:
                result["retrieval_recall"] = float(metrics["RECALL@10@30"])
                result["retrieval_ndcg"] = float(metrics["NDCG@10@30"])

    names = ("joint", "ranking_recall", "ranking_ndcg", "retrieval_recall", "retrieval_ndcg")
    return tuple(result[name] for name in names) if all(name in result for name in names) else None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default="ablations")
    args = parser.parse_args()

    values = defaultdict(list)
    for path in sorted(Path(args.root).glob("seed_*/**/test.log")):
        seed = path.parent.parent.name
        lines = path.read_text(errors="replace").splitlines()
        row = parse_paper_metrics(lines) or parse_legacy_metrics(lines)
        if row is not None:
            values[path.parent.name].append((seed, *row))

    if not values:
        raise SystemExit(f"未找到 {args.root}/seed_*/<variant>/test.log 的论文五列指标")

    header = (
        "variant\tseed\tJoint/Recall@10@20\tRanking/Recall@10@20\t"
        "Ranking/NDCG@10\tRetrieval/Recall@10@30\tRetrieval/NDCG@10"
    )
    print(header)
    for variant in sorted(values):
        rows = values[variant]
        for seed, *metrics in rows:
            print(
                f"{variant}\t{seed}\t"
                f"{metrics[0]:.4f}\t{metrics[1]:.4f}\t{metrics[2]:.4f}\t"
                f"{metrics[3]:.4f}\t{metrics[4]:.4f}"
            )
        means = [mean(row[i] for row in rows) for i in range(1, 6)]
        stds = [pstdev(row[i] for row in rows) for i in range(1, 6)]
        formatted = "\t".join(f"{m:.4f}±{s:.4f}" for m, s in zip(means, stds))
        print(f"{variant}\tmean±std\t{formatted}")


if __name__ == "__main__":
    main()
