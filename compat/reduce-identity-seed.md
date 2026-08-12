# Identity reducer seed

Reducers accept `.` as an identity seed and preserve the input when the
update expression is also identity.

Oracle evidence: `upstream/jq/tests/jq.test:915`.
