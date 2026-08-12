# Lowercase NaN JSON input

The CLI accepts the payload-free lowercase `nan` spelling as a root, array,
or object JSON input number. Compact JSON output renders the resulting native
NaN as `null`, including through the pinned catalog's `tojson | fromjson`
composition.

The same framing correction lets the existing caught `implode` evaluator path
consume `[nan]`, covering the second catalog case at
`upstream/jq/tests/jq.test:2365-2367` without changing evaluator semantics.

Oracle sources: `upstream/jq/src/jv_parse.c:506-545` routes an `n` token to
`null` only when its second byte is `u`, otherwise validating it as a number;
`upstream/jq/tests/jq.test:2271-2279` supplies the direct catalog regression.

Uppercase/signed NaN spellings, zero-payload suffixes, infinities, arbitrary
jq/decNumber spellings, and payload-error diagnostics remain outside this
focused CLI-framing slice.
