# Decision 0282: preserve caught typed index messages

`Cannot_Index_With_String` carries the input kind and key separately so
uncaught CLI diagnostics can use the existing driver formatter. During `try`
suppression, the evaluator materializes jq's descriptive message (`Cannot
index number with string "a"`) before entering the catch continuation.
