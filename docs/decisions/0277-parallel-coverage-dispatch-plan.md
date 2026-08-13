# Parallel coverage dispatch plan

## Baseline

The current integration head measures 414/522 selected jq compatibility cases,
with 108 failures and zero harness errors. The compatibility runner and full
`make validate` gate are green at this head. The remaining failures cluster by
contract rather than by isolated spelling:

| Lane | Main cases | Contract owner | Disposition |
| --- | --- | --- | --- |
| module metadata and diagnostics | 1896–1950 | specialty/cli | bounded metadata probe first; no parser-only rewrite |
| repeated `elif` and source diagnostics | 1301, 1333, 1337, 1431 | language/eval | parser and catch-value review separately |
| labels/break and foreach extractors | 315–345, 2243, 2255 | language/program/eval | one shared AST/IR proposal before implementation |
| dynamic updates and slice assignment | 474–490, 1216+, 2194, 2437–2441 | language/program/eval/value | contract-first; preserve copy-on-write ownership |
| nested definitions and parameterized calls | 775, 789, 864, 875 | specialty/language/program/eval | call-frame work only; reject textual-expansion shortcuts |
| grouping and key-based builtins | 1639, 1655, 1659 | specialty/eval | materialization and ordering review before lowering |
| module data/import paths | 1862–1872 | specialty/cli | retain recursive alias ownership through expansion |
| dynamic stream builtins | any/all, contains, trimstr, walk, INDEX/JOIN/IN | eval/specialty | each requires an explicit child-continuation or materialization contract |

## Dispatch rules

Each implementation VM owns one lane and one feature branch. It must produce a
focused oracle shard, `make validate`, a clean commit, and a handoff listing
known unsupported forms. A separate fresh VM performs semantic-parity and
Odin-ownership adversarial review against the net diff before integration.

Do not dispatch two agents that edit the same package contract concurrently.
Parser/program/evaluator changes therefore proceed in dependency order:

1. facts/fixture probes and decision record;
2. syntax and program ABI;
3. evaluator ownership/continuation implementation;
4. CLI/module wiring;
5. adversarial review and integration measurement.

The watchdog remains authoritative for project workers. It enforces a cap of
16 registered project VMs, removes running workers older than six hours (up to
three per run), and retires paused/deleted registry entries. Before dispatch,
run `scripts/vers/vm-watchdog.sh`; after completion, unregister or delete the
worker and run the watchdog again.

## First wave

The first parallel wave is intentionally low-conflict:

- specialty: module metadata inventory with a narrow `modulemeta` contract;
- language: repeated-`elif` parser/evidence shard, with no evaluator rewrite;
- eval: adversarial review of the existing bounded stream materializers and
  dynamic update ownership, not a new feature implementation.

The coordinator then selects at most one shared-contract lane (labels/foreach,
updates/slices, or call frames) for a second wave based on evidence. This keeps
coverage growth measurable while preventing incompatible AST/Program ABIs from
landing in parallel.
