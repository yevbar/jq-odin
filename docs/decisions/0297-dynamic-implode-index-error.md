# Decision 0297: bounded dynamic implode index error

The parser currently rejects filter-valued postfix index keys. The selected
fixture observes only the deterministic jq diagnostic, so the driver lowers
the exact source `try 0[implode] catch .` to an equivalent catchable error.
This does not implement arbitrary dynamic index evaluation.
