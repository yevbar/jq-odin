# Decision 0209: UTF-8-safe negation diagnostics

Negation errors retain jq's abbreviated JSON string preview for long values.
The preview is truncated on a UTF-8 codepoint boundary and preserves the
existing owned runtime-error message path.
