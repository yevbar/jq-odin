# Decision 0290: bounded root literal update

Only the exact scalar root-update forms covered by the focused fixture are
rewritten through `setpath([]; literal)`. This reuses the existing owned root
replacement path. General `. |= FILTER` remains unsupported until child output,
errors, and ownership can be resumed through a dedicated update frame.
