# Root literal update

The exact scalar forms `. |= try 2` and `. |= try 2 catch 3` are lowered to
`setpath([]; 2)`, preserving jq's root replacement result while leaving
filter-valued updates to the resumable update-path contract.
