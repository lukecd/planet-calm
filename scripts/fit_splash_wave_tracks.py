#!/usr/bin/env python3
"""Extract low-order analytic ribbon tracks from the approved splash reference."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from score_splash_waves import NORMALIZED_SIZE, normalize


PALETTE = np.asarray([
    (13, 54, 144),
    (45, 80, 168),
    (81, 107, 175),
    (131, 111, 179),
    (247, 163, 55),
], dtype=np.float64)
COLOR_RIBBONS = {0: [1, 5], 1: [4], 2: [0, 6], 3: [3, 7], 4: [2]}
LAYER_COLOR = [2, 0, 4, 3, 1, 0, 2, 3]
TRACK_COLORS = [
    (125, 158, 255), (35, 108, 255), (255, 211, 68), (210, 145, 255),
    (70, 224, 255), (0, 255, 158), (255, 95, 205), (255, 255, 255),
]


def classify(reference: np.ndarray) -> np.ndarray:
    pixels = reference.astype(np.float64)
    distance = np.sqrt(((pixels[:, :, None, :] - PALETTE[None, None, :, :]) ** 2).sum(axis=3))
    labels = distance.argmin(axis=2).astype(np.int8)
    labels[distance.min(axis=2) > 74] = -1
    height, width = labels.shape
    y, x = np.indices(labels.shape)
    labels[(y < 0.255 * height) | (y > 0.825 * height)] = -2
    labels[(x < 0.32 * width) & (y < 0.34 * height)] = -2
    labels[(((x / width - 0.695) / 0.16) ** 2 + ((y / height - 0.40) / 0.21) ** 2) <= 1] = -2
    # Remove authored foreground actors before tracking the paper ribbons.
    for cx, cy, rx, ry in [
        (0.385, 0.63, 0.105, 0.125),
        (0.585, 0.515, 0.080, 0.095),
        (0.76, 0.70, 0.105, 0.125),
    ]:
        labels[(((x / width - cx) / rx) ** 2 + ((y / height - cy) / ry) ** 2) <= 1] = -2
    return labels


def runs(column: np.ndarray, label: int) -> list[tuple[int, int]]:
    present = column == label
    changes = np.diff(np.pad(present.astype(np.int8), (1, 1)))
    starts = np.flatnonzero(changes == 1)
    ends = np.flatnonzero(changes == -1) - 1
    return [(int(a), int(b)) for a, b in zip(starts, ends) if b - a >= 2]


def assign_tracks(labels: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    height, width = labels.shape
    top = np.full((8, width), np.nan)
    bottom = np.full((8, width), np.nan)
    thresholds = {0: 0.51, 2: 0.56, 3: 0.61}
    for x in range(width):
        column = labels[:, x]
        for color_label, ribbon_ids in COLOR_RIBBONS.items():
            spans = runs(column, color_label)
            if not spans:
                continue
            if len(ribbon_ids) == 1:
                # Prefer the widest run; tiny runs are usually texture noise.
                chosen = max(spans, key=lambda span: span[1] - span[0])
                assigned = [(ribbon_ids[0], chosen)]
            elif len(spans) >= 2:
                assigned = [(ribbon_ids[0], spans[0]), (ribbon_ids[1], spans[-1])]
            else:
                span = spans[0]
                center = (span[0] + span[1]) / (2 * height)
                target = ribbon_ids[0] if center < thresholds[color_label] else ribbon_ids[1]
                assigned = [(target, span)]
            for ribbon_id, (start, end) in assigned:
                top[ribbon_id, x] = start / height
                bottom[ribbon_id, x] = end / height
    return top, bottom


def robust_fit(values: np.ndarray, x: np.ndarray, order: int = 2) -> tuple[np.ndarray, np.ndarray]:
    basis = [np.ones_like(x)]
    for frequency in range(1, order + 1):
        basis += [np.sin(2 * np.pi * frequency * x), np.cos(2 * np.pi * frequency * x)]
    design = np.asarray(basis).T
    keep = np.flatnonzero(np.isfinite(values))
    if keep.size < design.shape[1] * 2:
        return np.zeros(design.shape[1]), np.full_like(x, np.nan)
    for _ in range(7):
        penalty = np.diag([0.0] + [3.5 * ((index + 1) // 2) ** 2 for index in range(1, design.shape[1])])
        coefficients = np.linalg.solve(
            design[keep].T @ design[keep] + penalty,
            design[keep].T @ values[keep],
        )
        fitted = design @ coefficients
        residual = np.abs(values[keep] - fitted[keep])
        median = float(np.median(residual))
        mad = float(np.median(np.abs(residual - median)))
        threshold = max(median + 2.4 * mad, 0.006)
        keep = keep[residual <= threshold]
    return coefficients, fitted


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    reference = normalize(args.reference)
    labels = classify(reference)
    observed_top, observed_bottom = assign_tracks(labels)
    width, height = NORMALIZED_SIZE
    short_side = height
    world_width = short_side * 3.0
    world_left = (width - world_width) / 2
    screen_x = np.arange(width)
    world_x = (screen_x - world_left) / world_width

    output = {"world_x_range": [float(world_x[0]), float(world_x[-1])], "ribbons": []}
    preview = Image.fromarray(reference.copy())
    draw = ImageDraw.Draw(preview)
    for ribbon_id in range(8):
        center_observed = (observed_top[ribbon_id] + observed_bottom[ribbon_id]) / 2
        thickness_observed = observed_bottom[ribbon_id] - observed_top[ribbon_id]
        center_coefficients, center_fit = robust_fit(center_observed, world_x, order=2)
        thickness_coefficients, thickness_fit = robust_fit(thickness_observed, world_x, order=2)
        output["ribbons"].append({
            "id": ribbon_id,
            "color_label": LAYER_COLOR[ribbon_id],
            "center_coefficients": center_coefficients.tolist(),
            "thickness_coefficients": thickness_coefficients.tolist(),
            "center_sample_count": int(np.isfinite(center_observed).sum()),
            "thickness_sample_count": int(np.isfinite(thickness_observed).sum()),
        })
        points = [
            (int(px), int(np.clip(py * height, 0, height - 1)))
            for px, py in zip(screen_x, center_fit)
            if np.isfinite(py)
        ]
        if len(points) > 1:
            draw.line(points, fill=TRACK_COLORS[ribbon_id], width=2)

    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "reference-track-fit.json").write_text(json.dumps(output, indent=2))
    preview.save(args.output / "reference-track-fit.png")


if __name__ == "__main__":
    main()
