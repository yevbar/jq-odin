# Dynamic postfix-index continuation

The parser and program ABI represent a postfix index as two operands: operand
zero is the base instruction and operand one is either owned text for a static
index or an instruction for a dynamic key generator. The evaluator retains each
base result while running the key instruction against the original parent input,
then applies every string or integral-number key result before resuming the base
generator. This preserves jq's generator cardinality without overloading object
container links in the syntax node.

The syntax node therefore owns a dedicated `index_key` child field. Static
numeric and quoted indexes retain their existing operand ABI. Dynamic key
errors are raised through the normal runtime-error continuation so `try` and
optional suppression remain observable and ownership-safe.

Evidence: `upstream/jq/src/parser.y:175-181` and
`upstream/jq/src/jv_aux.c:80-87,130-154`.
