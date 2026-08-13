# Arithmetic range bounds

The parser/compiler/evaluator already lower literal arithmetic expressions in
`range(-99/2;99/2;1)` into numeric bounds. A focused compatibility fixture
records this end-to-end behavior. The larger upstream probe additionally
requires unsupported `keys`/binding composition and remains outside this
decision.
