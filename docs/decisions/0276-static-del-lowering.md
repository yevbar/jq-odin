# Decision 0276: lower bounded static `del` through `delpaths`

`delpaths` already owns literal path validation and copy-on-write deletion.
Static `del(.field)`, `del(.[N])`, and `del(.field[N])` therefore lower to its
existing nested array representation instead of introducing another mutation
opcode. Dynamic path streams, slices, and comma generators require resumable
path continuation and remain deferred.

Evidence: `upstream/jq/tests/jq.test` deletion cases around lines 474 and
1168-1175; focused compatibility fixture `compat/static-del.jq.test`.
