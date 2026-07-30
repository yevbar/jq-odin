# Compatibility tools

- `build-oracle.sh` archives the pinned jq and Oniguruma commits into a fresh
  randomized directory under ignored `.tools/` storage, builds jq 1.8.1
  there, and leaves the submodules clean. It never reuses a cached binary.
- `jq_compat.py` parses `jq.test`, executes explicit oracle and candidate
  paths, compares observable process behavior, supports deterministic shards,
  and emits reproducible text and JSON reports.

The runner rejects an oracle whose `--version` is not exactly `jq-1.8.1`
unless `--allow-unpinned-oracle` is supplied for harness self-tests.
