#!/bin/sh
set -eu

if output="$("$1" check "$2/src/value/external_boundary_test/forge_compile_fail" \
	-no-entry-point -collection:jq="$2/src" -vet -warnings-as-errors 2>&1)"; then
	echo "external Value storage forgery unexpectedly compiled" >&2
	exit 1
fi

expected="'Value_Handle' is not exported by 'value'"
case "$output" in
	*"$expected"*) ;;
	*)
		echo "external Value storage forgery failed with an unexpected diagnostic" >&2
		echo "$output" >&2
		exit 1
		;;
esac
