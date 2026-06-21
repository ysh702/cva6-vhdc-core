#!/usr/bin/env python3
"""Evaluate XOR-distance HDC vs AND-overlap HDC software models.

This script intentionally uses only numpy/pandas from the bundled Codex runtime.
It keeps downloaded data and reports under the repo-provided output directory.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import shutil
import sys
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np


UCI_HAR_URL = (
    "https://archive.ics.uci.edu/ml/machine-learning-databases/"
    "00240/UCI%20HAR%20Dataset.zip"
)
WISDM_AR_URL = "https://www.cis.fordham.edu/wisdm/includes/datasets/latest/WISDM_ar_latest.tar.gz"
ISOLET_ARFF_URL = "https://openml.org/data/v1/download/52405/isolet.arff"
PAMAP2_URL = "https://archive.ics.uci.edu/ml/machine-learning-databases/00231/PAMAP2_Dataset.zip"


@dataclass(frozen=True)
class Dataset:
    name: str
    x_train: np.ndarray
    y_train: np.ndarray
    x_test: np.ndarray
    y_test: np.ndarray
    labels: list[str]


def download_file(url: str, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and dst.stat().st_size > 0:
        return
    tmp = dst.with_suffix(dst.suffix + ".tmp")
    with urllib.request.urlopen(url, timeout=120) as resp, tmp.open("wb") as f:
        shutil.copyfileobj(resp, f)
    tmp.replace(dst)


def load_uci_har(data_dir: Path) -> Dataset:
    zip_path = data_dir / "uci_har" / "UCI_HAR_Dataset.zip"
    extract_dir = data_dir / "uci_har" / "UCI HAR Dataset"
    download_file(UCI_HAR_URL, zip_path)
    if not extract_dir.exists():
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(zip_path.parent)

    def load_matrix(path: Path) -> np.ndarray:
        return np.loadtxt(path, dtype=np.float32)

    def load_labels(path: Path) -> np.ndarray:
        return np.loadtxt(path, dtype=np.int64) - 1

    labels = []
    with (extract_dir / "activity_labels.txt").open("r", encoding="utf-8") as f:
        for line in f:
            _, name = line.strip().split(maxsplit=1)
            labels.append(name)

    return Dataset(
        name="uci_har",
        x_train=load_matrix(extract_dir / "train" / "X_train.txt"),
        y_train=load_labels(extract_dir / "train" / "y_train.txt"),
        x_test=load_matrix(extract_dir / "test" / "X_test.txt"),
        y_test=load_labels(extract_dir / "test" / "y_test.txt"),
        labels=labels,
    )


def load_wisdm_ar(data_dir: Path) -> Dataset:
    import tarfile

    tar_path = data_dir / "wisdm" / "WISDM_ar_latest.tar.gz"
    extract_dir = data_dir / "wisdm" / "WISDM_ar_v1.1"
    download_file(WISDM_AR_URL, tar_path)
    if not extract_dir.exists():
        with tarfile.open(tar_path, "r:gz") as tf:
            tf.extractall(tar_path.parent)

    arff_path = extract_dir / "WISDM_ar_v1.1_transformed.arff"
    labels_order = ["Walking", "Jogging", "Upstairs", "Downstairs", "Sitting", "Standing"]
    label_to_id = {name: idx for idx, name in enumerate(labels_order)}
    rows: list[list[float]] = []
    users: list[int] = []
    labels: list[int] = []
    in_data = False
    with arff_path.open("r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line:
                continue
            if not in_data:
                if line.lower() == "@data":
                    in_data = True
                continue
            parts = [p.strip().strip('"') for p in line.split(",")]
            if len(parts) < 4:
                continue
            users.append(int(parts[1]))
            feat = []
            for value in parts[2:-1]:
                feat.append(float("nan") if value == "?" else float(value))
            rows.append(feat)
            labels.append(label_to_id[parts[-1].strip()])

    x = np.asarray(rows, dtype=np.float32)
    y = np.asarray(labels, dtype=np.int64)
    users_arr = np.asarray(users, dtype=np.int64)

    # User-disjoint split: deterministic and closer to an end-device deployment
    # where a model sees new users at inference time.
    unique_users = np.array(sorted(np.unique(users_arr)))
    rng = np.random.default_rng(20260618)
    rng.shuffle(unique_users)
    n_train_users = max(1, int(math.ceil(unique_users.size * 0.7)))
    train_users = set(int(u) for u in unique_users[:n_train_users])
    train_mask = np.array([int(u) in train_users for u in users_arr], dtype=bool)

    x_train = x[train_mask]
    y_train = y[train_mask]
    x_test = x[~train_mask]
    y_test = y[~train_mask]

    # Impute occasional missing ARFF values using train means only.
    means = np.nanmean(x_train, axis=0, keepdims=True)
    means = np.where(np.isfinite(means), means, 0.0).astype(np.float32)
    x_train = np.where(np.isnan(x_train), means, x_train).astype(np.float32)
    x_test = np.where(np.isnan(x_test), means, x_test).astype(np.float32)

    return Dataset(
        name="wisdm_ar_user_split",
        x_train=x_train,
        y_train=y_train,
        x_test=x_test,
        y_test=y_test,
        labels=labels_order,
    )


def load_isolet(data_dir: Path) -> Dataset:
    arff_path = data_dir / "isolet" / "isolet_openml.arff"
    download_file(ISOLET_ARFF_URL, arff_path)
    rows: list[list[float]] = []
    labels_raw: list[str] = []
    in_data = False
    with arff_path.open("r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("%"):
                continue
            if not in_data:
                if line.lower() == "@data":
                    in_data = True
                continue
            parts = [p.strip().strip("'\"") for p in line.split(",")]
            rows.append([float(v) for v in parts[:-1]])
            labels_raw.append(parts[-1])

    x = np.asarray(rows, dtype=np.float32)
    unique = sorted(set(labels_raw), key=lambda v: int(v) if v.isdigit() else v)
    label_to_id = {label: idx for idx, label in enumerate(unique)}
    y = np.asarray([label_to_id[v] for v in labels_raw], dtype=np.int64)

    # OpenML preserves the common UCI ordering: isolet1-4 for train and
    # isolet5 for test.
    train_n = 6238
    labels = [chr(ord("A") + i) for i in range(26)]
    return Dataset(
        name="isolet",
        x_train=x[:train_n],
        y_train=y[:train_n],
        x_test=x[train_n:],
        y_test=y[train_n:],
        labels=labels,
    )


def load_pamap2(data_dir: Path) -> Dataset:
    zip_path = data_dir / "pamap2" / "PAMAP2_Dataset.zip"
    extract_dir = data_dir / "pamap2" / "PAMAP2_Dataset"
    download_file(PAMAP2_URL, zip_path)
    if not extract_dir.exists():
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(zip_path.parent)

    protocol_dir = extract_dir / "Protocol"
    activity_ids = [1, 2, 3, 4, 5, 6, 7, 12, 13, 16, 17, 24]
    labels = [
        "lying",
        "sitting",
        "standing",
        "walking",
        "running",
        "cycling",
        "nordic_walking",
        "ascending_stairs",
        "descending_stairs",
        "vacuum_cleaning",
        "ironing",
        "rope_jumping",
    ]
    activity_to_id = {act: idx for idx, act in enumerate(activity_ids)}
    rows_by_subject: dict[int, tuple[np.ndarray, np.ndarray]] = {}
    use_cols = [2] + list(range(4, 17)) + list(range(21, 34)) + list(range(38, 51))
    for path in sorted(protocol_dir.glob("subject*.dat")):
        subject = int(path.stem.replace("subject", ""))
        raw = np.loadtxt(path, dtype=np.float32)
        act = raw[:, 1].astype(np.int64)
        mask = np.isin(act, activity_ids)
        if not np.any(mask):
            continue
        x = raw[mask][:, use_cols].astype(np.float32)
        y_raw = act[mask]
        y = np.asarray([activity_to_id[int(v)] for v in y_raw], dtype=np.int64)
        rows_by_subject[subject] = (x, y)

    train_subjects = [101, 102, 103, 104, 105, 106, 107]
    test_subjects = [108]

    # 1.28-second windows with 50% overlap at the original 100 Hz sampling rate.
    # Each window emits mean and std; windows with mixed labels use the majority
    # activity if it covers at least 60% of the window.
    def featurize(subjects: list[int]) -> tuple[np.ndarray, np.ndarray]:
        feats: list[np.ndarray] = []
        ys: list[int] = []
        window = 128
        step = 64
        for subject in subjects:
            if subject not in rows_by_subject:
                continue
            x, y = rows_by_subject[subject]
            means = np.nanmean(x, axis=0, keepdims=True)
            means = np.where(np.isfinite(means), means, 0.0).astype(np.float32)
            x = np.where(np.isnan(x), means, x).astype(np.float32)
            for start in range(0, max(0, x.shape[0] - window + 1), step):
                stop = start + window
                wy = y[start:stop]
                hist = np.bincount(wy, minlength=len(labels))
                cls = int(hist.argmax())
                if hist[cls] < int(window * 0.6):
                    continue
                wx = x[start:stop]
                feats.append(np.concatenate([wx.mean(axis=0), wx.std(axis=0)]).astype(np.float32))
                ys.append(cls)
        return np.vstack(feats).astype(np.float32), np.asarray(ys, dtype=np.int64)

    x_train, y_train = featurize(train_subjects)
    x_test, y_test = featurize(test_subjects)
    return Dataset(
        name="pamap2_subject8",
        x_train=x_train,
        y_train=y_train,
        x_test=x_test,
        y_test=y_test,
        labels=labels,
    )


def standardize(x_train: np.ndarray, x_test: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    mean = x_train.mean(axis=0, keepdims=True)
    std = x_train.std(axis=0, keepdims=True)
    std = np.where(std < 1e-6, 1.0, std)
    return ((x_train - mean) / std).astype(np.float32), ((x_test - mean) / std).astype(np.float32)


def encode_random_projection(
    x_train: np.ndarray,
    x_test: np.ndarray,
    dim: int,
    seed: int,
    chunk_rows: int = 1024,
) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    proj = rng.standard_normal((x_train.shape[1], dim)).astype(np.float32)

    def encode(x: np.ndarray) -> np.ndarray:
        out = np.empty((x.shape[0], dim), dtype=bool)
        for start in range(0, x.shape[0], chunk_rows):
            stop = min(start + chunk_rows, x.shape[0])
            out[start:stop] = (x[start:stop] @ proj) >= 0
        return out

    return encode(x_train), encode(x_test)


def build_counts(hv: np.ndarray, y: np.ndarray, n_classes: int) -> tuple[np.ndarray, np.ndarray]:
    counts = np.zeros((n_classes, hv.shape[1]), dtype=np.uint16)
    class_sizes = np.zeros(n_classes, dtype=np.int64)
    hv_u16 = hv.astype(np.uint16)
    for cls in range(n_classes):
        mask = y == cls
        class_sizes[cls] = int(mask.sum())
        counts[cls] = hv_u16[mask].sum(axis=0, dtype=np.uint32)
    return counts, class_sizes


def prototype_majority(counts: np.ndarray, class_sizes: np.ndarray) -> np.ndarray:
    threshold = ((class_sizes + 1) // 2).reshape(-1, 1)
    return counts >= threshold


def prototype_nonzero(counts: np.ndarray) -> np.ndarray:
    return counts > 0


def prototype_topk(counts: np.ndarray, k: int) -> np.ndarray:
    n_classes, dim = counts.shape
    proto = np.zeros((n_classes, dim), dtype=bool)
    k = min(max(int(k), 1), dim)
    for cls in range(n_classes):
        idx = np.argpartition(counts[cls], dim - k)[dim - k :]
        proto[cls, idx] = True
    return proto


def prototype_score_topk(scores: np.ndarray, k: int) -> np.ndarray:
    n_classes, dim = scores.shape
    proto = np.zeros((n_classes, dim), dtype=bool)
    k = min(max(int(k), 1), dim)
    for cls in range(n_classes):
        idx = np.argpartition(scores[cls], dim - k)[dim - k :]
        proto[cls, idx] = True
    return proto


def discriminative_scores(
    counts: np.ndarray,
    class_sizes: np.ndarray,
    mode: str,
) -> np.ndarray:
    """Bit score: frequent in this class, rare in other classes."""
    sizes = np.maximum(class_sizes.astype(np.float32), 1.0).reshape(-1, 1)
    freq = counts.astype(np.float32) / sizes
    if mode == "avg":
        total = freq.sum(axis=0, keepdims=True)
        denom = max(freq.shape[0] - 1, 1)
        other = (total - freq) / float(denom)
    elif mode == "max":
        other = np.empty_like(freq)
        for cls in range(freq.shape[0]):
            if freq.shape[0] == 1:
                other[cls] = 0.0
            else:
                other[cls] = np.delete(freq, cls, axis=0).max(axis=0)
    else:
        raise ValueError(f"unknown discriminative mode: {mode}")
    return freq - other


def topk_row(scores: np.ndarray, k: int) -> np.ndarray:
    dim = scores.shape[0]
    k = min(max(int(k), 1), dim)
    row = np.zeros(dim, dtype=bool)
    idx = np.argpartition(scores, dim - k)[dim - k :]
    row[idx] = True
    return row


def overlaps(hv: np.ndarray, proto: np.ndarray) -> np.ndarray:
    return hv.astype(np.uint16) @ proto.astype(np.uint16).T


def predict_xor_distance(hv: np.ndarray, proto: np.ndarray) -> np.ndarray:
    ov = overlaps(hv, proto).astype(np.int32)
    q_weight = hv.sum(axis=1, dtype=np.int32).reshape(-1, 1)
    p_weight = proto.sum(axis=1, dtype=np.int32).reshape(1, -1)
    dist = q_weight + p_weight - 2 * ov
    return dist.argmin(axis=1)


def predict_and_compensated(hv: np.ndarray, proto: np.ndarray) -> np.ndarray:
    ov = overlaps(hv, proto).astype(np.int32)
    p_weight = proto.sum(axis=1, dtype=np.int32).reshape(1, -1)
    score = 2 * ov - p_weight
    return score.argmax(axis=1)


def predict_and_raw(hv: np.ndarray, proto: np.ndarray) -> np.ndarray:
    return overlaps(hv, proto).argmax(axis=1)


def confusion_matrix(y_true: np.ndarray, y_pred: np.ndarray, n_classes: int) -> list[list[int]]:
    cm = np.zeros((n_classes, n_classes), dtype=np.int64)
    for t, p in zip(y_true, y_pred):
        cm[int(t), int(p)] += 1
    return cm.tolist()


def evaluate_model(
    name: str,
    hv_test: np.ndarray,
    y_test: np.ndarray,
    proto: np.ndarray,
    predictor,
    labels: list[str],
) -> dict:
    y_pred = predictor(hv_test, proto)
    acc = float((y_pred == y_test).mean())
    weights = proto.sum(axis=1, dtype=np.int32)
    return {
        "model": name,
        "accuracy": acc,
        "prototype_weight_min": int(weights.min()),
        "prototype_weight_max": int(weights.max()),
        "prototype_weight_mean": float(weights.mean()),
        "prototype_weights": {labels[i]: int(weights[i]) for i in range(len(labels))},
        "confusion": confusion_matrix(y_test, y_pred, len(labels)),
    }


def evaluate_self_learning(
    name: str,
    hv_test: np.ndarray,
    y_test: np.ndarray,
    score_seed: np.ndarray,
    k: int,
    labels: list[str],
    mode: str,
    margin_ratio: float,
    eta: float,
    runner_eta: float,
) -> dict:
    """Online edge update after each prediction; the prediction itself is pre-update.

    mode="pseudo" uses only high-confidence predicted labels.
    mode="corrected" simulates user/device feedback with true labels available after
    every prediction, giving an upper bound for lightweight supervised adaptation.
    mode="mistake" updates only when the predicted label is corrected.
    """
    scores = score_seed.astype(np.float32).copy()
    proto = prototype_score_topk(scores, k)
    y_pred = np.empty(y_test.shape[0], dtype=np.int64)
    margin_abs = max(1, int(round(k * margin_ratio)))
    updates = 0
    wrong_pseudo_updates = 0
    changed_bits = 0

    for i in range(hv_test.shape[0]):
        ov = (hv_test[i].astype(np.uint16) @ proto.astype(np.uint16).T).astype(np.int32)
        if ov.shape[0] == 1:
            pred = 0
            runner = 0
            margin = int(ov[0])
        else:
            top2 = np.argpartition(ov, -2)[-2:]
            top2 = top2[np.argsort(ov[top2])]
            runner = int(top2[0])
            pred = int(top2[1])
            margin = int(ov[pred] - ov[runner])
        y_pred[i] = pred

        bit_mask = hv_test[i]
        old_pred_proto = proto[pred].copy()
        old_runner_proto = proto[runner].copy()

        if mode == "pseudo":
            if margin < margin_abs:
                continue
            update_cls = pred
            suppress_cls = runner
            if pred != int(y_test[i]):
                wrong_pseudo_updates += 1
        elif mode == "corrected":
            update_cls = int(y_test[i])
            suppress_cls = pred if pred != update_cls else runner
        elif mode == "mistake":
            if pred == int(y_test[i]):
                continue
            update_cls = int(y_test[i])
            suppress_cls = pred
        else:
            raise ValueError(f"unknown self-learning mode: {mode}")

        updates += 1
        scores[update_cls, bit_mask] += eta
        if suppress_cls != update_cls:
            scores[suppress_cls, bit_mask] -= runner_eta
        proto[update_cls] = topk_row(scores[update_cls], k)
        if suppress_cls != update_cls:
            proto[suppress_cls] = topk_row(scores[suppress_cls], k)
        changed_bits += int(np.count_nonzero(proto[pred] != old_pred_proto))
        if runner != pred:
            changed_bits += int(np.count_nonzero(proto[runner] != old_runner_proto))

    acc = float((y_pred == y_test).mean())
    weights = proto.sum(axis=1, dtype=np.int32)
    return {
        "model": name,
        "accuracy": acc,
        "prototype_weight_min": int(weights.min()),
        "prototype_weight_max": int(weights.max()),
        "prototype_weight_mean": float(weights.mean()),
        "prototype_weights": {labels[i]: int(weights[i]) for i in range(len(labels))},
        "confusion": confusion_matrix(y_test, y_pred, len(labels)),
        "updates": int(updates),
        "update_rate": float(updates / max(1, y_test.shape[0])),
        "wrong_pseudo_updates": int(wrong_pseudo_updates),
        "wrong_pseudo_update_rate": float(wrong_pseudo_updates / max(1, updates)),
        "changed_bits": int(changed_bits),
    }


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = [
        "model",
        "accuracy",
        "prototype_weight_min",
        "prototype_weight_max",
        "prototype_weight_mean",
        "updates",
        "update_rate",
        "wrong_pseudo_updates",
        "wrong_pseudo_update_rate",
        "changed_bits",
    ]
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, "") for k in fields})


def write_markdown(
    path: Path,
    dataset: Dataset,
    dim: int,
    seed: int,
    topks: list[int],
    rows: list[dict],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# V48 HDC AND-Overlap Algorithm Evaluation",
        "",
        f"Dataset: `{dataset.name}`",
        "",
        f"- Train samples: `{dataset.x_train.shape[0]}`",
        f"- Test samples: `{dataset.x_test.shape[0]}`",
        f"- Raw features: `{dataset.x_train.shape[1]}`",
        f"- HDC dimension: `{dim}`",
        f"- Random seed: `{seed}`",
        f"- Top-K scan: `{', '.join(str(k) for k in topks)}`",
        "",
        "## Models",
        "",
        "| Model | Meaning |",
        "| --- | --- |",
        "| `A_majority_xor` | Original-style majority prototype + XOR Hamming distance |",
        "| `B_nonzero_xor` | Current low-area fixed-nonzero prototype + XOR Hamming distance |",
        "| `C_majority_and_compensated` | Conservative AND overlap, mathematically equivalent to XOR ranking |",
        "| `D_topk*_and_raw` | Innovative fixed-density prototype + raw AND overlap |",
        "| `E_majority_and_raw_mismatch` | Deliberate mismatch: old prototype + raw AND overlap |",
        "| `F_diffavg_topk*_and_raw` | Class-differential fixed-density prototype using this-class minus other-class average |",
        "| `G_diffmax_topk*_and_raw` | Class-differential fixed-density prototype using this-class minus strongest competing class |",
        "| `H_diffavg_topk*_self_pseudo` | Label-free confidence-gated edge self-learning from the diff-average prototype |",
        "| `I_diffavg_topk*_self_corrected` | User-corrected edge self-learning upper-bound from the diff-average prototype |",
        "| `J_diffavg_topk*_self_mistake` | User-corrected edge self-learning that updates only after a wrong prediction |",
        "| `K_own_topk*_self_mistake` | Mistake-only edge self-learning from the plain top-K prototype |",
        "| `L_diffmax_topk*_self_mistake` | Mistake-only edge self-learning from the strongest-competitor differential prototype |",
        "",
        "## Results",
        "",
        "| Model | Accuracy | Prototype 1s min | Prototype 1s max | Prototype 1s mean | Updates | Wrong pseudo update rate |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in rows:
        lines.append(
            f"| `{row['model']}` | {row['accuracy']:.6f} | "
            f"{row['prototype_weight_min']} | {row['prototype_weight_max']} | "
            f"{row['prototype_weight_mean']:.2f} | "
            f"{row.get('updates', '')} | "
            f"{row.get('wrong_pseudo_update_rate', '')} |"
        )
    lines += [
        "",
        "## Early Reading",
        "",
        "- `C_majority_and_compensated` should match `A_majority_xor` except for ties, because both implement the same Hamming-distance ranking in different algebraic forms.",
        "- `E_majority_and_raw_mismatch` estimates the risk of changing only inference. If it drops, the training and inference metric are mismatched.",
        "- `D_topk*_and_raw` is the real innovation path: training generates fixed-density prototypes, and inference uses raw AND overlap.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", choices=["uci_har", "wisdm_ar", "isolet", "pamap2"], default="uci_har")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--dim", type=int, default=1024)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--topk", type=int, nargs="*", default=[128, 256, 512])
    ap.add_argument("--self-margin-ratio", type=float, default=0.05)
    ap.add_argument("--self-eta", type=float, default=0.003)
    ap.add_argument("--self-runner-eta", type=float, default=0.0015)
    args = ap.parse_args(argv)

    data_dir = args.out / "data"
    if args.dataset == "uci_har":
        dataset = load_uci_har(data_dir)
    elif args.dataset == "wisdm_ar":
        dataset = load_wisdm_ar(data_dir)
    elif args.dataset == "isolet":
        dataset = load_isolet(data_dir)
    elif args.dataset == "pamap2":
        dataset = load_pamap2(data_dir)
    else:
        raise ValueError(args.dataset)

    x_train, x_test = standardize(dataset.x_train, dataset.x_test)
    hv_train, hv_test = encode_random_projection(x_train, x_test, args.dim, args.seed)
    counts, class_sizes = build_counts(hv_train, dataset.y_train, len(dataset.labels))

    majority = prototype_majority(counts, class_sizes)
    nonzero = prototype_nonzero(counts)
    own_scores = counts.astype(np.float32) / np.maximum(class_sizes.astype(np.float32), 1.0).reshape(-1, 1)
    diffavg_scores = discriminative_scores(counts, class_sizes, "avg")
    diffmax_scores = discriminative_scores(counts, class_sizes, "max")

    rows: list[dict] = []
    rows.append(evaluate_model("A_majority_xor", hv_test, dataset.y_test, majority, predict_xor_distance, dataset.labels))
    rows.append(evaluate_model("B_nonzero_xor", hv_test, dataset.y_test, nonzero, predict_xor_distance, dataset.labels))
    rows.append(evaluate_model("C_majority_and_compensated", hv_test, dataset.y_test, majority, predict_and_compensated, dataset.labels))
    for k in args.topk:
        topk_proto = prototype_topk(counts, k)
        rows.append(evaluate_model(f"D_topk{k}_and_raw", hv_test, dataset.y_test, topk_proto, predict_and_raw, dataset.labels))
        diffavg_proto = prototype_score_topk(diffavg_scores, k)
        diffmax_proto = prototype_score_topk(diffmax_scores, k)
        rows.append(evaluate_model(f"F_diffavg_topk{k}_and_raw", hv_test, dataset.y_test, diffavg_proto, predict_and_raw, dataset.labels))
        rows.append(evaluate_model(f"G_diffmax_topk{k}_and_raw", hv_test, dataset.y_test, diffmax_proto, predict_and_raw, dataset.labels))
        rows.append(
            evaluate_self_learning(
                f"H_diffavg_topk{k}_self_pseudo",
                hv_test,
                dataset.y_test,
                diffavg_scores,
                k,
                dataset.labels,
                "pseudo",
                args.self_margin_ratio,
                args.self_eta,
                args.self_runner_eta,
            )
        )
        rows.append(
            evaluate_self_learning(
                f"I_diffavg_topk{k}_self_corrected",
                hv_test,
                dataset.y_test,
                diffavg_scores,
                k,
                dataset.labels,
                "corrected",
                args.self_margin_ratio,
                args.self_eta,
                args.self_runner_eta,
            )
        )
        rows.append(
            evaluate_self_learning(
                f"J_diffavg_topk{k}_self_mistake",
                hv_test,
                dataset.y_test,
                diffavg_scores,
                k,
                dataset.labels,
                "mistake",
                args.self_margin_ratio,
                args.self_eta,
                args.self_runner_eta,
            )
        )
        rows.append(
            evaluate_self_learning(
                f"K_own_topk{k}_self_mistake",
                hv_test,
                dataset.y_test,
                own_scores,
                k,
                dataset.labels,
                "mistake",
                args.self_margin_ratio,
                args.self_eta,
                args.self_runner_eta,
            )
        )
        rows.append(
            evaluate_self_learning(
                f"L_diffmax_topk{k}_self_mistake",
                hv_test,
                dataset.y_test,
                diffmax_scores,
                k,
                dataset.labels,
                "mistake",
                args.self_margin_ratio,
                args.self_eta,
                args.self_runner_eta,
            )
        )
    rows.append(evaluate_model("E_majority_and_raw_mismatch", hv_test, dataset.y_test, majority, predict_and_raw, dataset.labels))

    result_dir = args.out / f"{dataset.name}_D{args.dim}_seed{args.seed}"
    result_dir.mkdir(parents=True, exist_ok=True)
    write_csv(result_dir / "summary.csv", rows)
    write_markdown(result_dir / "summary.md", dataset, args.dim, args.seed, args.topk, rows)
    (result_dir / "details.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")

    print(f"Wrote {result_dir}")
    for row in rows:
        print(
            f"{row['model']:32s} acc={row['accuracy']:.6f} "
            f"w=[{row['prototype_weight_min']},{row['prototype_weight_max']}] "
            f"mean={row['prototype_weight_mean']:.2f} "
            f"updates={row.get('updates', '')}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
