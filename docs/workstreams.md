# Parallel workstreams

Only the integration coordinator edits this table. Each workstream has a brief
under `workstreams/` and owns complete directories to minimize merge conflicts.

| ID | Workstream | Owned paths | Depends on | Initial state |
|---|---|---|---|---|
| `facts` | Verified source facts | `evidence/**` | none | ready |
| `compat` | Differential harness | `compat/**`, `tools/compat/**` | case contract | ready |
| `value` | JSON value model | `src/value/**`, focused tests | verified ownership facts | ready for evidence/prototypes |
| `json` | JSON parser/printer/streaming | `src/json/**`, focused tests | value contract | evidence work ready |
| `language` | jq lexer/parser/AST | `src/syntax/**`, focused tests | diagnostics | ready |
| `program` | IR and compiler | `src/program/**`, `src/compiler/**`, focused tests | syntax and value contracts | evidence work ready |
| `eval` | Resumable evaluator | `src/eval/**`, focused tests | program and value contracts | prototype only |
| `specialty` | Regex, modules, codecs, time | future paths assigned by decision | harness and evaluator | inventory ready |
| `cli` | Process and CLI contract | future `src/driver/**`, `cmd/**`, CLI cases | integrated vertical slice | inventory ready |
| `integration` | Shared contracts and merge queue | root files and cross-package changes | all | coordinator only |

`src/diagnostic/**`, root build files, architecture documents, and shared
contracts remain coordinator-owned until explicitly delegated.

