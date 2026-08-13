# Decision 0277: preserve unary negation on reduce generators

The bounded Reduce evaluator path previously treated `-.[]` as `.[]`,
silently dropping the generator's Negate wrapper. It now recognizes Negate
around the identity Field iterator and applies numeric negation per yielded
item. Other generator filters continue through the existing unsupported path.
