# Decision 0070: bounded string `tostring`

Status: proposed on 2026-08-11.

For string input, jq's `tostring` returns the same textual value. This lane
implements that zero-argument form as an operand-free opcode and clones the
owned string value. Other type formatting and diagnostics remain deferred; no
continuation or shared contract is introduced.
