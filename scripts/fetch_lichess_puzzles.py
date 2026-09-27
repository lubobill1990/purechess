# /// script
# requires-python = ">=3.11"
# dependencies = ["python-chess==1.999", "zstandard==0.25.0"]
# ///
"""uv run scripts\\fetch_lichess_puzzles.py [--input local.csv.zst]

Stream the official CC0 database, stopping once every stratum is full.
The stored FEN is AFTER the opponent's setup move; `line` starts with the
solver. No engine, network access, or decompressor is needed by the app.
"""

import argparse
import csv
import hashlib
import io
import json
from contextlib import ExitStack
from pathlib import Path
from urllib.request import Request, urlopen

import chess
import zstandard

URL = "https://database.lichess.org/lichess_db_puzzle.csv.zst"
THEMES = ("mateIn1", "mateIn2", "fork", "pin", "skewer", "hangingPiece", "backRankMate")
BANDS = ("under1200", "1200-1600", "1600-2000")
ROOT = Path(__file__).resolve().parents[1]


def rating_band(rating):
    if rating < 0 or rating >= 2000:
        return None
    return BANDS[0 if rating < 1200 else 1 if rating < 1600 else 2]


def convert(row):
    board = chess.Board(row["FEN"])
    if not board.is_valid():
        raise ValueError(f'{row["PuzzleId"]}: invalid source FEN')
    moves = row["Moves"].split()
    if len(moves) < 2 or len(moves) % 2:
        raise ValueError(f'{row["PuzzleId"]}: expected setup + odd solver line')
    fen = None
    for index, uci in enumerate(moves):
        move = chess.Move.from_uci(uci)
        if move not in board.legal_moves:
            raise ValueError(f'{row["PuzzleId"]}: illegal move {uci}')
        board.push(move)
        if index == 0:
            fen = board.fen()
    themes = row["Themes"].split()
    for theme, plies in (("mateIn1", 1), ("mateIn2", 3)):
        if theme in themes and (len(moves) - 1 != plies or not board.is_checkmate()):
            raise ValueError(f'{row["PuzzleId"]}: inconsistent {theme}')
    if ("mate" in themes or "backRankMate" in themes) and not board.is_checkmate():
        raise ValueError(f'{row["PuzzleId"]}: mating line does not end in mate')
    return {
        "id": row["PuzzleId"],
        "fen": fen,
        "line": moves[1:],
        "themes": themes,
        "rating": int(row["Rating"]),
    }


def extract(rows, per_bucket):
    buckets = {(theme, band): [] for theme in THEMES for band in BANDS}
    seen = set()
    examined = 0
    for row in rows:
        examined += 1
        band = rating_band(int(row["Rating"]))
        if band is None or row["PuzzleId"] in seen:
            continue
        eligible = [
            theme for theme in THEMES
            if theme in row["Themes"].split() and len(buckets[theme, band]) < per_bucket
        ]
        if not eligible:
            continue
        # Fill rarer themes first; each source ID belongs to exactly one pack.
        theme = min(eligible, key=lambda t: (len(buckets[t, band]), THEMES.index(t)))
        buckets[theme, band].append(convert(row))
        seen.add(row["PuzzleId"])
        if all(len(items) == per_bucket for items in buckets.values()):
            return buckets, examined
    missing = {f"{t}/{b}": len(v) for (t, b), v in buckets.items() if len(v) < per_bucket}
    raise ValueError(f"Database ended before quotas were filled: {missing}")


def publish(buckets, output, source, examined):
    output.mkdir(parents=True, exist_ok=True)
    packs = []
    for (theme, band), puzzles in buckets.items():
        name = f"{theme}_{band}.json"
        content = (json.dumps(puzzles, ensure_ascii=False, indent=2) + "\n").encode()
        temp = output / f"{name}.tmp"
        temp.write_bytes(content)
        temp.replace(output / name)
        packs.append({
            "file": name, "theme": theme, "band": band, "count": len(puzzles),
            "sha256": hashlib.sha256(content).hexdigest(),
        })
    manifest = {
        "schema": 1, "source": URL, "license": "CC0-1.0",
        "sourceVersion": source, "rowsExamined": examined,
        "fenConvention": "after-setup", "total": sum(p["count"] for p in packs),
        "packs": packs,
    }
    temp = output / "manifest.json.tmp"
    temp.write_bytes((json.dumps(manifest, indent=2) + "\n").encode("utf-8"))
    temp.replace(output / "manifest.json")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="Read a previously downloaded .csv.zst")
    parser.add_argument("--output", type=Path, default=ROOT / "assets" / "puzzles")
    parser.add_argument("--per-bucket", type=int, default=50)
    args = parser.parse_args()
    if args.per_bucket < 50:
        parser.error("--per-bucket must be >= 50 (at least 1,050 unique puzzles)")
    with ExitStack() as stack:
        if args.input:
            source = stack.enter_context(args.input.open("rb"))
            version = args.input.name
        else:
            source = stack.enter_context(urlopen(Request(URL, headers={
                "User-Agent": "purechess-puzzle-import/1.0",
                "Accept-Encoding": "identity",
            }), timeout=120))
            version = source.headers.get("Last-Modified") or source.headers.get("ETag")
        reader = stack.enter_context(zstandard.ZstdDecompressor().stream_reader(source))
        text = stack.enter_context(io.TextIOWrapper(reader, encoding="utf-8", newline=""))
        buckets, examined = extract(csv.DictReader(text), args.per_bucket)
    manifest = publish(buckets, args.output, version, examined)
    for pack in manifest["packs"]:
        print(f'{pack["theme"]:16} {pack["band"]:12} {pack["count"]}')
    print(f'Total: {manifest["total"]} unique puzzles; scanned {examined} CSV rows')


if __name__ == "__main__":
    main()
