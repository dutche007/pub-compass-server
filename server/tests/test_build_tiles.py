import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from build_tiles import TileBuilder, deduplicate, normalize_feature


class TileBuilderTests(unittest.TestCase):
    def test_quadtree_quadrants_are_stable_at_boundaries(self):
        bounds = (0.0, 0.0, 1.0, 1.0)
        self.assertEqual(TileBuilder.child_index(0.25, 0.25, bounds), 0)
        self.assertEqual(TileBuilder.child_index(0.25, 0.75, bounds), 1)
        self.assertEqual(TileBuilder.child_index(0.75, 0.25, bounds), 2)
        self.assertEqual(TileBuilder.child_index(0.75, 0.75, bounds), 3)
        self.assertEqual(TileBuilder.child_index(0.5, 0.5, bounds), 3)

    def test_normalizes_polygon_to_centroid_and_keeps_raw_hours(self):
        feature = {
            "type": "Feature",
            "properties": {"@type": "way", "@id": 42, "tags": {
                "amenity": "pub", "name": "The Red Lion", "opening_hours": "Mo-Su 11:00-23:00"
            }},
            "geometry": {"type": "Polygon", "coordinates": [[
                [-1.0, 52.0], [-0.999, 52.0], [-0.999, 52.001], [-1.0, 52.001], [-1.0, 52.0]
            ]]},
        }
        pub = normalize_feature(feature, 0)
        self.assertIsNotNone(pub)
        self.assertAlmostEqual(pub["lat"], 52.0005)
        self.assertAlmostEqual(pub["lon"], -0.9995)
        self.assertEqual(pub["hours"], "Mo-Su 11:00-23:00")

    def test_deduplicates_same_name_point_and_building_within_30_metres(self):
        pubs = [
            {"id": "node/1", "name": "The Fox", "lat": 51.5, "lon": -0.1, "hours": None, "kind": "node"},
            {"id": "way/2", "name": "The Fox", "lat": 51.5001, "lon": -0.1, "hours": None, "kind": "way"},
            {"id": "node/3", "name": "The Fox", "lat": 51.501, "lon": -0.1, "hours": None, "kind": "node"},
        ]
        self.assertEqual([pub["id"] for pub in deduplicate(pubs)], ["node/1", "node/3"])

    def test_quadtree_tile_covers_nearest_ten_and_stays_within_cap(self):
        pubs = [
            {"id": f"node/{i}", "name": str(i), "lat": 51.5 + i * 0.00002, "lon": -0.1, "hours": None}
            for i in range(50)
        ]
        with tempfile.TemporaryDirectory() as directory:
            builder = TileBuilder(pubs, Path(directory), "2026-11-18", validation_points=0)
            root = "51_-1"
            root_bounds = (-0.101, 51.499, -0.099, 51.502)
            builder._root_bounds[root] = root_bounds
            builder._build_node(root, "", root_bounds, 0)
            included = builder._leaf_for(51.5, -0.1)
            self.assertIsNotNone(included)
            self.assertLessEqual(len(included), 40)
            nearest = builder.tree.query(
                builder.points[0], k=10
            )[1]
            self.assertTrue({pubs[int(index)]["id"] for index in nearest}.issubset(
                {pubs[index]["id"] for index in included}
            ))

    def test_index_reports_split_prefixes_for_adaptive_tiles(self):
        pubs = [
            {"id": f"node/{i}", "name": str(i), "lat": 52.05 + i * 0.00002, "lon": 1.15, "hours": None}
            for i in range(50)
        ]
        with tempfile.TemporaryDirectory() as directory:
            builder = TileBuilder(pubs, Path(directory), "2026-11-18", validation_points=0)
            root = "52_1"
            root_bounds = (1.149, 52.049, 1.151, 52.052)
            builder._root_bounds[root] = root_bounds
            builder._build_node(root, "", root_bounds, 0)
            self.assertTrue(builder._split_paths[root])

    def test_small_dataset_writes_compact_tile_and_root_index(self):
        pubs = [
            {"id": f"node/{i}", "name": f"Pub {i}", "lat": 52.05 + i * 0.001, "lon": 1.15, "hours": None}
            for i in range(12)
        ]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            builder = TileBuilder(
                pubs,
                output,
                "2026-11-18",
                validation_points=50,
                validation_bounds=(1.14, 52.04, 1.16, 52.07),
                spot_checks=(),
            )
            builder.build()
            prefix = builder.prefix_path(52.05, 1.15)
            index_path = output / "index" / "52_1" / f"{prefix}.txt"
            index = index_path.read_text(encoding="utf-8").splitlines()
            tile = (output / "tiles" / "52_1" / f"p{prefix}.txt").read_text(encoding="utf-8").splitlines()
            self.assertEqual(index[:2], ["I1", "0"])
            self.assertEqual(tile[:3], ["T1", "2026-11-18", "12"])
            self.assertEqual(len(tile[3:]), 12)
            self.assertEqual(tile[3].split("\t"), ["Pub 0", "520500000", "11500000", ""])
            self.assertLess(index_path.stat().st_size, 100)

    def test_dense_cell_index_contains_only_relative_splits(self):
        pubs = [
            {"id": f"node/{i}", "name": f"Pub {i}", "lat": 52.05 + i * 0.00002, "lon": 1.15, "hours": None}
            for i in range(12)
        ]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            builder = TileBuilder(
                pubs,
                output,
                "2026-11-18",
                validation_points=0,
                validation_bounds=(1.14, 52.04, 1.16, 52.07),
                spot_checks=(),
            )
            prefix = builder.prefix_path(52.05, 1.15)
            builder._leaf_pubs = {f"52_1/{prefix}": list(range(len(pubs)))}
            builder._split_paths["52_1"] = ["", "0", prefix, prefix + "2", prefix + "23"]
            index_dir = output / "index"
            index_dir.mkdir()
            builder._write_indexes(index_dir)
            index_path = output / "index" / "52_1" / f"{prefix}.txt"
            index = index_path.read_text(encoding="utf-8").splitlines()
            self.assertEqual(index[:2], ["I1", "3"])
            self.assertEqual(index[2:5], ["", "2", "23"])
            self.assertLess(index_path.stat().st_size, 2000)


if __name__ == "__main__":
    unittest.main()
