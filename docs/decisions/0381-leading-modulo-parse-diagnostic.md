# Leading modulo parse diagnostic

The compatibility fixture `jq.test:1950` uses `%::wat` and expects jq's
source-located error:

```
jq: error: syntax error, unexpected '%', expecting end of file at <top-level>, line 1, column 1:
    %::wat
    ^
jq: 1 compile error
```

The scanner already preserves the leading `%` as `Token_Kind.Modulo`
(`src/syntax/package.odin:562-605`), and the driver carries its one-byte span
and token kind through `Run_Result` (`src/driver/package.odin:1288-1308`). The
CLI now formats this spelling only when the parse outcome is an unexpected
leading modulo with span `[0,1)`, so infix modulo expressions remain on the
normal evaluator path. Probe coverage confirms `%`, `%foo`, `%::wat`, and
`%%::wat` match jq; `1 % 2` still evaluates successfully.

This is a presentation-only boundary: no parser token or evaluator semantics
change, and malformed trailing-modulo cases such as `1 %` remain deferred to
the broader parser-diagnostic contract.
