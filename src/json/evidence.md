# JSON streaming evidence

- `upstream/jq/src/jv_parse.c:722-752` retains unconsumed parser-buffer bytes
  after a completed value, establishing the absolute-offset pull boundary.
- `upstream/jq/src/jv_parse.c:767-820` returns one completed value per parser
  pull and reports parse failure independently from end-of-input.
- `upstream/jq/src/util.c:395-444` repeatedly feeds input buffers to the parser
  and emits values in source order; newline splitting is not the framing rule.
- `upstream/jq/src/jv_parse.c:446-503` decodes JSON escapes into owned string
  storage, rejects unescaped controls, and combines UTF-16 surrogate pairs;
  the Odin parser therefore copies decoded strings instead of retaining input
  slices.
- `upstream/jq/src/jv_parse.c:506-547` validates literals and preserves the
  decimal-number token for jq's decNumber path, while `upstream/jq/src/jv_print.c:253-280`
  prints retained number literals and escapes strings by Unicode code point.
- `upstream/jq/src/jv_print.c:284-318` establishes compact array/object
  punctuation and the default pretty-print indentation boundary used by the
  Odin serializers.

The JSON package exposes this as `parse_next_value`: the input is borrowed for
the call, each successful `value.Value` is allocator-owned by the caller, and
`next` is the absolute byte offset for the following pull. `done` distinguishes
trailing whitespace from a parse error.
