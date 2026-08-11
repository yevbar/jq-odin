# Fixed runtime diagnostic-key compatibility shard

The evaluator now retains jq's fixed runtime messages for invalid parsed
datetime arrays passed to `strftime` and non-string input passed to `trim`.
The messages survive `try ... catch .` through the existing owned runtime-key
path.
