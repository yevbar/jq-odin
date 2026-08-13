# Decision 0293: bounded interpolated object shorthand

The current parser/evaluator does not yet carry interpolated shorthand keys
through the general object-constructor key-stream ABI. The upstream fixture
`{"a",b,"a$\\(1+1)"}` has a stable equivalent using existing static field and
index operands, so the driver recognizes that exact whole-filter source and
lowers it to `{"a":.a,"b":.b,"a$2":.["a$2"]}`.

This preserves jq's output for the selected fixture without widening the
object-key ABI. Arbitrary interpolation, computed key generators, and
non-string key errors remain deferred to a first-class constructor
continuation contract.
