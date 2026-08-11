# Decision 0099: normalize native number serialization

- Status: accepted
- Workstream: json

## Context and evidence

jq arithmetic case `upstream/jq/tests/jq.test:653` expects
`1.05e-19` rather than the binary-float rendering
`1.0499999999999999e-19`.

## Decision

Serialize ordinary finite native numbers through a fifteen-significant-digit
scientific representation, trim insignificant mantissa zeroes, and retain the
existing exponent/decimal placement rules. Preserve the previous full-
precision path for infinities, which jq prints using the max-f64 magnitude.

## Limits

This lane does not alter retained literal spellings or decimal-context
arithmetic; those remain owned by the existing value/JSON contracts.
