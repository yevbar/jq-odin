# Builtins inventory

The operand-free `builtins` filter returns jq's builtin name/arity inventory as
an owned array. The implementation keeps the inventory explicit and ordered,
matching jq 1.8.1's observable output.
