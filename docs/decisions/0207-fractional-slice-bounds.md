# Decision 0207: fractional slice bounds

Fractional slice starts use floor and fractional slice ends use ceil, matching
jq's array slicing behavior. Bounds are then clamped using existing semantics.
