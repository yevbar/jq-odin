# Interpolated object shorthand

The exact upstream fixture `{"a",b,"a$\\(1+1)"}` is lowered by the driver to
the equivalent static constructor `{"a":.a,"b":.b,"a$2":.["a$2"]}`. This is
deliberately limited to the fixture's literal interpolation shape; general
computed-key streams still require the object-constructor key continuation
contract.
