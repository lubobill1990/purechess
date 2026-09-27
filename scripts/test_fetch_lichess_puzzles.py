# /// script
# requires-python = ">=3.11"
# dependencies = ["python-chess==1.999", "zstandard==0.25.0"]
# ///
"""uv run scripts\\test_fetch_lichess_puzzles.py"""

import csv
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path

import chess
import zstandard

from fetch_lichess_puzzles import BANDS, ROOT, THEMES, convert, extract, publish, rating_band


def row(**changes):
    value = {
        "PuzzleId": "sample",
        "FEN": chess.STARTING_FEN,
        "Moves": "e2e4 e7e5 g1f3 b8c6",
        "Rating": "1000",
        "Themes": "fork",
    }
    value.update(changes)
    return value


class ImportTests(unittest.TestCase):
    def test_rating_boundaries(self):
        self.assertEqual(
            [rating_band(r) for r in (-1, 0, 1199, 1200, 1599, 1600, 1999, 2000)],
            [None, BANDS[0], BANDS[0], BANDS[1], BANDS[1], BANDS[2], BANDS[2], None],
        )

    def test_setup_is_applied_once_and_removed_from_line(self):
        puzzle = convert(row())
        board = chess.Board()
        board.push_uci("e2e4")
        self.assertEqual(puzzle["fen"], board.fen())
        self.assertEqual(puzzle["line"], ["e7e5", "g1f3", "b8c6"])
        self.assertEqual(puzzle["themes"], ["fork"])

    def test_invalid_input_is_not_silently_skipped(self):
        for changes in [
            {"FEN": "8/8/8/8/8/8/8/8 w - - 0 1"},
            {"Moves": "e2e5 e7e5"},
            {"Moves": "e2e4"},
            {"Moves": "e2e4 e7e5 g1f3"},
            {"Themes": "mateIn1"},
            {"Themes": "mateIn2"},
            {"Themes": "backRankMate"},
        ]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                convert(row(**changes))

    def test_zstd_csv_stream_and_quota_shortfall(self):
        output = io.StringIO(newline="")
        writer = csv.DictWriter(output, fieldnames=list(row()))
        writer.writeheader()
        writer.writerow(row())
        compressed = zstandard.ZstdCompressor().compress(output.getvalue().encode())
        with zstandard.ZstdDecompressor().stream_reader(io.BytesIO(compressed)) as reader:
            with io.TextIOWrapper(reader, encoding="utf-8", newline="") as text:
                with self.assertRaisesRegex(ValueError, "quotas"):
                    extract(csv.DictReader(text), 1)

    def test_publication_is_byte_identical_on_rerun(self):
        buckets = {("fork", BANDS[0]): [convert(row())]}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            first = publish(buckets, output, "fixture", 1)
            before = {p.name: p.read_bytes() for p in output.iterdir()}
            second = publish(buckets, output, "fixture", 1)
            self.assertEqual(first, second)
            self.assertEqual(before, {p.name: p.read_bytes() for p in output.iterdir()})
            self.assertTrue(all(b"\r\n" not in content for content in before.values()))

    def test_generated_assets_hashes_and_independent_chess_validation(self):
        directory = ROOT / "assets" / "puzzles"
        manifest = json.loads((directory / "manifest.json").read_text())
        self.assertGreaterEqual(manifest["total"], 1000)
        self.assertEqual(len(manifest["packs"]), len(THEMES) * len(BANDS))
        ids = set()
        for pack in manifest["packs"]:
            content = (directory / pack["file"]).read_bytes()
            self.assertEqual(hashlib.sha256(content).hexdigest(), pack["sha256"])
            puzzles = json.loads(content)
            self.assertEqual(len(puzzles), pack["count"])
            for puzzle in puzzles:
                with self.subTest(id=puzzle["id"]):
                    self.assertNotIn(puzzle["id"], ids)
                    ids.add(puzzle["id"])
                    board = chess.Board(puzzle["fen"])
                    self.assertTrue(board.is_valid())
                    self.assertEqual(rating_band(puzzle["rating"]), pack["band"])
                    self.assertIn(pack["theme"], puzzle["themes"])
                    for uci in puzzle["line"]:
                        move = chess.Move.from_uci(uci)
                        self.assertIn(move, board.legal_moves)
                        board.push(move)
                        self.assertTrue(board.is_valid())
                    if any(t in puzzle["themes"] for t in ("mate", "mateIn1", "mateIn2", "backRankMate")):
                        self.assertTrue(board.is_checkmate())
                    if "mateIn1" in puzzle["themes"]:
                        self.assertEqual(len(puzzle["line"]), 1)
                    if "mateIn2" in puzzle["themes"]:
                        self.assertEqual(len(puzzle["line"]), 3)
        self.assertEqual(len(ids), manifest["total"])


if __name__ == "__main__":
    unittest.main()
