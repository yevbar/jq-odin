# Decision 0075: bounded `utf8bytelength` builtin

`utf8bytelength` is a zero-argument filter that accepts a string and returns
the number of bytes in its UTF-8 representation. It intentionally differs
from jq's codepoint-oriented `length` for multibyte text.

The syntax and program discriminants are appended to preserve existing
serialized forms. This lane covers ordinary valid strings only; non-string
diagnostics and malformed byte input remain deferred. The focused evidence
shard is `compat/utf8bytelength.jq.test`.
