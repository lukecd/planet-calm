#!/usr/bin/env python3
"""Fit low-frequency procedural ribbons to the approved splash reference.

The fitter treats the raster as observations, not as production artwork. It
segments the approved palette, assigns vertically separated runs to the rear and
front sheet of each repeated color, and robustly fits independent Fourier fields
for centerline and thickness. The resulting JSON is consumed by the native Swift
generator and can later be phase-animated without changing representation.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from optimize_splash_waves import (
    COLORS,
    FIT_PALETTE,
    FIT_SIZE,
    LAYER_LABELS,
    ReferenceRasterObjective,
    render,
)
from score_splash_waves import normalize


WORLD_WIDTH_IN_SHORT_SIDES = 3.0
RIBBON_ASSIGNMENTS = {
    0: (1, 5),  # deep blue: rear, front
    1: (4,),    # mid blue
    2: (0, 6),  # periwinkle: rear, front
    3: (3, 7),  # lavender: middle, front
    4: (2,),    # warm reveal
}
MINIMUM_VISIBLE_RUN = 2


def contiguous_runs(values: np.ndarray) -> list[np.ndarray]:
    if values.size == 0:
        return []
    breaks = np.flatnonzero(np.diff(values) > 1) + 1
    return [run for run in np.split(values, breaks) if run.size >= MINIMUM_VISIBLE_RUN]


def extract_observations(objective: ReferenceRasterObjective) -> dict[int, list[tuple[float, float, float]]]:
    labels = objective.reference_labels
    height, width = labels.shape
    screen_x = np.arange(width, dtype=np.float64)
    short_side = height
    world_width = short_side * WORLD_WIDTH_IN_SHORT_SIDES
    world_left = (width - world_width) / 2
    world_x = (screen_x - world_left) / world_width
    result: dict[int, list[tuple[float, float, float]]] = {
        index: [] for index in range(len(LAYER_LABELS))
    }

    for column, x in enumerate(world_x):
        for label, ribbon_indices in RIBBON_ASSIGNMENTS.items():
            ys = np.flatnonzero(
                (labels[:, column] == label)
                & objective.evaluation_mask[:, column]
            )
            runs = contiguous_runs(ys)
            if not runs:
                continue
            run_data = [
                (
                    (float(run[0]) + float(run[-1])) / (2 * height),
                    (float(run[-1] - run[0] + 1)) / height,
                )
                for run in runs
            ]
            run_data.sort(key=lambda item: item[0])

            if len(ribbon_indices) == 1:
                # The longest run is most likely the sheet rather than a residual
                # edge or a small unmasked petal fragment.
                center, thickness = max(run_data, key=lambda item: item[1])
                result[ribbon_indices[0]].append((float(x), center, thickness))
                continue

            upper_index, lower_index = ribbon_indices
            upper_candidates = [item for item in run_data if item[0] < 0.60]
            lower_candidates = [item for item in run_data if item[0] >= 0.48]
            if upper_candidates:
                center, thickness = upper_candidates[0]
                result[upper_index].append((float(x), center, thickness))
            if lower_candidates:
                center, thickness = lower_candidates[-1]
                result[lower_index].append((float(x), center, thickness))
    return result


def fit_field(
    observations: list[tuple[float, float, float]],
    value_index: int,
    frequency_grid: np.ndarray,
    harmonic_count: int,
    ridge: float,
) -> list[float]:
    data = np.asarray(observations, dtype=np.float64)
    x = data[:, 0]
    y = data[:, value_index]
    best_error = math.inf
    best_coefficients: np.ndarray | None = None
    best_frequencies: tuple[float, ...] | None = None

    if harmonic_count == 1:
        combinations = [(float(frequency),) for frequency in frequency_grid]
    else:
        combinations = [
            (float(first), float(second))
            for first in frequency_grid
            for second in frequency_grid
            if second > first + 0.35
        ]

    for frequencies in combinations:
        columns = [np.ones_like(x)]
        for frequency in frequencies:
            columns.extend(
                [
                    np.sin(2 * np.pi * frequency * x),
                    np.cos(2 * np.pi * frequency * x),
                ]
            )
        design = np.asarray(columns).T
        keep = np.ones(len(x), dtype=bool)
        coefficients = np.zeros(design.shape[1])
        for _ in range(4):
            lhs = design[keep].T @ design[keep]
            regularizer = np.eye(lhs.shape[0]) * ridge
            regularizer[0, 0] = ridge * 0.02
            coefficients = np.linalg.solve(
                lhs + regularizer,
                design[keep].T @ y[keep],
            )
            residual = np.abs(y - design @ coefficients)
            median = float(np.median(residual[keep]))
            mad = float(np.median(np.abs(residual[keep] - median)))
            keep = residual <= max(median + 2.8 * mad, 0.012)
        error = float(np.mean((y[keep] - design[keep] @ coefficients) ** 2))
        # Prefer broad motion when two fits explain the visible pixels similarly.
        error += 0.000003 * sum(frequency ** 2 for frequency in frequencies)
        if error < best_error:
            best_error = error
            best_coefficients = coefficients
            best_frequencies = frequencies

    assert best_coefficients is not None and best_frequencies is not None
    result = [float(best_coefficients[0])]
    for harmonic_index, frequency in enumerate(best_frequencies):
        sine = float(best_coefficients[1 + 2 * harmonic_index])
        cosine = float(best_coefficients[2 + 2 * harmonic_index])
        amplitude = math.hypot(sine, cosine)
        phase = (math.atan2(cosine, sine) / (2 * math.pi)) % 1
        result.extend([amplitude, frequency, phase])
    return result


def fit_parameters(objective: ReferenceRasterObjective) -> dict:
    observations = extract_observations(objective)
    world_top = 0.610 - 0.52 / 2
    world_observations = {
        index: [
            (x, (center - world_top) / 0.52, thickness / 0.52)
            for x, center, thickness in samples
        ]
        for index, samples in observations.items()
    }
    center_frequencies = np.linspace(0.90, 3.80, 30)
    thickness_frequencies = np.linspace(0.90, 3.40, 22)
    ribbons = []
    for index, samples in world_observations.items():
        if len(samples) < 20:
            raise RuntimeError(f"not enough reference samples for ribbon {index}: {len(samples)}")
        centerline = fit_field(
            samples,
            value_index=1,
            frequency_grid=center_frequencies,
            harmonic_count=2,
            ridge=1.4,
        )
        thickness = fit_field(
            samples,
            value_index=2,
            frequency_grid=thickness_frequencies,
            harmonic_count=2 if index != 2 else 1,
            ridge=2.2,
        )
        # Visible runs are partly occluded by foreground sheets. Restore a modest
        # physical underlap while keeping the yellow reveal intentionally narrow.
        thickness[0] += 0.018 if index == 2 else 0.055
        ribbons.append(
            {
                "attachment": "none",
                "centerline": centerline,
                "thickness": thickness,
            }
        )

    # The two outer sheets use analytic guard edges fitted from the source's robust
    # silhouette. They constrain only the union; interior centerlines remain free.
    # Coefficients start from the proven symmetric envelope and remain optimizer
    # variables rather than raster traces.
    return {
        "envelope_top": [0.1073, 0.0924, 0.0540, -0.0666],
        "envelope_bottom": [0.8886, -0.0334, 0.0467, -0.0673, 0.0602],
        "envelope_shift": [0.0, 0.0, 0.0],
        "ribbons": ribbons,
    }


def diagnostic_image(
    objective: ReferenceRasterObjective,
    observations: dict[int, list[tuple[float, float, float]]],
) -> Image.Image:
    width, height = FIT_SIZE
    image = Image.new("RGB", FIT_SIZE, (10, 17, 36))
    draw = ImageDraw.Draw(image)
    short_side = height
    world_width = short_side * WORLD_WIDTH_IN_SHORT_SIDES
    world_left = (width - world_width) / 2
    for index, samples in observations.items():
        color = COLORS[index]
        for x, center, thickness in samples:
            screen_x = world_left + x * world_width
            draw.line(
                (screen_x, (center - thickness / 2) * height,
                 screen_x, (center + thickness / 2) * height),
                fill=color,
                width=1,
            )
    return image.resize((640, 442), Image.Resampling.NEAREST)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    objective = ReferenceRasterObjective(normalize(args.reference))
    observations = extract_observations(objective)
    parameters = fit_parameters(objective)
    (args.output / "fitted-parameters.json").write_text(
        json.dumps(parameters, indent=2) + "\n"
    )
    Image.fromarray(render(parameters)).save(args.output / "fitted-flat-preview.png")
    diagnostic_image(objective, observations).save(args.output / "observed-runs.png")
    (args.output / "fit-metrics.json").write_text(
        json.dumps(objective.metrics(parameters), indent=2) + "\n"
    )


if __name__ == "__main__":
    main()
