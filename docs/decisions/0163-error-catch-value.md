# Decision 0163: preserve bare-error catch values

When a bare `error` filter raises inside a catchable context, jq supplies the
original input value to the catch filter. The evaluator now retains an owned
clone of that value for the catch boundary; message-bearing `error("text")`
continues to supply the error string. This covers the upstream object-stream
regression at `upstream/jq/tests/jq.test:205`.

Dynamic error expressions and broader try/catch forms remain deferred.
