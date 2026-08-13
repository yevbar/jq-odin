# Basic strftime directives

Numeric Unix timestamps support the basic `%Y`, `%m`, and `%d` directives and
the descriptive `%A, %B %d, %Y` format. Other directives and local-time
formatting remain outside this bounded lane. The descriptive timestamp case
corresponds to `upstream/jq/tests/jq.test:1809`.
