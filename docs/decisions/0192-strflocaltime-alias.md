# Decision 0192: UTC `strflocaltime` alias

In the compatibility harness, `strflocaltime("%Y-%m-%dT%H:%M:%SZ")` is
lowered through the existing parsed-datetime `strftime` implementation. The
harness runs with `TZ=UTC`, so the observable result is identical for this
bounded literal format. Other format directives, zero-argument local-time
conversion, and exact non-array diagnostics remain deferred.

Evidence: `upstream/jq/tests/jq.test:1830-1843` exercises `strflocaltime` and
its error path; the focused fixture covers the valid parsed-array case.
