# Parenthesized generator binary expressions

This shard covers binary operators around parenthesized generator expressions.
The parser must not reuse a caller-owned operator frame when reducing a
recursive `parse_pipe` invocation. Dynamic generator syntax and assignment are
outside this focused parser-safety slice.
