# `first` compatibility shard

Zero-argument array selector; empty and null inputs yield null. The bounded
generator form consumes only the first output and suppresses later outputs or
errors after that first value. Broader dynamic/control forms and wrong-
container diagnostics remain deferred.

Evidence: `upstream/jq/tests/jq.test:397-410`.
