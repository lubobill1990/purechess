# Third-party credits and release obligations

## Stockfish

The AI is [Stockfish](https://stockfishchess.org/), by the Stockfish developers.
Engine source: <https://github.com/official-stockfish/Stockfish>.
License: **GNU GPL version 3**; preserve the upstream copyright notices,
`AUTHORS`, and `Copying.txt` when distributing an engine.

Android/iOS use [`stockfish` 1.8.1](https://pub.dev/packages/stockfish),
maintained by Arjan Aswal, through its Dart/native FFI bridge:
<https://github.com/ArjanAswal/stockfish>. Treat this integration as GPLv3;
the CocoaPods metadata's MIT label is not a license exemption for Stockfish.
The package's NNUE networks are downloaded by its native build scripts and
embedded in the app, not downloaded by the user at runtime.

Desktop uses an external UCI process. Local Windows validation used the
unmodified [official Stockfish 19 release](https://github.com/official-stockfish/Stockfish/releases/tag/sf_19)
(published 2026-09-05), `stockfish-windows-x86-64-universal.zip`.
Archive SHA-256:
`3c8bf1f9ea66a09350a40df4f632288285ac206d99f33ab5842c408fc30b48a7`.
The archive includes the matching source and GPL notices. Local executable,
archive, source, and networks stay in ignored `engine_assets`; none are committed.

**Before distribution:** the maintainer must confirm a GPLv3-compatible app
licensing/source-distribution strategy, especially for the in-process mobile
integration; provide corresponding source and applicable notices for every
shipped engine/build. Process separation alone is not a blanket GPL exemption.
Verify App Store distribution terms and complete the in-app legal notices
before release. This development milestone is not legal or store approval.

## Package evaluation not shipped

[`stockfish_chess_engine` 0.8.2](https://pub.dev/packages/stockfish_chess_engine)
was evaluated but is **not** a dependency. Its source and credits are at
<https://github.com/loloof64/StockfishChessEngineFlutter>. See
`CHESS_PLAN.md` for the reproducible desktop failure that ruled it out.
