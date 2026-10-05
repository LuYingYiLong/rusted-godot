"""Fault injection for parity gates: presence, sparse sampling, and double precision."""

import csv
from pathlib import Path
import tempfile
import unittest

from compare_rw_115_unit_traces import compare, compare_teams


class TraceComparisonTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)

    def write(self, name, fields, rows, delimiter=","):
        path = self.directory / name
        with path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=fields, delimiter=delimiter)
            writer.writeheader()
            writer.writerows(rows)
        return path

    def test_missing_and_extra_units_are_failures(self):
        self.write("original-units.csv", ["frame", "id", "x"], [{"frame": 1, "id": 1, "x": 0}])
        self.write("godot.tsv", ["frame", "id", "x", "type"], [{"frame": 1, "id": 2, "x": 0, "type": "tank"}], "\t")
        result = compare(self.directory)
        self.assertEqual(result["missing_godot_unit_frames"], 1)
        self.assertEqual(result["extra_godot_unit_frames"], 1)
        self.assertIsNotNone(result["first_difference"])

    def test_unobserved_source_frames_are_not_extra_units(self):
        self.write("original-units.csv", ["frame", "id", "x"], [{"frame": 2, "id": 1, "x": 0}])
        self.write("godot.tsv", ["frame", "id", "x", "type", "order"], [
            {"frame": 1, "id": 2, "x": 0, "type": "tank", "order": ""},
            {"frame": 2, "id": 1, "x": 0, "type": "tank", "order": ""},
        ], "\t")
        result = compare(self.directory)
        self.assertEqual(result["compared_unit_frames"], 1)
        self.assertEqual(result["extra_godot_unit_frames"], 0)
        self.assertIsNone(result["first_difference"])

    def test_credit_difference_below_float_precision_is_detected(self):
        original = self.write("teams.csv", ["frame", "slot", "credits"], [{"frame": 1, "slot": 0, "credits": 4000.0}])
        actual = self.write("teams.tsv", ["frame", "slot", "credits"], [{"frame": 1, "slot": 0, "credits": 4000.000000001}], "\t")
        result = compare_teams(original, actual)
        self.assertEqual(result["compared_team_frames"], 1)
        self.assertIsNotNone(result["first_difference"])

    def test_missing_credit_record_is_detected(self):
        original = self.write("teams.csv", ["frame", "slot", "credits"], [{"frame": 1, "slot": 0, "credits": 4000.0}])
        actual = self.write("teams.tsv", ["frame", "slot", "credits"], [], "\t")
        result = compare_teams(original, actual)
        self.assertEqual(result["missing_godot_team_frames"], 1)
        self.assertIsNotNone(result["first_difference"])


    def test_later_path_node_difference_is_detected(self):
        self.write("original-units.csv", ["frame", "id", "path_points", "order"], [
            {"frame": 1, "id": 1, "path_points": "10:20|30:40", "order": "move"},
        ])
        self.write("godot.tsv", ["frame", "id", "path_points", "type", "order"], [
            {"frame": 1, "id": 1, "path_points": "10:20|30:40.000004", "type": "tank", "order": "move"},
        ], "\t")
        result = compare(self.directory)
        self.assertIn("path_points", result["first_difference"]["differences"])
        self.assertEqual(result["compared_fields"]["path_points"], 1)


    def test_path_text_precision_is_compared_as_float32(self):
        self.write("original-units.csv", ["frame", "id", "path_points", "order"], [
            {"frame": 1, "id": 1, "path_points": "0.1:20", "order": "move"},
        ])
        self.write("godot.tsv", ["frame", "id", "path_points", "type", "order"], [
            {"frame": 1, "id": 1, "path_points": "0.10000000149011612:20.0", "type": "tank", "order": "move"},
        ], "\t")
        self.assertIsNone(compare(self.directory)["first_difference"])


if __name__ == "__main__":
    unittest.main()
