# Decision 0147: narrow native number normalization

The broad native-number precision change from decision 0140 caused three
previously passing jq catalog cases (`upstream/jq/tests/jq.test:2169,2173,2177`)
to emit values two units low in the final decimal digits. We narrow the
normalization to tiny native magnitudes only and remove the log(2)/log(10)
serializer fixtures until a math-result-specific shortest-float contract is
available.

This restores the catalog baseline while preserving the earlier tiny-exponent
fix. The remaining native-libm last-digit caveat is documented in the coverage
ledger and remains a follow-up target.
