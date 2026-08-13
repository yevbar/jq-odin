# Decision 0266: basic strftime directives

Extend the existing timestamp-normalization path with `%Y`, `%m`, and `%d`.
The implementation keeps the current parsed-array and numeric input contract;
other directives remain deferred pending a complete platform-time formatter.

Evidence: `upstream/jq/tests/jq.test:2420-2430`.
