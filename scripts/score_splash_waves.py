#!/usr/bin/env python3
"""Score a rendered Planet Focus splash against the approved wave reference.

The scorer deliberately evaluates visible pixels, not the Swift parameters that
produced them. It normalizes both images to one viewport, isolates the four wave
palette families, compares their occupied silhouette and layer-color structure,
and measures curvature, edge balance, and paper-scale luminance variation.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageOps


PALETTE = np.array(
    [
        (13, 54, 144),   # deep blue
        (45, 80, 168),   # mid blue
        (81, 107, 175),  # periwinkle
        (131, 111, 179), # lavender
    ],
    dtype=np.float32,
)
NORMALIZED_SIZE = (640, 442)
WAVE_BAND = (0.27, 0.84)


def normalize(path: Path) -> np.ndarray:
    image = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    source_ratio = image.width / image.height
    target_ratio = NORMALIZED_SIZE[0] / NORMALIZED_SIZE[1]
    if source_ratio > target_ratio:
        width = round(image.height * target_ratio)
        left = (image.width - width) // 2
        image = image.crop((left, 0, left + width, image.height))
    elif source_ratio < target_ratio:
        height = round(image.width / target_ratio)
        top = (image.height - height) // 2
        image = image.crop((0, top, image.width, top + height))
    return np.asarray(image.resize(NORMALIZED_SIZE, Image.Resampling.LANCZOS), dtype=np.uint8)


def classify(image: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    pixels = image.astype(np.float32)
    distance = np.sqrt(((pixels[:, :, None, :] - PALETTE[None, None, :, :]) ** 2).sum(axis=3))
    labels = distance.argmin(axis=2)
    nearest = distance.min(axis=2)
    y0 = round(image.shape[0] * WAVE_BAND[0])
    y1 = round(image.shape[0] * WAVE_BAND[1])
    band = np.zeros(image.shape[:2], dtype=bool)
    band[y0:y1] = True
    # The threshold deliberately tolerates texture, highlights, and shadowed paper.
    mask = (nearest < 82) & band
    labels = np.where(mask, labels, -1)
    return mask, labels


def fill_missing(values: np.ndarray) -> np.ndarray:
    valid = np.flatnonzero(np.isfinite(values))
    if valid.size == 0:
        return np.zeros_like(values)
    return np.interp(np.arange(values.size), valid, values[valid])


def contours(mask: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    height, width = mask.shape
    top = np.full(width, np.nan)
    bottom = np.full(width, np.nan)
    for x in range(width):
        ys = np.flatnonzero(mask[:, x])
        if ys.size:
            top[x] = ys[0] / height
            bottom[x] = ys[-1] / height
    return fill_missing(top), fill_missing(bottom)


def block_labels(labels: np.ndarray, rows: int = 28, columns: int = 40) -> np.ndarray:
    height, width = labels.shape
    result = np.full((rows, columns), -1, dtype=np.int16)
    for row in range(rows):
        y0, y1 = round(row * height / rows), round((row + 1) * height / rows)
        for column in range(columns):
            x0, x1 = round(column * width / columns), round((column + 1) * width / columns)
            values = labels[y0:y1, x0:x1]
            values = values[values >= 0]
            if values.size:
                counts = np.bincount(values, minlength=len(PALETTE))
                result[row, column] = int(counts.argmax())
    return result


def ranked_boundaries(labels: np.ndarray, count: int = 8) -> np.ndarray:
    """Track the stack's visible color boundaries without assuming ribbon identity.

    Every column can expose a different number of boundaries because ribbons overlap.
    Ranking and resampling those transitions produces a stable description of whether
    the visible layers rise and fall together—the defect that is most obvious in a
    narrow portrait crop.
    """
    height, width = labels.shape
    tracks = np.full((count, width), np.nan)
    for x in range(width):
        column = labels[:, x]
        changes = np.flatnonzero(column[1:] != column[:-1]) + 1
        boundaries: list[int] = []
        for y in changes:
            if column[y] < 0 and column[y - 1] < 0:
                continue
            if not boundaries or y - boundaries[-1] > 3:
                boundaries.append(int(y))
        if len(boundaries) >= 2:
            source = np.arange(len(boundaries))
            target = np.linspace(0, len(boundaries) - 1, count)
            tracks[:, x] = np.interp(target, source, np.asarray(boundaries) / height)

    kernel_width = 31
    kernel = np.ones(kernel_width) / kernel_width
    padding = kernel_width // 2
    for index in range(count):
        values = fill_missing(tracks[index])
        tracks[index] = np.convolve(
            np.pad(values, (padding, padding), mode="edge"),
            kernel,
            mode="valid",
        )
    return tracks


def phase_synchrony(labels: np.ndarray, crop: tuple[float, float] = (0, 1)) -> float:
    tracks = ranked_boundaries(labels)
    width = tracks.shape[1]
    left = round(width * crop[0])
    right = round(width * crop[1])
    slopes = np.gradient(tracks[:, left:right], axis=1)
    scale = max(float(np.quantile(np.abs(slopes), 0.60)), 0.0001)
    signed_motion = np.tanh(slopes / scale)
    return float(np.mean(np.abs(signed_motion.mean(axis=0))))


def high_frequency_energy(image: np.ndarray, mask: np.ndarray) -> float:
    luminance = image.astype(np.float32).mean(axis=2)
    # Four-neighbour residual keeps the metric about face grain, not broad lighting.
    residual = np.abs(luminance[:, 1:] - luminance[:, :-1])
    valid = mask[:, 1:] & mask[:, :-1]
    return float(residual[valid].mean()) if valid.any() else 0.0


def curvature_signature(top: np.ndarray, bottom: np.ndarray) -> tuple[float, float]:
    def signature(values: np.ndarray) -> tuple[float, float]:
        second = np.diff(values, n=2)
        third = np.diff(values, n=3)
        return float(np.mean(np.abs(second))), float(np.quantile(np.abs(third), 0.99))

    top_mean, top_spike = signature(top)
    bottom_mean, bottom_spike = signature(bottom)
    return (top_mean + bottom_mean) / 2, max(top_spike, bottom_spike)


def closeness(error: float, scale: float) -> float:
    return math.exp(-error / max(scale, 1e-9))


def score(reference: np.ndarray, candidate: np.ndarray) -> dict[str, float]:
    reference_mask, reference_labels = classify(reference)
    candidate_mask, candidate_labels = classify(candidate)
    reference_top, reference_bottom = contours(reference_mask)
    candidate_top, candidate_bottom = contours(candidate_mask)

    silhouette_error = float(
        (np.abs(reference_top - candidate_top).mean()
        + np.abs(reference_bottom - candidate_bottom).mean()) / 2
    )
    intersection = np.logical_and(reference_mask, candidate_mask).sum()
    union = np.logical_or(reference_mask, candidate_mask).sum()
    mask_iou = float(intersection / union) if union else 0.0

    reference_blocks = block_labels(reference_labels)
    candidate_blocks = block_labels(candidate_labels)
    relevant = (reference_blocks >= 0) | (candidate_blocks >= 0)
    color_similarity = float(
        (reference_blocks[relevant] == candidate_blocks[relevant]).mean()
    ) if relevant.any() else 0.0

    reference_curve, reference_spike = curvature_signature(reference_top, reference_bottom)
    candidate_curve, candidate_spike = curvature_signature(candidate_top, candidate_bottom)
    curvature_similarity = closeness(abs(candidate_curve - reference_curve), max(reference_curve, 0.00002))
    spike_similarity = closeness(abs(candidate_spike - reference_spike), max(reference_spike, 0.00003))

    reference_texture = high_frequency_energy(reference, reference_mask)
    candidate_texture = high_frequency_energy(candidate, candidate_mask)
    texture_similarity = closeness(
        abs(candidate_texture - reference_texture),
        max(reference_texture * 0.55, 0.25),
    )

    edge_height_error = abs(
        (candidate_bottom[0] - candidate_top[0])
        - (candidate_bottom[-1] - candidate_top[-1])
    )
    edge_balance = closeness(edge_height_error, 0.008)

    reference_synchrony = phase_synchrony(reference_labels)
    candidate_synchrony = phase_synchrony(candidate_labels)
    # This center crop approximates the portion of the same world visible on iPhone.
    reference_portrait_synchrony = phase_synchrony(reference_labels, (0.143, 0.857))
    candidate_portrait_synchrony = phase_synchrony(candidate_labels, (0.143, 0.857))
    synchrony_error = (
        abs(candidate_synchrony - reference_synchrony)
        + abs(candidate_portrait_synchrony - reference_portrait_synchrony)
    ) / 2
    phase_structure_similarity = closeness(synchrony_error, 0.12)

    total = 100 * (
        0.27 * closeness(silhouette_error, 0.075)
        + 0.22 * mask_iou
        + 0.16 * color_similarity
        + 0.08 * curvature_similarity
        + 0.06 * spike_similarity
        + 0.06 * texture_similarity
        + 0.05 * edge_balance
        + 0.10 * phase_structure_similarity
    )
    return {
        "total": round(total, 2),
        "silhouette_similarity": round(100 * closeness(silhouette_error, 0.075), 2),
        "mask_iou": round(100 * mask_iou, 2),
        "layer_color_similarity": round(100 * color_similarity, 2),
        "curvature_similarity": round(100 * curvature_similarity, 2),
        "curvature_spike_similarity": round(100 * spike_similarity, 2),
        "phase_structure_similarity": round(100 * phase_structure_similarity, 2),
        "reference_phase_synchrony": round(reference_synchrony, 4),
        "candidate_phase_synchrony": round(candidate_synchrony, 4),
        "reference_portrait_synchrony": round(reference_portrait_synchrony, 4),
        "candidate_portrait_synchrony": round(candidate_portrait_synchrony, 4),
        "paper_texture_similarity": round(100 * texture_similarity, 2),
        "edge_balance": round(100 * edge_balance, 2),
        "edge_height_error": round(edge_height_error, 6),
        "reference_texture_energy": round(reference_texture, 4),
        "candidate_texture_energy": round(candidate_texture, 4),
    }


def comparison_image(reference: np.ndarray, candidate: np.ndarray, metrics: dict[str, float]) -> Image.Image:
    reference_image = Image.fromarray(reference)
    candidate_image = Image.fromarray(candidate)
    difference = Image.fromarray(np.abs(reference.astype(np.int16) - candidate.astype(np.int16)).astype(np.uint8))
    canvas = Image.new("RGB", (NORMALIZED_SIZE[0] * 3, NORMALIZED_SIZE[1] + 54), (10, 17, 36))
    canvas.paste(reference_image, (0, 54))
    canvas.paste(candidate_image, (NORMALIZED_SIZE[0], 54))
    canvas.paste(difference, (NORMALIZED_SIZE[0] * 2, 54))
    draw = ImageDraw.Draw(canvas)
    draw.text((14, 16), "REFERENCE", fill=(174, 199, 251))
    draw.text((NORMALIZED_SIZE[0] + 14, 16), f"CANDIDATE  SCORE {metrics['total']:.2f}", fill=(174, 199, 251))
    draw.text((NORMALIZED_SIZE[0] * 2 + 14, 16), "PIXEL DIFFERENCE", fill=(174, 199, 251))
    return canvas


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--comparison", type=Path)
    parser.add_argument("--json", type=Path)
    args = parser.parse_args()

    reference = normalize(args.reference)
    candidate = normalize(args.candidate)
    metrics = score(reference, candidate)
    payload = json.dumps(metrics, indent=2, sort_keys=True)
    print(payload)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(payload + "\n")
    if args.comparison:
        args.comparison.parent.mkdir(parents=True, exist_ok=True)
        comparison_image(reference, candidate, metrics).save(args.comparison)


if __name__ == "__main__":
    main()
