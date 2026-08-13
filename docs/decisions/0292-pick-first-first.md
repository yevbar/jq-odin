# Decision 0292: bounded nested pick(first)

Only the exact `pick(first|first)` whole-filter shape is lowered through the
existing slice and map ABIs. General path capture and `pick(last)` remain
outside this bounded contract.
