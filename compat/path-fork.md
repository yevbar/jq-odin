# Static path fork

The path fork shard covers literal numeric comma indexes in `path(.foo[0,1])`.
The evaluator expands the existing `Fork` instruction into an ordered path
stream. Dynamic filters, slices, and computed indexes remain deferred.
