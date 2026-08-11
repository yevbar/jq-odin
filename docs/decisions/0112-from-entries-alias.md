# Decision 0112: from_entries field aliases

The evaluator performs ordered, read-only alias lookup for each entry: key
names are `key`, `Key`, `name`, `Name`; value names are `value`, `Value`.
The first present alias is copied, preserving existing ownership and object
construction contracts. If no value alias is present, the entry value is
`null`, matching jq. Invalid shapes and duplicate-field precedence beyond this
ordered lookup remain deferred.
