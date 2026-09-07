#!/usr/bin/env python3
"""Reference-driven search for Planet Focus's procedural wave parameters.

This is a development tool, not production runtime code. It mutates the same
semantic parameters used by the Swift generator, renders complete candidates,
and retains changes only when the reference-derived objective improves.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from score_splash_waves import (
    NORMALIZED_SIZE,
    normalize,
    phase_synchrony,
    ranked_boundaries,
    score,
)


COLORS = [
    (81, 107, 175),
    (13, 54, 144),
    (247, 163, 55),
    (131, 111, 179),
    (45, 80, 168),
    (13, 54, 144),
    (81, 107, 175),
    (131, 111, 179),
]

FIT_PALETTE = np.asarray(
    [
        (13, 54, 144),
        (45, 80, 168),
        (81, 107, 175),
        (131, 111, 179),
        (247, 163, 55),
    ],
    dtype=np.float64,
)
LAYER_LABELS = np.asarray([2, 0, 4, 3, 1, 0, 2, 3], dtype=np.int8)
FIT_SIZE = (320, 221)
WORLD_HORIZONTAL_OFFSET = 0.0


INITIAL = {
    "excursion_scale": 0.65,
    "ribbon_frequency_scale": 1.50,
    "ribbon_overlap": 0.05,
    "warm_weight_scale": 0.32,
    "envelope_top": [0.1071, 0.085, 0.054, -0.0581],
    "envelope_bottom": [0.8884, -0.0341, 0.0467, -0.0623, 0.080],
    "envelope_shift": [0.0, 0.0, 0.0],
    "ribbons": [
        {"attachment": "none", "centerline": [0.22, 0.09, 1.00, 0.25, 0.04, 2.00, 0.25, 0.02, 3.00, 0.25], "thickness": [0.23, 0.05, 1.65, 0.89, 0.012, 3.06, 0.44]},
        {"attachment": "none", "centerline": [0.29, 0.09, 2.28, 0.16, 0.025, 3.92, 0.54], "thickness": [0.21, 0.055, 1.62, 0.64, 0.025, 3.36, 0.25]},
        {"attachment": "none", "centerline": [0.47, 0.065, 2.52, 0.75, 0.015, 3.53, 0.07], "thickness": [0.04, 0.025, 1.59, 0.15]},
        {"attachment": "none", "centerline": [0.50, 0.08, 2.10, 0.41, 0.025, 3.65, 0.89], "thickness": [0.25, 0.06, 1.81, 0.34, 0.04, 3.49, 0.68]},
        {"attachment": "none", "centerline": [0.60, 0.09, 2.21, 0.99, 0.045, 3.96, 0.48], "thickness": [0.23, 0.05, 1.77, 0.64, 0.04, 3.33, 0.17]},
        {"attachment": "none", "centerline": [0.67, 0.06, 2.71, 0.64, 0.015, 3.92, 0.26], "thickness": [0.20, 0.05, 1.87, 0.09, 0.02, 3.12, 0.68]},
        {"attachment": "none", "centerline": [0.74, 0.07, 2.27, 0.27, 0.02, 3.80, 0.69], "thickness": [0.21, 0.04, 1.93, 0.67, 0.04, 3.45, 0.11]},
        {"attachment": "none", "centerline": [0.82, 0.04, 1.00, 0.75, 0.04, 2.00, 0.25, 0.02, 3.00, 0.75], "thickness": [0.14, 0.045, 1.94, 0.78, 0.025, 3.04, 0.31]},
    ],
}

REFERENCE_SYNCHRONY = 0.3942
REFERENCE_PORTRAIT_SYNCHRONY = 0.4142
EDGE_MARGIN = 0.012
SOFTNESS = 48.0
CENTER_BASE_BOUNDS = [
    (0.08, 0.30),
    (0.28, 0.36),
    (0.43, 0.55),
    (0.45, 0.55),
    (0.55, 0.65),
    (0.63, 0.72),
    (0.70, 0.80),
    (0.72, 0.94),
]
INDEPENDENT_CENTER_BASE_BOUNDS = [
    (-0.05, 0.40),
    (0.10, 0.60),
    (0.20, 0.65),
    (0.15, 0.65),
    (0.30, 0.78),
    (0.42, 0.88),
    (0.42, 0.92),
    (0.52, 0.98),
]
THICKNESS_BASE_BOUNDS = [
    (0.18, 0.34),
    (0.15, 0.32),
    (0.025, 0.12),
    (0.12, 0.32),
    (0.12, 0.30),
    (0.12, 0.30),
    (0.17, 0.30),
    (0.14, 0.24),
]
INDEPENDENT_THICKNESS_BASE_BOUNDS = [
    (0.040, 0.30),
    (0.020, 0.25),
    (0.012, 0.08),
    (0.060, 0.25),
    (0.040, 0.24),
    (0.030, 0.25),
    (0.040, 0.28),
    (0.040, 0.24),
]


def harmonic(parameters: list[float], x: np.ndarray) -> np.ndarray:
    value = np.full_like(x, parameters[0], dtype=np.float64)
    for index in range(1, len(parameters), 3):
        amplitude, cycles, phase = parameters[index:index + 3]
        value += amplitude * np.sin(2 * np.pi * (cycles * x + phase))
    return value


def envelope(parameters: dict, x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    if "envelope_center" in parameters and "envelope_span" in parameters:
        center_parameters = parameters["envelope_center"]
        span_parameters = parameters["envelope_span"]
        center = np.full_like(x, center_parameters[0])
        for frequency in range(1, 7):
            cosine = center_parameters[1 + 2 * (frequency - 1)]
            sine = center_parameters[2 + 2 * (frequency - 1)]
            center += cosine * np.cos(2 * np.pi * frequency * x)
            center += sine * np.sin(2 * np.pi * frequency * x)
        span = np.full_like(x, span_parameters[0])
        for frequency, coefficient in enumerate(span_parameters[1:7], start=1):
            span += coefficient * np.cos(2 * np.pi * frequency * x)
        span += span_parameters[7] * (x - 0.5) ** 2
        return center - span / 2, center + span / 2

    top = np.full_like(x, parameters["envelope_top"][0])
    bottom = np.full_like(x, parameters["envelope_bottom"][0])
    for frequency, coefficient in enumerate(parameters["envelope_top"][1:], start=1):
        top += coefficient * np.cos(2 * np.pi * frequency * x)
    for frequency, coefficient in enumerate(parameters["envelope_bottom"][1:4], start=1):
        bottom += coefficient * np.cos(2 * np.pi * frequency * x)
    bottom += parameters["envelope_bottom"][4] * (x - 0.5) ** 2
    for frequency, coefficient in enumerate(parameters.get("envelope_shift", [0.0, 0.0, 0.0]), start=1):
        shift = coefficient * np.sin(2 * np.pi * frequency * x)
        top += shift
        bottom += shift
    return top, bottom


def softplus(value: np.ndarray, sharpness: float = SOFTNESS) -> np.ndarray:
    scaled = sharpness * value
    return (np.maximum(scaled, 0) + np.log1p(np.exp(-np.abs(scaled)))) / sharpness


def smooth_clamp(value: np.ndarray, lower: np.ndarray, upper: np.ndarray) -> np.ndarray:
    return lower + softplus(value - lower) - softplus(value - upper)


def independent_ribbon_edges(
    parameters: dict,
    x: np.ndarray,
) -> list[tuple[np.ndarray, np.ndarray]]:
    """Evaluate independently phased analytic ribbons inside a coverage sheet.

    Each sheet owns its centerline and thickness field. The analytic envelope is
    a hidden coverage sheet, not a guard that pins either visible ribbon. The
    coverage sheet closes any intentional negative space between paper strips.
    Visible ribbon geometry is otherwise identical to the Swift runtime.
    """
    outer_top, outer_bottom = envelope(parameters, x)
    spatial_x = x * parameters.get("ribbon_frequency_scale", 1.50)
    center_scale = parameters.get("center_amplitude_scale", 0.72)
    thickness_scale = parameters.get("thickness_amplitude_scale", 0.62)
    edges: list[list[np.ndarray]] = []
    for ribbon_index, ribbon in enumerate(parameters["ribbons"]):
        raw_center = harmonic(ribbon["centerline"], spatial_x)
        center = ribbon["centerline"][0] + center_scale * (
            raw_center - ribbon["centerline"][0]
        )
        center += ribbon.get("center_drift", 0.0) * (x - 0.5)
        raw_thickness = harmonic(ribbon["thickness"], spatial_x)
        thickness_signal = ribbon["thickness"][0] + thickness_scale * (
            raw_thickness - ribbon["thickness"][0]
        )
        thickness = 0.010 + softplus(
            thickness_signal - 0.010,
            sharpness=32,
        )
        thickness = np.minimum(thickness, 0.38 * (outer_bottom - outer_top))
        half = thickness / 2
        center = smooth_clamp(
            center,
            lower=outer_top + half,
            upper=outer_bottom - half,
        )
        top = center - half
        bottom = center + half
        edges.append([
            np.maximum(top, outer_top),
            np.minimum(bottom, outer_bottom),
        ])

    return [(top, bottom) for top, bottom in edges]


def shared_seam_ribbon_edges(parameters: dict, x: np.ndarray) -> list[tuple[np.ndarray, np.ndarray]]:
    outer_top, outer_bottom = envelope(parameters, x)
    span = np.maximum(outer_bottom - outer_top, 0.10)
    spatial_x = x * parameters.get("ribbon_frequency_scale", 1.50)
    weights = []
    excursions = []
    excursion_multipliers = parameters.get(
        "excursion_multipliers",
        [1.0, 1.0, 0.28, 1.0, 1.0, 1.0, 1.0, 1.0],
    )
    weight_multipliers = parameters.get(
        "weight_multipliers",
        [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
    )
    for ribbon_index, ribbon in enumerate(parameters["ribbons"]):
        thickness_field = harmonic(ribbon["thickness"], spatial_x)
        thickness_variation = parameters.get("thickness_variation_scale", 1.0)
        raw_thickness = ribbon["thickness"][0] + thickness_variation * (
            thickness_field - ribbon["thickness"][0]
        )
        weight = 0.010 + softplus(raw_thickness - 0.010, sharpness=32)
        weight *= weight_multipliers[ribbon_index]
        if ribbon_index == 2:
            weight *= parameters.get("warm_weight_scale", 0.32)
        weights.append(weight)
        excursions.append(
            parameters.get("excursion_scale", 0.65)
            * excursion_multipliers[ribbon_index]
            * (harmonic(ribbon["centerline"], spatial_x) - ribbon["centerline"][0])
        )

    normalized_weights = np.asarray(weights)
    normalized_weights /= np.maximum(normalized_weights.sum(axis=0), 0.001)
    base_boundaries = outer_top + np.vstack(
        [np.zeros_like(x), np.cumsum(normalized_weights, axis=0)]
    ) * span
    lane_tops = base_boundaries[:-1]
    lane_bottoms = base_boundaries[1:]
    lane_centers = (lane_tops + lane_bottoms) / 2

    target_centers = []
    for ribbon_index, excursion in enumerate(excursions):
        lane_center = lane_centers[ribbon_index]
        upward = np.maximum(lane_center - outer_top, 0.001)
        downward = np.maximum(outer_bottom - lane_center, 0.001)
        bounded = np.where(
            excursion < 0,
            upward * np.tanh(excursion / upward),
            downward * np.tanh(excursion / downward),
        )
        target_centers.append(lane_center + bounded)

    desired_boundaries = [outer_top]
    for ribbon_index in range(len(parameters["ribbons"]) - 1):
        upper_half = (lane_bottoms[ribbon_index] - lane_tops[ribbon_index]) / 2
        lower_half = (lane_bottoms[ribbon_index + 1] - lane_tops[ribbon_index + 1]) / 2
        upper_edge = target_centers[ribbon_index] + upper_half
        lower_edge = target_centers[ribbon_index + 1] - lower_half
        desired_boundaries.append((upper_edge + lower_edge) / 2)
    desired_boundaries.append(outer_bottom)

    desired_widths = np.diff(np.asarray(desired_boundaries), axis=0) / span
    minimum_shares = np.asarray(
        [0.070, 0.080, 0.015, 0.065, 0.075, 0.120, 0.100, 0.100]
    )[:, None]
    flexible_share = 1 - float(minimum_shares.sum())
    excesses = softplus(desired_widths - minimum_shares, sharpness=54)
    excesses /= np.maximum(excesses.sum(axis=0), 0.001)
    positive_widths = minimum_shares + flexible_share * excesses
    boundaries = outer_top + np.vstack(
        [np.zeros_like(x), np.cumsum(positive_widths, axis=0)]
    ) * span

    overlap = parameters.get("seam_overlap", 0.006)
    occlusion_scale = parameters.get("occlusion_scale", 0.0)
    occlusion_multipliers = parameters.get(
        "occlusion_multipliers",
        [0.0, 0.30, 0.20, 0.80, 0.70, 0.90, 0.80, 1.0],
    )
    result = []
    for ribbon_index in range(len(parameters["ribbons"])):
        top = boundaries[ribbon_index].copy()
        bottom = boundaries[ribbon_index + 1].copy()
        if ribbon_index > 0:
            top -= overlap
            ribbon = parameters["ribbons"][ribbon_index]
            center_signal = (
                harmonic(ribbon["centerline"], spatial_x)
                - ribbon["centerline"][0]
            )
            overhang = softplus(
                0.003
                + occlusion_scale
                * occlusion_multipliers[ribbon_index]
                * center_signal,
                sharpness=52,
            )
            top -= overhang
        if ribbon_index < len(parameters["ribbons"]) - 1:
            bottom += overlap
        result.append((np.maximum(top, outer_top), np.minimum(bottom, outer_bottom)))
    return result


def ribbon_edges(parameters: dict, x: np.ndarray) -> list[tuple[np.ndarray, np.ndarray]]:
    """Evaluate independent ribbons inside analytic outer guard sheets.

    The rear periwinkle owns the upper boundary and the front lavender owns the
    lower boundary. Their cosine envelopes guarantee equal left/right total height
    without rescaling or vertically transporting any interior ribbon.
    """
    if parameters.get("geometry_model", "independent") == "shared_seams":
        return shared_seam_ribbon_edges(parameters, x)
    return independent_ribbon_edges(parameters, x)


def centerline_synchrony(parameters: dict, crop: tuple[float, float]) -> float:
    x = np.linspace(crop[0], crop[1], 513)
    centers = np.asarray([(top + bottom) / 2 for top, bottom in ribbon_edges(parameters, x)])
    slopes = np.gradient(centers, axis=1)
    scale = max(float(np.quantile(np.abs(slopes), 0.60)), 0.0001)
    signed_motion = np.tanh(slopes / scale)
    return float(np.mean(np.abs(signed_motion.mean(axis=0))))


def render(parameters: dict, scale: int = 2) -> np.ndarray:
    width, height = NORMALIZED_SIZE
    short_side = height
    world_width = short_side * 3.0
    world_height = short_side * 0.52
    world_left = (
        (width - world_width) / 2
        + parameters.get("world_horizontal_offset", WORLD_HORIZONTAL_OFFSET) * short_side
    )
    world_top = height * 0.610 - world_height / 2
    screen_x = np.linspace(0, width * scale - 1, width * scale)
    world_x = (screen_x / scale - world_left) / world_width
    edges = ribbon_edges(parameters, world_x)
    canvas = Image.new("RGB", (width * scale, height * scale), (10, 17, 36))
    draw = ImageDraw.Draw(canvas)
    outer_top, outer_bottom = envelope(parameters, world_x)
    coverage_top = (world_top + outer_top * world_height) * scale
    coverage_bottom = (world_top + outer_bottom * world_height) * scale
    coverage_points = list(zip(screen_x, coverage_top)) + list(
        zip(screen_x[::-1], coverage_bottom[::-1])
    )
    draw.polygon(coverage_points, fill=COLORS[1])
    draw_order = parameters.get("draw_order", list(range(len(edges))))
    for ribbon_index in draw_order:
        color = COLORS[ribbon_index]
        top, bottom = edges[ribbon_index]
        y_top = (world_top + top * world_height) * scale
        y_bottom = (world_top + bottom * world_height) * scale
        points = list(zip(screen_x, y_top)) + list(zip(screen_x[::-1], y_bottom[::-1]))
        draw.polygon(points, fill=color)
    return np.asarray(canvas.resize(NORMALIZED_SIZE, Image.Resampling.LANCZOS), dtype=np.uint8)


class ReferenceRasterObjective:
    """Fast, texture-tolerant comparison of analytic ribbons to the source pixels."""

    def __init__(self, reference: np.ndarray):
        image = np.asarray(
            Image.fromarray(reference).resize(FIT_SIZE, Image.Resampling.LANCZOS),
            dtype=np.float64,
        )
        distance = np.sqrt(
            ((image[:, :, None, :] - FIT_PALETTE[None, None, :, :]) ** 2).sum(axis=3)
        )
        self.reference_labels = distance.argmin(axis=2).astype(np.int8)
        self.reference_labels[distance.min(axis=2) > 82] = -1

        width, height = FIT_SIZE
        y, x = np.indices((height, width))
        # Score every plausible wave pixel, including empty space above the source
        # silhouette.  The earlier 0.30 crop accidentally let a candidate improve
        # by lifting a ribbon out of the judged band.
        self.evaluation_mask = (y >= 0.12 * height) & (y < 0.82 * height)
        wordmark = (
            (x >= 0.035 * width)
            & (x <= 0.30 * width)
            & (y <= 0.33 * height)
        )
        self.evaluation_mask &= ~wordmark
        self.contour_mask = self.evaluation_mask.copy()
        # Lotus pixels use the same palette as the waves but are not wave targets.
        for center_x, center_y, radius_x, radius_y in [
            (0.385, 0.63, 0.115, 0.14),
            (0.585, 0.515, 0.095, 0.12),
            (0.76, 0.70, 0.125, 0.15),
        ]:
            lotus = (
                ((x / width - center_x) / radius_x) ** 2
                + ((y / height - center_y) / radius_y) ** 2
            ) <= 1
            self.evaluation_mask &= ~lotus

        sun = (
            ((x / width - 0.695) / 0.145) ** 2
            + ((y / height - 0.40) / 0.19) ** 2
        ) <= 1
        self.evaluation_mask &= ~(sun & (self.reference_labels == 4))
        self.y = y
        self.reference_top, self.reference_bottom = self._smooth_outer_contours(
            self.reference_labels
        )
        self.reference_orphan_rate = self._orphan_rate(self.reference_labels)
        self.reference_synchrony = phase_synchrony(self.reference_labels)
        self.reference_portrait_synchrony = phase_synchrony(
            self.reference_labels,
            (0.25, 0.75),
        )
        self.reference_track_roughness = self._track_roughness(self.reference_labels)

    @staticmethod
    def _track_roughness(labels: np.ndarray) -> tuple[float, float]:
        tracks = ranked_boundaries(labels)
        curvature = np.abs(np.diff(tracks, n=2, axis=1))
        return float(np.mean(curvature)), float(np.quantile(curvature, 0.98))

    def _orphan_rate(self, labels: np.ndarray) -> float:
        """Measure a skinny top strip isolated from the main wave field."""
        _, width = labels.shape
        orphan_columns = 0
        judged_columns = 0
        for column in range(width):
            present = (labels[:, column] >= 0) & self.contour_mask[:, column]
            ys = np.flatnonzero(present)
            if not ys.size:
                continue
            breaks = np.flatnonzero(np.diff(ys) > 1)
            column_has_orphan = False
            if breaks.size:
                top_run_end_index = int(breaks[0])
                run_length = int(ys[top_run_end_index] - ys[0] + 1)
                gap_length = int(ys[top_run_end_index + 1] - ys[top_run_end_index] - 1)
                top_label = labels[ys[0], column]
                column_has_orphan = (
                    top_label != 4 and run_length <= 5 and gap_length >= 5
                )
            judged_columns += 1
            orphan_columns += int(column_has_orphan)
        return orphan_columns / max(judged_columns, 1)

    def _smooth_outer_contours(
        self,
        labels: np.ndarray,
    ) -> tuple[np.ndarray, np.ndarray]:
        """Return low-frequency outer contours without tracing lotus petal tips."""
        height, width = labels.shape
        top = np.full(width, np.nan)
        bottom = np.full(width, np.nan)
        for column in range(width):
            ys = np.flatnonzero(
                (labels[:, column] >= 0)
                & (labels[:, column] != 4)
                & self.contour_mask[:, column]
            )
            if ys.size:
                top[column] = ys[0]
                bottom[column] = ys[-1]

        def robust_fourier_fit(values: np.ndarray) -> np.ndarray:
            valid = np.flatnonzero(np.isfinite(values))
            x = np.linspace(0, 1, width)
            basis = [np.ones(width)]
            for frequency in range(1, 6):
                basis.extend(
                    [
                        np.sin(2 * np.pi * frequency * x),
                        np.cos(2 * np.pi * frequency * x),
                    ]
                )
            design = np.asarray(basis).T
            keep = valid
            for _ in range(4):
                coefficients, *_ = np.linalg.lstsq(
                    design[keep], values[keep], rcond=None
                )
                fitted = design @ coefficients
                residual = np.abs(values[valid] - fitted[valid])
                median = float(np.median(residual))
                mad = float(np.median(np.abs(residual - median)))
                threshold = max(median + 2.8 * mad, 2.5)
                keep = valid[residual <= threshold]
            return fitted / height

        return robust_fourier_fit(top), robust_fourier_fit(bottom)

    def _outer_contours(
        self,
        labels: np.ndarray,
    ) -> tuple[np.ndarray, np.ndarray]:
        present = (labels >= 0) & self.contour_mask
        height = labels.shape[0]
        has_wave = present.any(axis=0)
        top = present.argmax(axis=0).astype(np.float64)
        bottom = (
            height - 1 - present[::-1].argmax(axis=0)
        ).astype(np.float64)
        if not np.all(has_wave):
            valid = np.flatnonzero(has_wave)
            missing = np.flatnonzero(~has_wave)
            top[missing] = np.interp(missing, valid, top[valid])
            bottom[missing] = np.interp(missing, valid, bottom[valid])
        return top / height, bottom / height

    def candidate_labels(self, parameters: dict) -> np.ndarray:
        width, height = FIT_SIZE
        screen_x = np.linspace(0, width - 1, width)
        short_side = height
        world_width = short_side * 3.0
        world_height = short_side * 0.52
        world_left = (
            (width - world_width) / 2
            + parameters.get("world_horizontal_offset", WORLD_HORIZONTAL_OFFSET) * short_side
        )
        world_top = height * 0.610 - world_height / 2
        world_x = (screen_x - world_left) / world_width
        labels = np.full((height, width), -1, dtype=np.int8)

        outer_top, outer_bottom = envelope(parameters, world_x)
        coverage_top = world_top + outer_top * world_height
        coverage_bottom = world_top + outer_bottom * world_height
        coverage = (self.y >= coverage_top[None, :]) & (
            self.y <= coverage_bottom[None, :]
        )
        labels[coverage] = LAYER_LABELS[1]

        edges = ribbon_edges(parameters, world_x)
        draw_order = parameters.get("draw_order", list(range(len(edges))))
        for ribbon_index in draw_order:
            label = LAYER_LABELS[ribbon_index]
            top, bottom = edges[ribbon_index]
            top_pixels = world_top + top * world_height
            bottom_pixels = world_top + bottom * world_height
            inside = (self.y >= top_pixels[None, :]) & (self.y <= bottom_pixels[None, :])
            labels[inside] = label
        return labels

    def metrics(self, parameters: dict) -> dict[str, float]:
        candidate = self.candidate_labels(parameters)
        reference = self.reference_labels
        relevant = self.evaluation_mask & ((reference >= 0) | (candidate >= 0))
        exact = float(np.mean(reference[relevant] == candidate[relevant]))

        palette_intersection = 0
        palette_union = 0
        per_color_iou = []
        for label in range(len(FIT_PALETTE)):
            reference_color = self.evaluation_mask & (reference == label)
            candidate_color = self.evaluation_mask & (candidate == label)
            intersection = int(np.logical_and(reference_color, candidate_color).sum())
            union = int(np.logical_or(reference_color, candidate_color).sum())
            palette_intersection += intersection
            palette_union += union
            per_color_iou.append(intersection / max(union, 1))
        palette_iou = palette_intersection / max(palette_union, 1)
        balanced_palette_iou = float(np.mean(per_color_iou))
        lower_tail_palette_iou = float(np.mean(np.sort(per_color_iou)[:2]))

        reference_mask = self.evaluation_mask & (reference >= 0)
        candidate_mask = self.evaluation_mask & (candidate >= 0)
        mask_iou = float(
            np.logical_and(reference_mask, candidate_mask).sum()
            / max(np.logical_or(reference_mask, candidate_mask).sum(), 1)
        )

        candidate_top, candidate_bottom = self._outer_contours(candidate)
        silhouette_error = float(
            (
                np.mean(np.abs(candidate_top - self.reference_top))
                + np.mean(np.abs(candidate_bottom - self.reference_bottom))
            )
            / 2
        )
        silhouette_similarity = math.exp(-silhouette_error / 0.055)
        orphan_rate = self._orphan_rate(candidate)
        orphan_similarity = math.exp(
            -abs(orphan_rate - self.reference_orphan_rate) / 0.08
        )

        regional_scores = []
        regional_silhouette_scores = []
        for region in range(8):
            left = round(region * candidate.shape[1] / 8)
            right = round((region + 1) * candidate.shape[1] / 8)
            regional_relevant = relevant[:, left:right]
            regional_exact = float(
                np.mean(
                    reference[:, left:right][regional_relevant]
                    == candidate[:, left:right][regional_relevant]
                )
            )
            regional_reference_mask = reference_mask[:, left:right]
            regional_candidate_mask = candidate_mask[:, left:right]
            regional_union = np.logical_or(
                regional_reference_mask,
                regional_candidate_mask,
            ).sum()
            regional_iou = float(
                np.logical_and(
                    regional_reference_mask,
                    regional_candidate_mask,
                ).sum()
                / max(regional_union, 1)
            )
            regional_scores.append(0.60 * regional_exact + 0.40 * regional_iou)
            regional_silhouette_error = float(
                (
                    np.mean(
                        np.abs(
                            candidate_top[left:right]
                            - self.reference_top[left:right]
                        )
                    )
                    + np.mean(
                        np.abs(
                            candidate_bottom[left:right]
                            - self.reference_bottom[left:right]
                        )
                    )
                )
                / 2
            )
            regional_silhouette_scores.append(
                math.exp(-regional_silhouette_error / 0.045)
            )
        lower_tail_region_similarity = float(
            np.mean(np.sort(regional_scores)[:2])
        )
        lower_tail_silhouette_similarity = float(
            np.mean(np.sort(regional_silhouette_scores)[:2])
        )

        synchrony = phase_synchrony(candidate)
        portrait_synchrony = phase_synchrony(candidate, (0.25, 0.75))
        synchrony_error = (
            abs(synchrony - self.reference_synchrony)
            + abs(portrait_synchrony - self.reference_portrait_synchrony)
        ) / 2
        phase_similarity = math.exp(-synchrony_error / 0.12)
        candidate_roughness = self._track_roughness(candidate)
        roughness_error = (
            abs(candidate_roughness[0] - self.reference_track_roughness[0])
            / max(self.reference_track_roughness[0], 0.00001)
            + abs(candidate_roughness[1] - self.reference_track_roughness[1])
            / max(self.reference_track_roughness[1], 0.00001)
        ) / 2
        interior_smoothness = math.exp(-roughness_error / 0.85)
        # A good global average cannot compensate for erasing a palette member.
        # The lower-tail term keeps the small mid-blue and warm reveal accountable.
        fidelity = 100 * (
            0.09 * exact
            + 0.05 * palette_iou
            + 0.15 * balanced_palette_iou
            + 0.14 * lower_tail_palette_iou
            + 0.08 * mask_iou
            + 0.08 * silhouette_similarity
            + 0.06 * phase_similarity
            + 0.06 * interior_smoothness
            + 0.08 * orphan_similarity
            + 0.08 * lower_tail_region_similarity
            + 0.13 * lower_tail_silhouette_similarity
        )
        return {
            "wave_fidelity": round(fidelity, 4),
            "dense_label_accuracy": round(100 * exact, 4),
            "palette_iou": round(100 * palette_iou, 4),
            "balanced_palette_iou": round(100 * balanced_palette_iou, 4),
            "lower_tail_palette_iou": round(100 * lower_tail_palette_iou, 4),
            "per_color_iou": [round(100 * value, 4) for value in per_color_iou],
            "wave_mask_iou": round(100 * mask_iou, 4),
            "silhouette_similarity": round(100 * silhouette_similarity, 4),
            "silhouette_error": round(silhouette_error, 6),
            "orphan_similarity": round(100 * orphan_similarity, 4),
            "reference_orphan_rate": round(self.reference_orphan_rate, 6),
            "candidate_orphan_rate": round(orphan_rate, 6),
            "lower_tail_region_similarity": round(
                100 * lower_tail_region_similarity,
                4,
            ),
            "regional_similarity": [
                round(100 * value, 4) for value in regional_scores
            ],
            "lower_tail_silhouette_similarity": round(
                100 * lower_tail_silhouette_similarity,
                4,
            ),
            "regional_silhouette_similarity": [
                round(100 * value, 4)
                for value in regional_silhouette_scores
            ],
            "mathematical_phase_similarity": round(100 * phase_similarity, 4),
            "mathematical_phase_synchrony": round(synchrony, 4),
            "mathematical_portrait_synchrony": round(portrait_synchrony, 4),
            "interior_smoothness": round(100 * interior_smoothness, 4),
            "reference_track_roughness": [round(value, 7) for value in self.reference_track_roughness],
            "candidate_track_roughness": [round(value, 7) for value in candidate_roughness],
        }


def objective(
    reference_objective: ReferenceRasterObjective,
    parameters: dict,
    focus_label: int | None = None,
    focus_silhouette: bool = False,
    focus_phase: bool = False,
) -> tuple[float, dict[str, float]]:
    metrics = reference_objective.metrics(parameters)
    optimization_score = metrics["wave_fidelity"]
    if focus_label is not None:
        # A focused cleanup pass is allowed to trade a little aggregate overlap for
        # visibility of a small palette region, but the global score stays dominant.
        optimization_score = (
            0.72 * optimization_score
            + 0.28 * metrics["per_color_iou"][focus_label]
        )
    if focus_silhouette:
        optimization_score = (
            0.62 * optimization_score
            + 0.38 * metrics["silhouette_similarity"]
        )
    if focus_phase:
        optimization_score = (
            0.55 * optimization_score
            + 0.45 * metrics["mathematical_phase_similarity"]
        )
    return optimization_score, metrics


def mutate(
    parameters: dict,
    rng: np.random.Generator,
    temperature: float,
    mutable_ribbons: list[int] | None = None,
    phases_only: bool = False,
    envelope_only: bool = False,
) -> dict:
    candidate = copy.deepcopy(parameters)
    if envelope_only:
        envelope_fields = (
            ["envelope_center", "envelope_span"]
            if "envelope_center" in candidate
            else ["envelope_top", "envelope_bottom", "envelope_shift"]
        )
        field = str(rng.choice(envelope_fields))
        values = candidate[field]
        index = int(rng.integers(0, len(values)))
        sigma = 0.012 if index == 0 else 0.008
        values[index] += float(rng.normal(0, sigma * max(temperature, 0.20)))
        return constrain(candidate)
    if not phases_only and mutable_ribbons is None and rng.random() < 0.08:
        field = str(rng.choice([
            "coverage_overlap",
            "coverage_repair",
            "center_amplitude_scale",
            "thickness_amplitude_scale",
            "guard_thickness_scale",
            "warm_weight_scale",
            "ribbon_frequency_scale",
        ]))
        sigma = {
            "coverage_overlap": 0.006,
            "coverage_repair": 0.05,
            "center_amplitude_scale": 0.05,
            "thickness_amplitude_scale": 0.05,
            "guard_thickness_scale": 0.04,
        }.get(field, 0.05)
        defaults = {
            "coverage_overlap": 0.010,
            "coverage_repair": 0.82,
            "center_amplitude_scale": 0.72,
            "thickness_amplitude_scale": 0.62,
            "guard_thickness_scale": 0.66,
        }
        base_value = candidate.get(field)
        if base_value is None:
            base_value = INITIAL.get(field, defaults.get(field, 0.0))
        candidate[field] = base_value + float(
            rng.normal(0, sigma * max(temperature, 0.20))
        )
        return constrain(candidate)
    if not phases_only and mutable_ribbons is None and rng.random() < 0.12:
        envelope_fields = (
            ["envelope_center", "envelope_span"]
            if "envelope_center" in candidate
            else ["envelope_top", "envelope_bottom", "envelope_shift"]
        )
        field = str(rng.choice(envelope_fields))
        values = candidate[field]
        index = int(rng.integers(0, len(values)))
        sigma = 0.012 if index == 0 else 0.008
        values[index] += float(rng.normal(0, sigma * max(temperature, 0.20)))
        return constrain(candidate)
    if mutable_ribbons:
        ribbon_index = int(rng.choice(mutable_ribbons))
    else:
        ribbon_index = int(rng.integers(0, len(candidate["ribbons"])))
    ribbon = candidate["ribbons"][ribbon_index]
    if phases_only:
        field = "centerline" if rng.random() < 0.72 else "thickness"
        values = ribbon[field]
        phase_indices = list(range(3, len(values), 3))
        if not phase_indices:
            return candidate
        index = int(rng.choice(phase_indices))
        values[index] = float(
            (values[index] + rng.normal(0, 0.05 * max(temperature, 0.20))) % 1.0
        )
        return constrain(candidate)
    if rng.random() < 0.08:
        ribbon["center_drift"] = float(
            np.clip(
                ribbon.get("center_drift", 0.0)
                + rng.normal(0, 0.045 * max(temperature, 0.20)),
                -0.90,
                0.90,
            )
        )
        return constrain(candidate)
    field = "centerline" if rng.random() < 0.62 else "thickness"
    values = ribbon[field]
    index = int(rng.integers(0, len(values)))
    kind = index % 3
    if index == 0:
        sigma = 0.020
    elif kind == 1:
        sigma = 0.012
    elif kind == 2:
        sigma = 0.10
    else:
        sigma = 0.035
    values[index] += float(rng.normal(0, sigma * max(temperature, 0.20)))
    if index == 0:
        bounds = (
            (
                INDEPENDENT_CENTER_BASE_BOUNDS[ribbon_index]
                if candidate.get("geometry_model", "independent") == "independent"
                else CENTER_BASE_BOUNDS[ribbon_index]
            )
            if field == "centerline"
            else (
                INDEPENDENT_THICKNESS_BASE_BOUNDS[ribbon_index]
                if candidate.get("geometry_model", "independent") == "independent"
                else THICKNESS_BASE_BOUNDS[ribbon_index]
            )
        )
        values[index] = float(np.clip(values[index], *bounds))
    elif kind == 1:
        independent = candidate.get("geometry_model", "independent") == "independent"
        amplitude_limit = (
            (0.22 if field == "centerline" else 0.13)
            if independent
            else (0.18 if field == "centerline" else 0.14)
        )
        values[index] = float(np.clip(values[index], 0.0, amplitude_limit))
    elif kind == 2:
        maximum_cycles = (
            8.0
            if candidate.get("geometry_model", "independent") == "independent"
            else 2.2
        )
        values[index] = float(np.clip(values[index], 0.65, maximum_cycles))
    else:
        values[index] %= 1.0
    return constrain(candidate)


def constrain(parameters: dict) -> dict:
    independent = parameters.get("geometry_model", "independent") == "independent"
    parameters["world_horizontal_offset"] = 0.0
    draw_order = parameters.setdefault(
        "draw_order",
        list(range(len(parameters["ribbons"]))),
    )
    if sorted(draw_order) != list(range(len(parameters["ribbons"]))):
        parameters["draw_order"] = list(range(len(parameters["ribbons"])))
    parameters["excursion_scale"] = float(
        np.clip(parameters.get("excursion_scale", 0.65), 0.18, 1.0)
    )
    parameters["ribbon_frequency_scale"] = float(
        np.clip(parameters.get("ribbon_frequency_scale", 0.72), 0.40, 2.40)
    )
    parameters["center_amplitude_scale"] = float(
        np.clip(parameters.get("center_amplitude_scale", 0.72), 0.25, 1.0)
    )
    parameters["thickness_amplitude_scale"] = float(
        np.clip(parameters.get("thickness_amplitude_scale", 0.62), 0.20, 1.0)
    )
    parameters["guard_thickness_scale"] = float(
        np.clip(parameters.get("guard_thickness_scale", 0.66), 0.45, 0.90)
    )
    parameters["coverage_overlap"] = float(
        np.clip(parameters.get("coverage_overlap", 0.010), -0.015, 0.035)
    )
    parameters["coverage_repair"] = float(
        np.clip(parameters.get("coverage_repair", 0.82), 0.0, 1.0)
    )
    parameters["warm_weight_scale"] = float(
        np.clip(parameters.get("warm_weight_scale", 0.32), 0.12, 0.65)
    )
    if "envelope_center" in parameters:
        parameters["envelope_center"][0] = float(
            np.clip(parameters["envelope_center"][0], 0.38, 0.52)
        )
        parameters["envelope_span"][0] = float(
            np.clip(parameters["envelope_span"][0], 0.62, 0.86)
        )
        for field in ["envelope_center", "envelope_span"]:
            for index in range(1, len(parameters[field])):
                parameters[field][index] = float(
                    np.clip(parameters[field][index], -0.12, 0.12)
                )
    else:
        parameters["envelope_top"][0] = float(
            np.clip(parameters["envelope_top"][0], 0.04, 0.16)
        )
        parameters["envelope_bottom"][0] = float(
            np.clip(parameters["envelope_bottom"][0], 0.76, 0.92)
        )
        for field in ["envelope_top", "envelope_bottom"]:
            for index in range(1, len(parameters[field])):
                parameters[field][index] = float(
                    np.clip(parameters[field][index], -0.12, 0.12)
                )
        parameters["envelope_bottom"][4] = float(
            np.clip(parameters["envelope_bottom"][4], 0.0, 0.12)
        )
        for index in range(len(parameters.get("envelope_shift", []))):
            parameters["envelope_shift"][index] = float(
                np.clip(parameters["envelope_shift"][index], -0.08, 0.08)
            )
    for ribbon_index, ribbon in enumerate(parameters["ribbons"]):
        ribbon["center_drift"] = float(
            np.clip(ribbon.get("center_drift", 0.0), -0.90, 0.90)
        )
        for field, bounds in [
            (
                "centerline",
                (
                    INDEPENDENT_CENTER_BASE_BOUNDS[ribbon_index]
                    if independent
                    else CENTER_BASE_BOUNDS[ribbon_index]
                ),
            ),
            (
                "thickness",
                (
                    INDEPENDENT_THICKNESS_BASE_BOUNDS[ribbon_index]
                    if independent
                    else THICKNESS_BASE_BOUNDS[ribbon_index]
                ),
            ),
        ]:
            values = ribbon[field]
            values[0] = float(np.clip(values[0], *bounds))
            for index in range(1, len(values), 3):
                amplitude_limit = (
                    (0.22 if field == "centerline" else 0.13)
                    if independent
                    else (0.12 if field == "centerline" else 0.09)
                )
                values[index] = float(np.clip(values[index], 0.0, amplitude_limit))
                maximum_cycles = 8.0 if independent else 2.2
                values[index + 1] = float(
                    np.clip(values[index + 1], 0.65, maximum_cycles)
                )
                values[index + 2] %= 1.0
    return parameters


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("reference", type=Path)
    parser.add_argument("--iterations", type=int, default=600)
    parser.add_argument("--seed", type=int, default=20260906)
    parser.add_argument("--initial", type=Path)
    parser.add_argument("--focus-label", type=int, choices=range(len(FIT_PALETTE)))
    parser.add_argument("--focus-ribbon", type=int, choices=range(len(LAYER_LABELS)))
    parser.add_argument("--focus-silhouette", action="store_true")
    parser.add_argument("--focus-phase", action="store_true")
    parser.add_argument("--focus-envelope", action="store_true")
    parser.add_argument("--geometry-model", choices=["independent", "shared_seams"])
    parser.add_argument("--greedy", action="store_true")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    reference = normalize(args.reference)
    reference_objective = ReferenceRasterObjective(reference)
    rng = np.random.default_rng(args.seed)
    best = json.loads(args.initial.read_text()) if args.initial else copy.deepcopy(INITIAL)
    if args.geometry_model:
        best["geometry_model"] = args.geometry_model
    best = constrain(best)
    best.setdefault("envelope_shift", [0.0, 0.0, 0.0])
    args.output.mkdir(parents=True, exist_ok=True)
    mutable_ribbons = None
    if args.focus_ribbon is not None:
        mutable_ribbons = [args.focus_ribbon]
    elif args.focus_label is not None:
        matching = np.flatnonzero(LAYER_LABELS == args.focus_label)
        first_matching = int(matching.min())
        mutable_ribbons = list(range(first_matching, len(LAYER_LABELS)))

    best_score, best_metrics = objective(
        reference_objective,
        best,
        args.focus_label,
        args.focus_silhouette,
        args.focus_phase,
    )
    current = copy.deepcopy(best)
    current_score = best_score
    history = [{"iteration": 0, "objective": round(best_score, 4), "metrics": best_metrics}]
    print(f"0 {best_score:.4f}")

    for iteration in range(1, args.iterations + 1):
        temperature = 0.20 if args.greedy else 1 - iteration / max(args.iterations, 1)
        candidate = copy.deepcopy(current)
        step_count = 1 if args.greedy else (
            1
            + int(rng.random() < 0.24 * temperature)
            + int(rng.random() < 0.08 * temperature)
        )
        for _ in range(step_count):
            candidate = mutate(
                candidate,
                rng,
                temperature,
                mutable_ribbons,
                phases_only=args.focus_phase,
                envelope_only=args.focus_envelope,
            )
        candidate_score, candidate_metrics = objective(
            reference_objective,
            candidate,
            args.focus_label,
            args.focus_silhouette,
            args.focus_phase,
        )
        score_temperature = 0 if args.greedy else 0.42 * temperature + 0.008
        if (
            candidate_score >= current_score
            or (
                score_temperature > 0
                and rng.random()
                < math.exp((candidate_score - current_score) / score_temperature)
            )
        ):
            current, current_score = candidate, candidate_score
        if candidate_score > best_score:
            best, best_score, best_metrics = candidate, candidate_score, candidate_metrics
            history.append({"iteration": iteration, "objective": round(best_score, 4), "metrics": best_metrics})
            print(f"{iteration} {best_score:.4f}")
            (args.output / "optimized-parameters.json").write_text(
                json.dumps(best, indent=2) + "\n"
            )
            (args.output / "optimization-history.json").write_text(
                json.dumps(history, indent=2) + "\n"
            )

    (args.output / "optimized-parameters.json").write_text(json.dumps(best, indent=2) + "\n")
    (args.output / "optimization-history.json").write_text(json.dumps(history, indent=2) + "\n")
    rendered = render(best)
    Image.fromarray(rendered).save(args.output / "optimized-flat-preview.png")
    print(json.dumps({
        "objective": round(best_score, 4),
        "metrics": best_metrics,
        "legacy_metrics": score(reference, rendered),
    }, indent=2))


if __name__ == "__main__":
    main()
