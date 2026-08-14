# Decision 0331: invocation-scoped `input/0` provider

- Status: implemented in `facc7e04`
- Date: 2026-08-14
- Workstream: cli/eval integration

The `input/0` opcode now receives a provider that survives each individual
`Run_Result`. The CLI provider owns the unread framed buffer, the active file,
argv-source index, and source transition state. It refills the current source
on demand, advances across `-` and named files, and marks a source terminal on
parse failure so a caught provider error is not reported again by the outer
JSON framer.

The evaluator ABI remains dependency-safe: eval sees only the existing borrowed
callback, while `cmd/jq-odin` owns file descriptors and transfers framed text
to the evaluator for parsing. A fresh value framer is used for each provider
suffix; copying the outer `Found` framer would misparse the next scalar.

Evidence against pinned jq 1.8.1 includes same-buffer values, 4096-byte split
refill, `-n` with real stdin, argv transitions, `-` transitions, EOF `break`,
and malformed numeric literals under and outside `try`. Package checks pass;
the threaded Odin syntax test runner still has the known host Bus-error issue.

The provider currently reports the compatible numeric-literal diagnostics and
source line/path for the tested malformed cases. Broader JSON parse-error
families and injected I/O failures remain follow-up coverage, not silently
rewritten into success.
