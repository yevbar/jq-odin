# `trunc`

This shard covers the zero-argument numeric `trunc` builtin. It follows jq's
documented numeric behavior of truncating toward zero and defers non-number
diagnostic wording.

Oracle evidence: jq exposes truncation through the native math layer at
`upstream/jq/src/libm.h:278`; numeric truncation behavior is exercised in
`upstream/jq/tests/jq.test:2167`.
