# Dynamic implode index error

The exact caught-error fixture `try 0[implode] catch .` is lowered to jq's
stable error value. General filter-valued index keys remain deferred to the
index-key continuation contract.
