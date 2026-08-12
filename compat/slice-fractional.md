# Fractional slice bounds

Array and string slice bounds follow jq's asymmetric rounding: starts are
floored and ends are ceiled before clamping and negative-index adjustment.

Oracle evidence: `upstream/jq/tests/jq.test:2393-2397`.
