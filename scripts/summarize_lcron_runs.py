#!/usr/bin/env python3

"""Summarize metrics emitted by the multi-seed LCRON comparison runs."""

import argparse
import re
from collections import defaultdict
from pathlib import Path
from statistics import mean, pstdev


METRIC_RE = re.compile(
    r"^metrics\tlcron\tretrival\t"
    r"(?P<ndcg>[-+]?\d+(?:\.\d+)?)\t"
    r"(?P<recall>[-+]?\d+(?:\.\d+)?)\t"
    r"(?P<kdt>[-+]?\d+(?:\.\d+)?)$"
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default="ablations")
    args = parser.parse_args()

    values = defaultdict(list)
    for path in sorted(Path(args.root).glob("seed_*/**/test.log")):
        variant = path.parent.name
        for line in path.read_text(errors="replace").splitlines():
            match = METRIC_RE.match(line.strip())
            if match:
                values[variant].append((path.parent.parent.name, *map(float, match.groups())))

    if not values:
        raise SystemExit(f"未找到 {args.root}/seed_*/<variant>/test.log 的 metrics 行")

    print("variant\tseed\tNDCG@10@30\tRECALL@10@30\tKDT")
    for variant in sorted(values):
        rows = values[variant]
        for seed, ndcg, recall, kdt in rows:
            print(f"{variant}\t{seed}\t{ndcg:.4f}\t{recall:.6f}\t{kdt:.4f}")
        print(
            f"{variant}\tmean±std\t"
            f"{mean(r[1] for r in rows):.4f}±{pstdev(r[1] for r in rows):.4f}\t"
            f"{mean(r[2] for r in rows):.6f}±{pstdev(r[2] for r in rows):.6f}\t"
            f"{mean(r[3] for r in rows):.4f}±{pstdev(r[3] for r in rows):.4f}"
        )


if __name__ == "__main__":
    main()
