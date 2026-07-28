# Value workstream

Own the logical JSON value, number, string, array, and object representation.

Before public APIs:

- classify relevant upstream ownership in `evidence/ownership/value.tsv`;
- decide how JSON null differs from an Odin union's nil state;
- demonstrate copy, clone, take, and destroy behavior;
- demonstrate object ordering and number round-trip requirements;
- add allocation-tracked tests.

This package is a root dependency. Other workstreams propose changes rather
than editing it concurrently.

