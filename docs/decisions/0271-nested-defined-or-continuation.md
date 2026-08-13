# Nested defined-or continuation

Defined-or is stream-valued: null/false outputs from the left generator are
suppressed, while truthy outputs pass through. The right generator is selected
only after the left stream exhausts without a defined output. This preserves
the jq fixture `[.[] | [.foo[] // .bar]]` (`upstream/jq/tests/jq.test:1353-1356`).
