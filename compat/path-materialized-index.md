# Materialized map/select path index diagnostic

The bounded `path(.a | map(select(.b == 0)) | .[0])` shape now preserves jq's
catchable diagnostic after materializing the filtered array.
