# Parallel development rules

Read `README.md`, `docs/odin-development.md`,
`docs/architecture/package-graph.md`, `docs/workstreams.md`, and the assigned
workstream brief before editing.

## Source of truth

- `upstream/jq/**` is immutable reference material. Never edit it.
- Observable jq 1.8.1 behavior and compatibility fixtures are the
  specification.
- Cite source facts as `path:line` in the assigned evidence shard.
- Odin package boundaries follow directories. Do not add a package or import
  edge without checking the documented graph.
- Preserve the ownership conventions in `docs/contracts/ownership.md`.

## Branch and workspace isolation

- In a dedicated Vers VM or Git worktree, create
  `agent/<workstream>/<short-task>` from the current integration base.
- One feature branch owns one narrowly reviewable outcome.
- Do not mix formatter churn, refactors, or unrelated fixes into the branch.
- Never merge your own pull request.
- In a shared worktree, do not switch branches, stage, commit, clean, reset, or
  revert unless the coordinator explicitly assigns integration work.
- Never overwrite another agent's uncommitted changes.

## Work ownership

- Edit only paths assigned to the workstream in `docs/workstreams.md`.
- Reading any path is allowed.
- The coordinator owns root build files, cross-package contracts, the package
  graph, and the workstream table unless a task delegates them.
- Propose shared changes in the branch handoff instead of silently duplicating
  a type or editing another workstream's package.

## Shared contracts

Shared contracts include public types and procedures, value ownership, AST and
program forms, evaluator result/error states, fixture schemas, import edges,
and root build commands.

Before changing one:

1. Record a decision under `docs/decisions/`.
2. Identify affected packages and owners.
3. Update direct consumers and focused tests together, or document the
   sequencing requirement.
4. Run `make validate`.

## Author validation

Run the narrowest relevant test first, followed by:

```sh
make validate
```

When a compatibility runner exists, run the assigned compatibility shard
against both the pinned jq oracle and the Odin candidate. Never claim an
unexecuted check passed.

## Adversarial review

The author agent may self-check but may not satisfy the adversarial-review
gate. Reviewer agents:

- start in a fresh VM from the clean golden snapshot;
- check out the pull-request commit;
- do not inherit or read the author's agent session;
- do not edit the author's branch;
- attempt to falsify correctness using the prompts in `reviews/prompts/`;
- cite concrete files, lines, jq fixtures, and reproduction commands;
- submit findings as pull-request reviews.

At least two independent lanes are required for behavior-changing work:
semantic parity and Odin ownership/safety. High-risk evaluator, parser, number,
regex, and process-I/O changes also require the test-gap lane.

## Handoff

Every author handoff or pull request reports:

- workstream and task;
- files changed;
- evidence and decisions added;
- commands run and their results;
- ownership or shared-contract effects;
- known failures and incomplete behavior;
- suggested adversarial-review lanes.

