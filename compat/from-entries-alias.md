# Bounded from_entries alias compatibility shard

This shard covers jq's accepted entry-field aliases (`key`/`Key`/`name`/`Name`
and `value`/`Value`) from `upstream/jq/tests/jq.test:1679`. Lowercase fields
remain preferred. An omitted value alias follows jq and defaults to `null`.
Invalid entry shapes, duplicate aliases in one object, and dynamic update
semantics remain deferred.
