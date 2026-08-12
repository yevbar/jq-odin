# Literal `strftime` array compatibility shard

This bounded lane supports the UTC format `%Y-%m-%dT%H:%M:%SZ` for parsed
datetime arrays (including jq's default-zero omitted fields, including short
arrays), plus the
named format `%A, %B %d, %Y` for numeric UTC timestamps. The UTC harness also
supports the corresponding literal `strflocaltime` format. Other format
directives, `strptime`, and `mktime` remain deferred.
