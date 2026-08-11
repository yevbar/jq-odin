# Decision 0186: retain binary type-error messages

Failed `+` and `-` operations now carry an owned jq-style message through the
existing `User_Error` transport, allowing both terminal CLI output and catch
filters to observe the same text. Operand rendering is bounded to the existing
11-character jq truncation convention.
