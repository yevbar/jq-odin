# jq in Odin experiment

This repository is the staging area for a behavior-compatible rewrite of
[jq](https://github.com/jqlang/jq) in
[Odin](https://odin-lang.org/). The compatibility strategy is to treat jq's
language-agnostic behavior and test suite as the specification.

The repository contains a marker-only Odin package skeleton and coordination
material for parallel implementation. The marker files establish dependency
boundaries but intentionally contain no jq implementation or speculative APIs.

## Baseline

- jq: `jq-1.8.1` at commit `4467af7068b1bcd7f882defff6e7ea674c5357f4`
- bundled Oniguruma: commit `4ef89209a239c1aea328cf13c05a2807e5c146d1`
- Odin: `dev-2026-05`, pinned in `.odin-version`

The jq source lives in `upstream/jq` as a Git submodule. Keep that checkout
unchanged; rewrite work will live outside it in a layout chosen in a later
pass.

## Get started

Prerequisites on macOS are the Xcode command-line tools:

```sh
xcode-select --install
```

Then install the pinned Odin release locally and verify the environment:

```sh
make bootstrap
make validate
```

The compiler is installed under the ignored `.tools/` directory. The scripts
also accept an existing `odin` on `PATH`, but `make bootstrap` is the
reproducible path for supported macOS and Linux hosts.

After cloning this repository elsewhere, restore the original source with:

```sh
git submodule update --init --recursive
```

## Documents

- [`docs/upstream-baseline.md`](docs/upstream-baseline.md) records provenance
  and the rules for updating jq.
- [`docs/odin-development.md`](docs/odin-development.md) records Odin-specific
  constraints and early design guardrails.
- [`docs/architecture/package-graph.md`](docs/architecture/package-graph.md)
  defines the initial acyclic package graph.
- [`docs/workstreams.md`](docs/workstreams.md) assigns non-overlapping paths to
  parallel agents.
- [`docs/vers-workflow.md`](docs/vers-workflow.md) describes the Git, Vers,
  pull-request, and adversarial-review loop.

Agents must read [`AGENTS.md`](AGENTS.md) before changing the repository.
