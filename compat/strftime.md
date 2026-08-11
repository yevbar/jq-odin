# Literal `strftime` array compatibility shard

This bounded lane supports the UTC format `%Y-%m-%dT%H:%M:%SZ` for parsed
datetime arrays (including jq's default-zero omitted time fields). Numeric
timestamps, other format directives, `strflocaltime`, `strptime`, and `mktime`
remain deferred.
