# Decision 0184: preserve signed-infinity modulo conversion

The value arithmetic layer handles pairs of infinite binary64 operands before
integer conversion, matching jq's signed C conversion and remainder results.
Finite modulo behavior remains unchanged.
