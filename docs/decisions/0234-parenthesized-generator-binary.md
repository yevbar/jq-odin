# Decision 0234: parenthesized generator binary expressions

Recursive `parse_pipe` calls can inherit parenthesis frames belonging to their
caller. Those frames are not valid local binary/negation sentinels: reducing
against them can dereference `Node_Id(-1)` and abort the process. Use the
entry frame depth as the ownership boundary for both operator reduction and
unclosed-parenthesis checks (`src/syntax/parser.odin`). This is parser-local,
preserves existing AST/opcode contracts, and is covered by five focused jq
parity expressions plus parser regressions.
