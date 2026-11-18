#!/usr/bin/env python3
"""Build compact, static, adaptive pub tiles from a UK OSM GeoJSON export."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import random
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

import numpy as np
from scipy.spatial import cKDTree
from shapely.geometry import shape

EARTH_RADIUS_M = 6_371_008.8
MAX_TILE_PUBS = 40
MAX_EMPTY_DISTANCE_M = 30_000.0
INDEX_PREFIX_DEPTH = 3
WARN_SITE_SIZE = 500_000_000
MAX_SITE_SIZE = 1_000_000_000
UK_BOUNDS = (-8.7, 49.8, 2.2, 60.9)
RANDOM_VALIDATION_POINTS = 300
SPOT_CHECKS = (
    ("Ipswich city centre", 52.0567, 1.1482),
    ("Needham Market village", 52.1510, 1.0530),
    ("Glenmore, Scotland", 57.17, -3.66),
    ("England tile boundary", 52.0, -1.0),
    ("Belfast, Northern Ireland", 54.5973, -5.9301),
)


def xyz(latitude: float, longitude: float) -> tuple[float, float, float]:
    lat = math.radians(latitude)
    lon = math.radians(longitude)
    return (
        math.cos(lat) * math.cos(lon),
        math.cos(lat) * math.sin(lon),
        math.sin(lat),
    )


def chord_distance(distance_m: float) -> float:
    return 2.0 * math.sin(min(distance_m / (2.0 * EARTH_RADIUS_M), math.pi / 2.0))


def metres_from_chord(chord: float) -> float:
    return 2.0 * EARTH_RADIUS_M * math.asin(min(chord / 2.0, 1.0))


def haversine(a: dict[str, Any], b: dict[str, Any]) -> float:
    lat1 = math.radians(a["lat"])
    lat2 = math.radians(b["lat"])
    dlat = lat2 - lat1
    dlon = math.radians(b["lon"] - a["lon"])
    h = math.sin(dlat / 2.0) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2.0) ** 2
    return 2.0 * EARTH_RADIUS_M * math.asin(math.sqrt(min(h, 1.0)))


def element_id(properties: dict[str, Any], fallback: int) -> str:
    kind = properties.get("@type", properties.get("type", ""))
    osm_id = properties.get("@id", properties.get("id", fallback))
    return f"{kind}/{osm_id}"


def normalize_feature(feature: dict[str, Any], fallback: int) -> dict[str, Any] | None:
    properties = feature.get("properties") or {}
    tags = properties.get("tags") or properties
    if tags.get("amenity") != "pub":
        return None

    geometry = feature.get("geometry")
    if not geometry:
        return None
    geom = shape(geometry)
    if geom.is_empty:
        return None
    point = geom if geom.geom_type == "Point" else geom.centroid
    longitude, latitude = point.x, point.y
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return None

    name = tags.get("name")
    hours = tags.get("opening_hours")
    return {
        "id": element_id(properties, fallback),
        "name": name if isinstance(name, str) and name else None,
        "lat": float(latitude),
        "lon": float(longitude),
        "hours": hours if isinstance(hours, str) and hours else None,
        "kind": properties.get("@type", properties.get("type", "")),
    }


def deduplicate(pubs: list[dict[str, Any]], threshold_m: float = 30.0) -> list[dict[str, Any]]:
    """Collapse same-name node/area representations while preserving other venues."""
    cells: dict[tuple[int, int], list[dict[str, Any]]] = defaultdict(list)
    result: list[dict[str, Any]] = []
    cell_size = threshold_m / 111_000.0

    for pub in sorted(pubs, key=lambda item: (item["name"] or "", item["id"])):
        if not pub["name"]:
            result.append(pub)
            continue
        lat_cell = math.floor(pub["lat"] / cell_size)
        lon_scale = max(math.cos(math.radians(pub["lat"])), 0.1)
        lon_cell_size = cell_size / lon_scale
        lon_cell = math.floor(pub["lon"] / lon_cell_size)

        duplicate = False
        for lat_offset in (-1, 0, 1):
            for lon_offset in (-1, 0, 1):
                for existing in cells.get((lat_cell + lat_offset, lon_cell + lon_offset), []):
                    if existing["name"] == pub["name"] and haversine(existing, pub) <= threshold_m:
                        duplicate = True
                        break
                if duplicate:
                    break
            if duplicate:
                break

        if not duplicate:
            result.append(pub)
            cells[(lat_cell, lon_cell)].append(pub)
    return result


class TileBuilder:
    def __init__(
        self,
        pubs: list[dict[str, Any]],
        output: Path,
        built: str,
        max_depth: int = 18,
        max_tile_pubs: int = MAX_TILE_PUBS,
        validation_points: int = RANDOM_VALIDATION_POINTS,
        validation_bounds: tuple[float, float, float, float] = UK_BOUNDS,
        spot_checks: tuple[tuple[str, float, float], ...] = SPOT_CHECKS,
    ) -> None:
        if len(pubs) < 10:
            raise ValueError("The UK snapshot must contain at least ten pubs.")
        self.pubs = pubs
        self.output = output
        self.built = built
        self.max_depth = max_depth
        self.max_tile_pubs = max_tile_pubs
        self.validation_points = validation_points
        self.validation_bounds = validation_bounds
        self.spot_checks = spot_checks
        self.points = [xyz(pub["lat"], pub["lon"]) for pub in pubs]
        self.tree = cKDTree(self.points)
        self.pub_latitudes = np.radians(np.asarray([pub["lat"] for pub in pubs]))
        self.pub_longitudes = np.radians(np.asarray([pub["lon"] for pub in pubs]))
        self.tile_count = 0
        self.index_count = 0
        self.largest_tile_size = 0
        self.total_tile_size = 0
        self._split_paths: dict[str, list[str]] = defaultdict(list)
        self._leaf_pubs: dict[str, list[int]] = {}
        self._root_bounds: dict[str, tuple[float, float, float, float]] = {}

    @staticmethod
    def root_key(latitude: float, longitude: float) -> str:
        return f"{math.floor(latitude)}_{math.floor(longitude)}"

    @staticmethod
    def child_index(latitude: float, longitude: float, bounds: tuple[float, float, float, float]) -> int:
        min_lon, min_lat, max_lon, max_lat = bounds
        mid_lon = (min_lon + max_lon) / 2.0
        mid_lat = (min_lat + max_lat) / 2.0
        return (2 if latitude >= mid_lat else 0) | (1 if longitude >= mid_lon else 0)

    @classmethod
    def prefix_path(cls, latitude: float, longitude: float, depth: int = INDEX_PREFIX_DEPTH) -> str:
        min_lon = math.floor(longitude)
        min_lat = math.floor(latitude)
        bounds = (float(min_lon), float(min_lat), float(min_lon + 1), float(min_lat + 1))
        path = ""
        for _ in range(depth):
            child = cls.child_index(latitude, longitude, bounds)
            bounds = cls.child_bounds(bounds, child)
            path += str(child)
        return path

    @staticmethod
    def child_bounds(bounds: tuple[float, float, float, float], child: int) -> tuple[float, float, float, float]:
        min_lon, min_lat, max_lon, max_lat = bounds
        mid_lon = (min_lon + max_lon) / 2.0
        mid_lat = (min_lat + max_lat) / 2.0
        return (
            mid_lon if child & 1 else min_lon,
            mid_lat if child & 2 else min_lat,
            max_lon if child & 1 else mid_lon,
            max_lat if child & 2 else mid_lat,
        )

    def _center_and_corner_radius(self, bounds: tuple[float, float, float, float]) -> tuple[float, float, float]:
        min_lon, min_lat, max_lon, max_lat = bounds
        center_lat = (min_lat + max_lat) / 2.0
        center_lon = (min_lon + max_lon) / 2.0
        corners = [
            {"lat": lat, "lon": lon}
            for lat in (min_lat, max_lat)
            for lon in (min_lon, max_lon)
        ]
        center = {"lat": center_lat, "lon": center_lon}
        corner_radius = max(haversine(center, corner) for corner in corners)
        return center_lat, center_lon, corner_radius

    def _candidates(self, bounds: tuple[float, float, float, float]) -> list[int] | None:
        center_lat, center_lon, corner_radius = self._center_and_corner_radius(bounds)
        center = xyz(center_lat, center_lon)
        count = min(10, len(self.pubs))
        distances, indices = self.tree.query(center, k=count)
        if count == 1:
            distances = [distances]
            indices = [indices]
        nearest_m = metres_from_chord(float(distances[0]))
        if nearest_m - corner_radius > MAX_EMPTY_DISTANCE_M:
            return None

        tenth_m = metres_from_chord(float(distances[-1]))
        include_radius = tenth_m + 2.0 * corner_radius
        candidate_indices = self.tree.query_ball_point(center, chord_distance(include_radius))
        return sorted(int(index) for index in candidate_indices)

    def _build_node(
        self,
        root: str,
        path: str,
        bounds: tuple[float, float, float, float],
        depth: int,
    ) -> None:
        candidates = self._candidates(bounds)
        if candidates is None:
            return
        if len(candidates) > self.max_tile_pubs or depth < INDEX_PREFIX_DEPTH:
            if depth >= self.max_depth:
                raise ValueError(
                    f"Tile {root}/{path or 'root'} still has {len(candidates)} pubs "
                    f"at maximum quadtree depth {self.max_depth}; refusing to break the cap."
                )
            self._split_paths[root].append(path)
            for child in range(4):
                child_path = path + str(child)
                self._build_node(root, child_path, self.child_bounds(bounds, child), depth + 1)
            return
        self._leaf_pubs[f"{root}/{path}"] = candidates

    def build(self) -> None:
        min_lon, min_lat, max_lon, max_lat = UK_BOUNDS
        for lat_degree in range(math.floor(min_lat), math.ceil(max_lat)):
            for lon_degree in range(math.floor(min_lon), math.ceil(max_lon)):
                root = f"{lat_degree}_{lon_degree}"
                bounds = (float(lon_degree), float(lat_degree), float(lon_degree + 1), float(lat_degree + 1))
                self._root_bounds[root] = bounds
                if self._candidates(bounds) is not None:
                    self._build_node(root, "", bounds, 0)

        self.output.mkdir(parents=True, exist_ok=True)
        tiles_dir = self.output / "tiles"
        index_dir = self.output / "index"
        tiles_dir.mkdir(exist_ok=True)
        index_dir.mkdir(exist_ok=True)

        self._write_indexes(index_dir)

        for key, indices in self._leaf_pubs.items():
            root, path = key.split("/", 1)
            filename = f"p{path}.json" if path else "root.json"
            tile_path = tiles_dir / root / filename
            tile_path.parent.mkdir(parents=True, exist_ok=True)
            payload = {
                "v": 1,
                "built": self.built,
                "p": [[self.pubs[i]["name"], self.pubs[i]["lat"], self.pubs[i]["lon"], self.pubs[i]["hours"]] for i in indices],
            }
            encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            tile_path.write_bytes(encoded)
            self.tile_count += 1
            self.total_tile_size += len(encoded)
            self.largest_tile_size = max(self.largest_tile_size, len(encoded))

        self._write_site_index()
        self.validate_random_points()

    def _write_indexes(self, index_dir: Path) -> None:
        index_groups: dict[tuple[str, str], set[str]] = defaultdict(set)
        for key in self._leaf_pubs:
            root, path = key.split("/", 1)
            if len(path) >= INDEX_PREFIX_DEPTH:
                index_groups[(root, path[:INDEX_PREFIX_DEPTH])]

        for root, paths in self._split_paths.items():
            for path in paths:
                if len(path) >= INDEX_PREFIX_DEPTH:
                    index_groups[(root, path[:INDEX_PREFIX_DEPTH])].add(
                        path[INDEX_PREFIX_DEPTH:]
                    )

        for (root, prefix), split_paths in index_groups.items():
            path = index_dir / root / f"{prefix}.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            payload = json.dumps({"v": 1, "s": sorted(split_paths)}, separators=(",", ":"))
            path.write_text(payload, encoding="utf-8")
            self.index_count += 1

    def _leaf_for(self, latitude: float, longitude: float) -> list[int] | None:
        root = self.root_key(latitude, longitude)
        bounds = self._root_bounds.get(root)
        if bounds is None:
            return None
        split_paths = set(self._split_paths.get(root, []))
        path = ""
        while path in split_paths:
            child = self.child_index(latitude, longitude, bounds)
            bounds = self.child_bounds(bounds, child)
            path += str(child)
        return self._leaf_pubs.get(f"{root}/{path}")

    def validate_random_points(self) -> None:
        randomizer = random.Random(20261116)
        min_lon, min_lat, max_lon, max_lat = self.validation_bounds
        checked = 0
        attempts = 0
        while checked < self.validation_points and attempts < self.validation_points * 30:
            attempts += 1
            latitude = randomizer.uniform(min_lat, max_lat)
            longitude = randomizer.uniform(min_lon, max_lon)
            distances = self._brute_force_distances(latitude, longitude)
            if float(np.min(distances)) > MAX_EMPTY_DISTANCE_M:
                continue
            included = self._leaf_for(latitude, longitude)
            if included is None:
                raise AssertionError(f"Covered random point has no tile: {latitude},{longitude}")
            nearest_indices = np.argsort(distances)[:10]
            nearest_ids = {self.pubs[int(index)]["id"] for index in nearest_indices}
            included_ids = {self.pubs[index]["id"] for index in included}
            if not nearest_ids.issubset(included_ids):
                raise AssertionError(
                    f"Tile violates nearest-10 guarantee at {latitude},{longitude}; "
                    f"missing {sorted(nearest_ids - included_ids)}"
                )
            checked += 1
        if checked < self.validation_points:
            raise AssertionError(f"Only validated {checked} covered points; expected {self.validation_points}.")
        print(f"Nearest-10 validation: {checked} random points passed.")
        for label, latitude, longitude in self.spot_checks:
            distances = self._brute_force_distances(latitude, longitude)
            if float(np.min(distances)) > MAX_EMPTY_DISTANCE_M:
                print(f"Spot check {label}: no tile expected (no pub within 30 km).")
                continue
            included = self._leaf_for(latitude, longitude)
            if included is None:
                raise AssertionError(f"Covered spot check has no tile: {label}")
            nearest_indices = np.argsort(distances)[:10]
            nearest_ids = {self.pubs[int(index)]["id"] for index in nearest_indices}
            included_ids = {self.pubs[index]["id"] for index in included}
            if not nearest_ids.issubset(included_ids):
                raise AssertionError(f"Tile violates nearest-10 guarantee at {label}.")
            print(f"Spot check {label}: passed.")

    def _brute_force_distances(self, latitude: float, longitude: float) -> np.ndarray:
        lat_radians = math.radians(latitude)
        lon_radians = math.radians(longitude)
        delta_latitude = self.pub_latitudes - lat_radians
        delta_longitude = self.pub_longitudes - lon_radians
        haversine_values = (
            np.sin(delta_latitude / 2.0) ** 2
            + math.cos(lat_radians) * np.cos(self.pub_latitudes) * np.sin(delta_longitude / 2.0) ** 2
        )
        return 2.0 * EARTH_RADIUS_M * np.arcsin(np.sqrt(np.minimum(haversine_values, 1.0)))

    def _write_site_index(self) -> None:
        self.output.joinpath("index.html").write_text(
            f"""<!doctype html>
<html lang="en-GB">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Pub Compass data</title></head>
<body>
<main><h1>Pub Compass snapshot data</h1>
<p>Static OpenStreetMap snapshot built {self.built}. This site serves only prebuilt snapshot tiles; it does not query live map services.</p>
<p>© OpenStreetMap contributors. Data available under the Open Database License (ODbL).</p>
</main></body></html>
""",
            encoding="utf-8",
        )

    def print_stats(self) -> None:
        site_size = sum(path.stat().st_size for path in self.output.rglob("*") if path.is_file())
        index_sizes = [
            path.stat().st_size for path in (self.output / "index").rglob("*.json")
        ]
        tile_count = sum(1 for path in (self.output / "tiles").rglob("*.json"))
        print(f"Pub records after deduplication: {len(self.pubs)}")
        print(f"Tile count: {tile_count}")
        print(f"Index count: {self.index_count}")
        print(f"Largest index: {max(index_sizes, default=0)} bytes")
        print(f"Largest tile: {self.largest_tile_size} bytes")
        print(f"Total tile JSON size: {self.total_tile_size} bytes")
        print(f"Total site size: {site_size} bytes")
        if site_size > WARN_SITE_SIZE:
            print(f"Warning: site is larger than the 500 MB target ({site_size} bytes).")
        if site_size > MAX_SITE_SIZE:
            raise ValueError(f"Site exceeds GitHub Pages' 1 GB limit ({site_size} bytes).")


def load_pubs(geojson_path: Path) -> list[dict[str, Any]]:
    document = json.loads(geojson_path.read_text(encoding="utf-8"))
    features = document.get("features")
    if not isinstance(features, list):
        raise ValueError("Input must be a GeoJSON FeatureCollection.")
    pubs = [
        normalized
        for index, feature in enumerate(features)
        if (normalized := normalize_feature(feature, index)) is not None
    ]
    return deduplicate(pubs)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Osmium-exported pub GeoJSON file")
    parser.add_argument("--output", type=Path, required=True, help="Output directory for the static site")
    parser.add_argument("--built", default=dt.date.today().isoformat(), help="Snapshot build date (YYYY-MM-DD)")
    parser.add_argument("--max-depth", type=int, default=18)
    args = parser.parse_args()
    try:
        pubs = load_pubs(args.input)
        builder = TileBuilder(pubs, args.output, args.built, max_depth=args.max_depth)
        builder.build()
        builder.print_stats()
    except (OSError, ValueError, AssertionError, json.JSONDecodeError) as error:
        print(f"Tile build failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
