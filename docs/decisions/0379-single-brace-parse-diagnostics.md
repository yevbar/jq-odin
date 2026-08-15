# Single-brace parse diagnostics

Status: implemented bounded slice (2026-08-15)

The pinned jq oracle reports source-located diagnostics for the one-character
filters `{` and `}` (jq.test:2033 and :2039). The existing parser already
retains the distinction between unexpected end-of-input and a lexical invalid
character, including exact spans. This slice formats those two single-error
cases in the CLI and leaves parser recovery and multi-diagnostic expressions
(notably `{1+2:3}`) deferred.

Validation: driver span tests, Odin package checks, CLI build, and direct
pinned-jq stderr probes for both filters.
