# Directory-form module resolution

The jq module search path accepts both a flat module (`a.jq`) and the
directory-form fixture used by jq (`b/b.jq`). The loader probes the flat
spelling first and then `<name>/<name>.jq`, preserving ordered `-L` lookup.

Evidence: `upstream/jq/tests/jq.test:1861-1865` and fixtures under
`upstream/jq/tests/modules/b/`.
