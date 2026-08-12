# Iterator-error catch values

The evaluator now retains jq's typed `Cannot iterate over <kind> (<value>)`
message as the caught string value. This is bounded to the existing `.[]`
iterator and does not broaden parser or continuation support.

Oracle evidence: `upstream/jq/tests/jq.test:200`.
