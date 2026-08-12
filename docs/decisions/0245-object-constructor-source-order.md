# Decision 0245: static object constructor source order

Object constructor emission now detects the all-static-key case and emits keys
in source order, with the later value stream as the least-significant Cartesian
dimension. Computed-key constructors retain their existing continuation path;
duplicate-key replacement and dynamic assignment remain deferred.
