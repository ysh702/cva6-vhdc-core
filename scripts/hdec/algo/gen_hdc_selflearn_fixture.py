#!/usr/bin/env python3
"""Generate HDC self-learning fixtures for Vivado xsim.

The fixture is intentionally a software schedule, not a new hardware model:
Python keeps the score/top-k state, while the RTL testbench writes queries and
updated prototypes into HDEC VRF and checks HSIM overlap scores class by class.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import hdc_overlap_eval as hdc_eval  # noqa: E402


WORDS_PER_HV = 16


def load_dataset(name: str, data_dir: Path) -> hdc_eval.Dataset:
    if name == "uci_har":
        return hdc_eval.load_uci_har(data_dir)
    if name in ("wisdm_ar", "wisdm_ar_user_split"):
        return hdc_eval.load_wisdm_ar(data_dir)
    if name == "isolet":
        return hdc_eval.load_isolet(data_dir)
    if name == "pamap2":
        return hdc_eval.load_pamap2(data_dir)
    raise ValueError(f"unknown dataset: {name}")


def parse_model(model: str, explicit_topk: int | None) -> tuple[str, str, int]:
    match = re.fullmatch(r"([A-Z])_([a-z]+)_topk([0-9]+)_self_([a-z]+)", model)
    if match:
        _, score_name, topk_text, learn_mode = match.groups()
        score_map = {
            "own": "own",
            "diffavg": "diffavg",
            "diffmax": "diffmax",
        }
        if score_name not in score_map:
            raise ValueError(f"unsupported self-learning model score: {score_name}")
        topk = int(topk_text)
        if explicit_topk is not None and explicit_topk != topk:
            raise ValueError(f"--topk {explicit_topk} disagrees with model topk {topk}")
        return score_map[score_name], learn_mode, topk

    match = re.fullmatch(r"D_topk([0-9]+)_and_raw", model)
    if match:
        topk = int(match.group(1))
        if explicit_topk is not None and explicit_topk != topk:
            raise ValueError(f"--topk {explicit_topk} disagrees with model topk {topk}")
        return "own", "none", topk

    raise ValueError(
        "model must look like K_own_topk256_self_mistake, "
        "L_diffmax_topk256_self_mistake, or D_topk256_and_raw"
    )


def score_seed(
    score_mode: str,
    counts: np.ndarray,
    class_sizes: np.ndarray,
) -> np.ndarray:
    if score_mode == "own":
        sizes = np.maximum(class_sizes.astype(np.float32), 1.0).reshape(-1, 1)
        return counts.astype(np.float32) / sizes
    if score_mode == "diffavg":
        return hdc_eval.discriminative_scores(counts, class_sizes, "avg")
    if score_mode == "diffmax":
        return hdc_eval.discriminative_scores(counts, class_sizes, "max")
    raise ValueError(score_mode)


def bits_to_words(bits: np.ndarray) -> list[int]:
    flat = np.asarray(bits, dtype=np.bool_).reshape(-1)
    if flat.size != WORDS_PER_HV * 64:
        raise ValueError(f"expected 1024 bits, got {flat.size}")
    words: list[int] = []
    for word_idx in range(WORDS_PER_HV):
        value = 0
        base = word_idx * 64
        for bit_idx in range(64):
            if bool(flat[base + bit_idx]):
                value |= 1 << bit_idx
        words.append(value)
    return words


def write_words(path: Path, rows: list[list[int]]) -> None:
    with path.open("w", encoding="ascii", newline="\n") as f:
        for row in rows:
            for word in row:
                f.write(f"{word:016x}\n")


def simulate_schedule(
    hv_test: np.ndarray,
    y_test: np.ndarray,
    scores_initial: np.ndarray,
    topk: int,
    learn_mode: str,
    eta: float,
    runner_eta: float,
    max_samples: int | None,
) -> tuple[np.ndarray, list[dict], int, int]:
    scores = scores_initial.astype(np.float32).copy()
    proto = hdc_eval.prototype_score_topk(scores, topk)
    n_samples = int(hv_test.shape[0] if max_samples is None else min(max_samples, hv_test.shape[0]))
    records: list[dict] = []
    correct = 0
    updates = 0

    for sample_idx in range(n_samples):
        query = hv_test[sample_idx]
        overlap = (query.astype(np.uint16) @ proto.astype(np.uint16).T).astype(np.int32)
        if overlap.shape[0] == 1:
            pred = 0
        else:
            top2 = np.argpartition(overlap, -2)[-2:]
            top2 = top2[np.argsort(overlap[top2])]
            pred = int(top2[1])
        score = int(overlap[pred])
        label = int(y_test[sample_idx])
        correct += int(pred == label)

        update = False
        update_cls = 0
        suppress_cls = 0
        update_proto = np.zeros(query.shape[0], dtype=np.bool_)
        suppress_proto = np.zeros(query.shape[0], dtype=np.bool_)

        if learn_mode == "none":
            pass
        elif learn_mode == "mistake":
            if pred != label:
                update = True
                update_cls = label
                suppress_cls = pred
        elif learn_mode == "corrected":
            update = True
            update_cls = label
            suppress_cls = pred
        else:
            raise ValueError(f"unsupported RTL fixture learning mode: {learn_mode}")

        if update:
            updates += 1
            bit_mask = query
            scores[update_cls, bit_mask] += eta
            if suppress_cls != update_cls:
                scores[suppress_cls, bit_mask] -= runner_eta
            proto[update_cls] = hdc_eval.topk_row(scores[update_cls], topk)
            update_proto = proto[update_cls].copy()
            if suppress_cls != update_cls:
                proto[suppress_cls] = hdc_eval.topk_row(scores[suppress_cls], topk)
                suppress_proto = proto[suppress_cls].copy()
            else:
                suppress_proto = update_proto.copy()

        records.append(
            {
                "label": label,
                "pred": pred,
                "score": score,
                "class_scores": [int(v) for v in overlap.tolist()],
                "update": int(update),
                "update_cls": update_cls,
                "suppress_cls": suppress_cls,
                "query_words": bits_to_words(query),
                "update_words": bits_to_words(update_proto),
                "suppress_words": bits_to_words(suppress_proto),
            }
        )

    return proto, records, correct, updates


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", choices=["uci_har", "wisdm_ar", "wisdm_ar_user_split", "isolet", "pamap2"], required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--data-dir", type=Path, default=Path("reports/hdec/v48_hdc_discriminative_selflearn_2026_06_18/data"))
    ap.add_argument("--dim", type=int, default=1024)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--topk", type=int)
    ap.add_argument("--max-samples", type=int)
    ap.add_argument("--self-eta", type=float, default=0.003)
    ap.add_argument("--self-runner-eta", type=float, default=0.0015)
    args = ap.parse_args(argv)

    if args.dim != 1024:
        raise ValueError("current HDEC RTL fixture supports the 1024-bit HDC datapath")

    score_mode, learn_mode, topk = parse_model(args.model, args.topk)
    dataset = load_dataset(args.dataset, args.data_dir)
    x_train, x_test = hdc_eval.standardize(dataset.x_train, dataset.x_test)
    hv_train, hv_test = hdc_eval.encode_random_projection(x_train, x_test, args.dim, args.seed)
    counts, class_sizes = hdc_eval.build_counts(hv_train, dataset.y_train, len(dataset.labels))
    seed_scores = score_seed(score_mode, counts, class_sizes)
    initial_proto = hdc_eval.prototype_score_topk(seed_scores, topk)
    final_proto, records, correct, updates = simulate_schedule(
        hv_test=hv_test,
        y_test=dataset.y_test,
        scores_initial=seed_scores,
        topk=topk,
        learn_mode=learn_mode,
        eta=args.self_eta,
        runner_eta=args.self_runner_eta,
        max_samples=args.max_samples,
    )

    args.out.mkdir(parents=True, exist_ok=True)
    num_classes = len(dataset.labels)
    num_samples = len(records)

    (args.out / "meta.txt").write_text(
        f"{num_classes} {num_samples} {WORDS_PER_HV} {topk} {args.seed} {correct} {updates}\n",
        encoding="ascii",
        newline="\n",
    )
    write_words(args.out / "initial_proto.mem", [bits_to_words(initial_proto[c]) for c in range(num_classes)])
    write_words(args.out / "final_proto.mem", [bits_to_words(final_proto[c]) for c in range(num_classes)])

    with (args.out / "samples.mem").open("w", encoding="ascii", newline="\n") as f:
        for rec in records:
            fields = [
                str(rec["label"]),
                str(rec["pred"]),
                str(rec["score"]),
                str(rec["update"]),
                str(rec["update_cls"]),
                str(rec["suppress_cls"]),
            ]
            fields.extend(str(score) for score in rec["class_scores"])
            fields.extend(f"{word:016x}" for word in rec["query_words"])
            fields.extend(f"{word:016x}" for word in rec["update_words"])
            fields.extend(f"{word:016x}" for word in rec["suppress_words"])
            f.write(" ".join(fields) + "\n")

    summary = {
        "dataset": dataset.name,
        "model": args.model,
        "score_mode": score_mode,
        "learn_mode": learn_mode,
        "dim": args.dim,
        "seed": args.seed,
        "topk": topk,
        "num_classes": num_classes,
        "num_samples": num_samples,
        "correct": correct,
        "accuracy": correct / num_samples if num_samples else 0.0,
        "updates": updates,
        "class_labels": dataset.labels,
    }
    (args.out / "summary.json").write_text(json.dumps(summary, indent=2), encoding="ascii")
    (args.out / "summary.md").write_text(
        "\n".join(
            [
                "# HDC Self-Learning Fixture",
                "",
                f"- Dataset: `{dataset.name}`",
                f"- Model: `{args.model}`",
                f"- Dimension: `{args.dim}`",
                f"- Seed: `{args.seed}`",
                f"- Top-K: `{topk}`",
                f"- Samples: `{num_samples}`",
                f"- Correct: `{correct}`",
                f"- Accuracy: `{summary['accuracy']:.9f}`",
                f"- Updates: `{updates}`",
                "",
            ]
        ),
        encoding="ascii",
        newline="\n",
    )
    print(f"Wrote fixture to {args.out}")
    print(f"accuracy={summary['accuracy']:.9f} correct={correct}/{num_samples} updates={updates}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
