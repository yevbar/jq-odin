# Vers VM preparation lifecycle incident

Status: accepted operational finding (2026-08-13)

## Observation

Two independent `handle-task` launches reached the same boundary: `vers
run-commit` reported a VM started successfully, but the VM disappeared before
the first preparation operation could inspect or execute on it. The latest
reproduction used VM `7c9b337a-806f-45ca-b8d8-77365e3b8224`; preparation
reported `VM not found` while uploading `prepare-vm.sh`. The earlier incident
used VM `291321b5-7e46-44ed-875f-e0f960c139fb`.

## Disposition

- Treat this as a Vers lifecycle/backend incident, not an author failure.
- Do not retry the same task repeatedly or claim implementation/review work
  completed when the VM vanishes before preparation.
- Preserve the VM identifier and launcher output for the Vers operator.
- Let `scripts/vers/vm-watchdog.sh` reconcile missing registry rows; it must
  not delete unrelated available inventory.
- Keep the project cap at 16 and stale threshold at 360 minutes until the
  backend lifecycle is stable.

## Current evidence

The watchdog test matrix passes, and live reconciliation reports
`project running=1 cap=16 stale=0 deleted=0`. The available-VM list is not a
worker registry and must not be interpreted as 21 active project workers.
No repository diff, VM checkpoint, or COWFS/backend artifact demonstrates a
backend code change; therefore no backend/COWFS commit is included here.

## Resume criteria

Retry author and fresh adversarial-review VMs only after a `run-commit` VM
survives status, copy, and execute checks long enough to complete preparation.
Use separate VMs for author and reviewer, and retain the exact PR-head
assessment before integration.
