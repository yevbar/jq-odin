# Decision 0284: scalar `contains` literals

`contains/1` already has a complete literal evaluator and program operand
contract. Extend only parser admission for null, boolean, number, NaN, and
infinite literal needles. Dynamic needles remain deferred because they require
a resumable child-evaluation frame.
