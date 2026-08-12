# Implicit `try` suppression

The parser accepts zero-catch `try EXP` and lowers it to the existing `Try`
opcode with an `empty` catch branch. This covers static error suppression;
stream composition, defined-or, and dynamic catch expressions remain deferred.

Evidence: `upstream/jq/tests/jq.test:1447-1451`.
