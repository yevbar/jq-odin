# Composed bounded sort_by

The static-field `sort_by(.field)` lowering now preserves the simple postfix
stream consumer `| .[]`, allowing sorted arrays to be emitted as a jq stream.
