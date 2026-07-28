# Verified evidence

Evidence is sharded by workstream to avoid concurrent edits.

Claim columns:

```text
id	area	claim	source_path	source_lines	author	reviewer_1	reviewer_2	status
```

Ownership columns:

```text
id	c_type	field	class	owner	release_rule	source_path	source_lines	author	reviewer_1	reviewer_2	status
```

Valid status progression is `proposed`, `disputed`, or `accepted`. Acceptance
requires two independent reviewers and source-line evidence. Use one physical
TSV line per record; escape tabs and newlines in prose.

