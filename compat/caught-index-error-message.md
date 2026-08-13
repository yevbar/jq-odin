# Caught typed index errors

When a string-key index is attempted on a number inside `try`, jq exposes a
descriptive message as the caught value. The evaluator now formats that value
from the typed runtime error while preserving the compact terminal diagnostic.
