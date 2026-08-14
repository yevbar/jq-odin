# Decision 0314: nested static path component lowering

`path(.a[path(.b)[0]])` is equivalent to `path(["a","b"])` for every input:
`path(.b)` always yields the static path array `["b"]`, so its index zero is
the literal field name. The driver accepts only this identifier-shaped form;
general dynamic path generators still require a resumable path-component
contract.

Evidence: `upstream/jq/tests/jq.test:1130` and
`compat/path-nested-static-component.jq.test`.
