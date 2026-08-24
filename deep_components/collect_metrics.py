import sys
import codecs

def parse_metrics(lines):
    if lines and lines[0].startswith("paper_metrics"):
        header_parts = lines[0].strip().split("\t")
        value_parts = lines[1].strip().split("\t") if len(lines) > 1 else []
        if len(header_parts) == len(value_parts):
            print("\t".join(header_parts[2:]))
            print("\t".join(value_parts[2:]))
        return

    metric_names = []
    metric_values = []

    i = 0
    while i < len(lines):
        header_parts = lines[i].strip().split()
        value_parts = lines[i + 1].strip().split()

        if len(header_parts) < 4 or len(value_parts) < 4 or len(header_parts)!=len(value_parts):
            i += 2
            continue

        stage = header_parts[2]
        keys = header_parts[3:]
        values = value_parts[3:]
        if len(keys) != len(values):
            i += 2
            continue

        for k, v in zip(keys, values):
            if "recall" in k.lower() or "ndcg" in k.lower():
                metric_names.append(f"{stage}#{k}")
                metric_values.append("%.4f" %(float(v)))
        i += 2

    header_line = "\t".join(metric_names)
    value_line = "\t".join(metric_values)

    print(header_line)
    print(value_line)

def collect_lines():
    metric_lines = []
    for line in sys.stdin.readlines():
        if not (line.startswith("metrics") or line.startswith("paper_metrics")):
            continue
        metric_lines.append(line)
    # New two-stage LCRON evaluation emits a paper_metrics pair. Prefer it
    # over the legacy per-stage rows so the collector prints exactly the five
    # columns used by the paper.
    paper_lines = [line for line in metric_lines if line.startswith("paper_metrics")]
    if len(paper_lines) >= 2:
        return paper_lines[:2]
    return metric_lines

def main():
    metric_lines = collect_lines()

    parse_metrics(metric_lines)

if __name__ == "__main__":
    main()
