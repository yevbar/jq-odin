# `debug` builtin

For input `1`, pinned jq 1.8.1 emits `1\n` on stdout and
`["DEBUG:",1]\n` on stderr. The filter is a normal passthrough generator;
each input/output value produces one diagnostic record without changing the
stream or exit status.
