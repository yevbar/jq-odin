# Decision 0251: bounded defined-or

Add an append-only `Defined_Or` opcode and reuse the existing binary
continuation frame. The left stream is truth-tested per output: null/false
values select the right stream, while truthy values are emitted directly.
This preserves ownership without a new frame type. Error suppression with
defined-or, broader generator streams, and assignment/update compositions
remain subject to precedence/continuation/path follow-up.
