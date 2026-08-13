# Literal pick path

The bounded whole-filter `pick(.a.b.c)` form is lowered to the existing
literal `setpath` ABI. This preserves jq's behavior of creating missing object
ancestors and storing a null leaf.
