# Parenthesized static field assignment

The parser unwraps only transparent parenthesized RHS nodes for the existing
static scalar assignment contract, so `try (.foo = 9) catch .` reaches the
existing owned object update evaluator. Dynamic/path-composed assignment remains
out of scope.
