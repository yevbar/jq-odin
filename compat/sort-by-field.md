# Bounded sort_by field

The driver lowers whole-filter `sort_by(.field)` calls into
`map([.field,.]) | sort_by_key | map(.[1])`. The dedicated compiler/program
opcode compares only the materialized key and keeps insertion order for equal
keys, preserving jq's stable scalar-key ordering. General key filters and
group/min/max variants remain deferred until a key-stream materialization
contract exists.
