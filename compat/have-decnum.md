# Decimal feature flag

The operand-free `have_decnum` feature flag is a compile-time boolean in jq.
This build uses the decimal-preserving value representation, so it lowers to
the existing Boolean literal `true` path.
