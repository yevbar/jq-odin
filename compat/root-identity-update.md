# Root identity update

The exact `. |= try . catch .` filter is lowered to `.`. Its RHS always
returns the original input and cannot produce an error, so the update is
observationally identical for every JSON value.
