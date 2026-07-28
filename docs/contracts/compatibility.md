# Compatibility case requirements

The harness workstream owns the eventual machine-readable schema. Every case
must be capable of recording:

- a stable ID and upstream `path:line` provenance;
- argv, stdin bytes, working directory, and relevant environment;
- expected ordered output stream;
- stdout, stderr, exit status, or signal where applicable;
- comparison mode: semantic JSON, exact bytes, diagnostic pattern, or
  crash/memory invariant;
- platform and capability labels;
- oracle version and configuration;
- explicit normalization rules.

Do not silently skip unsupported cases. Record the missing capability and
produce a visible skip with a reason.

`upstream/jq/tests/jq.test` is executed internally by jq's `--run-tests` mode
and is not by itself a candidate-independent harness. Preserve its grammar and
source provenance while building a runner that can drive two CLI executables.

