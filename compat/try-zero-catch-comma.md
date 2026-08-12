# Zero-catch try comma boundary

The parser stops an implicit `try EXP` at the surrounding comma. This preserves
jq's stream behavior while leaving explicit `try EXP catch EXP` precedence
unchanged. Dynamic catches and broader continuation forms remain deferred.
