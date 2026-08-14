# Filter-valued static field update

The exact `.sum = add(.arr[])` form lowers to `. + {sum: add(.arr[])}`.
Existing object-add and constructor continuations evaluate the RHS against the
original object and preserve jq's errors before mutation for non-object inputs.
