# Static nested assignment

The parser lowers a bounded static field/index chain with a scalar literal RHS
to the existing `setpath` instruction. This reuses the evaluator's owned
copy-on-write path mutation and catchable diagnostics without admitting dynamic
indices or filter-valued updates.
