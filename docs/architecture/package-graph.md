# Initial package graph

The first packages are intentionally small and acyclic:

```text
diagnostic        value
     │           ╱  │  ╲
     │          ╱   │   ╲
   syntax     json  program
      ╲             ╱   ╲
       ╲           ╱     eval
        compiler───
```

The exact import edges are:

- `diagnostic`: imports no project package.
- `value`: imports no project package.
- `json`: may import `value` and `diagnostic`.
- `syntax`: may import `diagnostic`, but not `value`.
- `program`: may import `value` and `diagnostic`.
- `compiler`: may import `syntax`, `program`, `value`, and `diagnostic`.
- `eval`: may import `program`, `value`, and `diagnostic`; it must not import
  `compiler`.

The syntax tree keeps source-level JSON literals rather than runtime `Value`
objects. This prevents the parser from depending on runtime ownership.

A future driver package may join JSON parsing, compilation, and evaluation.
The CLI will be a leaf above that driver. Neither is created as an Odin package
yet because their public dependencies do not exist.

Do not create generic `common` or `util` packages. Do not split builtins,
regular expressions, modules, or I/O into packages until their dependency
direction has been demonstrated by an implementation slice and recorded as a
decision.

