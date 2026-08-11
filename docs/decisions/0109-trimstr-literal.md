# Decision 0109: literal trimstr family

The parser and compiler represent `ltrimstr("...")`, `rtrimstr("...")`, and
`trimstr("...")` as one-child instructions whose child is a string literal.
The evaluator removes the matching prefix, suffix, or both and allocates a new
string result. This keeps ownership within the existing evaluator path and
does not introduce dynamic argument or continuation contracts. Non-string and
dynamic forms remain explicitly deferred.
