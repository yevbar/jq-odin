# Upstream jq baseline

## Pinned source

The compatibility reference is the jq `1.8.1` release:

- repository: <https://github.com/jqlang/jq>
- release: <https://github.com/jqlang/jq/releases/tag/jq-1.8.1>
- commit: `4467af7068b1bcd7f882defff6e7ea674c5357f4`
- local path: `upstream/jq`
- bundled Oniguruma commit:
  `4ef89209a239c1aea328cf13c05a2807e5c146d1`

The patch release is preferred over 1.8.0 because it includes security,
performance, portability, parser, and language-semantics fixes.

## Source policy

`upstream/jq` is an evidence source, not a workspace for the Odin rewrite.
Do not commit edits inside it. Any fixture or test adaptation needed by the
rewrite should be copied or driven from outside the submodule, with its origin
recorded.

Before changing the jq pin:

1. Record the old and new tag and full commit IDs here.
2. Read the intervening release notes for observable behavior changes.
3. Run the existing compatibility suite against both the reference jq and the
   Odin implementation.
4. Update the submodule intentionally in a dedicated change.

Useful checks:

```sh
make upstream-status
git -C upstream/jq status --short
```

The upstream repository contains licensing terms in `COPYING`. Preserve
license and attribution notices for any material copied into the rewrite.
