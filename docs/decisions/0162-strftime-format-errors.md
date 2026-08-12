# Decision 0162: catchable literal `strftime` format errors

The literal `strftime` slice accepts static non-string format operands through
compilation and raises a runtime error, so `try ... catch` can observe it as jq
does. This bounded case covers `strftime([])`; dynamic format expressions and
other date format directives remain deferred.

Oracle source: `upstream/jq/tests/jq.test:1839`.
