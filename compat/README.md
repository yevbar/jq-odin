# Differential compatibility harness

This directory will contain the language-agnostic oracle/candidate runner and
case manifests. It begins empty by design; the `compat` workstream owns its
schema and implementation.

Reference surfaces:

- core language: `upstream/jq/tests/jq.test`
- process and CLI: `upstream/jq/tests/shtest`
- regex: `upstream/jq/tests/onig.test` and `manonig.test`
- documentation cases: `upstream/jq/tests/man.test`
- codecs: `upstream/jq/tests/base64.test` and `uri.test`
- modules: `upstream/jq/tests/modules/`
- robustness: `upstream/jq/tests/torture/`, `utf8test`, and fuzz targets

Fixtures remain in the immutable submodule unless a copied fixture has a
recorded provenance and license reason.

