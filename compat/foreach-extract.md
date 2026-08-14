# Three-clause foreach extraction

The pinned jq behavior at `upstream/jq/tests/jq.test:2255` defines
`foreach EXP as $x (INIT; UPDATE; EXTRACT)`: each generator value updates the
accumulator, then EXTRACT runs against that post-update accumulator and emits
its result. The evaluator retains the existing explicit state-machine stream
for the generator and accumulator, materializing only the bounded arithmetic
extractor forms covered here (`.` and `.*number`). The jq.test:2255 form also
uses a literal binding in `INIT` (`1 as $catch | $catch - 1`); that scalar seed
shape is lowered explicitly before the update loop. The optional extractor is a
fourth instruction child before the binding-name text operand; legacy two-clause
foreach keeps its existing four-operand layout.
