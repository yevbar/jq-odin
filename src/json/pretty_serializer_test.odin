package json

import "base:runtime"
import "core:testing"
import "jq:value"

expect_pretty_input :: proc(t: ^testing.T, input, expected: string) {
	parsed, parse_error := parse_value(input, context.allocator)
	testing.expect_value(t, parse_error.kind, Scalar_Parse_Error_Kind.None)
	defer value.destroy_value(&parsed)
	serializer: Pretty_Serializer
	testing.expect(t, init_pretty_serializer(&serializer, context.allocator))
	defer destroy_pretty_serializer(&serializer)
	result: Pretty_Result
	err := serialize_pretty(&serializer, &parsed, &result)
	testing.expect_value(t, err.kind, Compact_Error_Kind.None)
	if err.kind != .None do return
	defer destroy_pretty_result(&result)
	bytes, ok := pretty_result_bytes(&result)
	testing.expect(t, ok)
	testing.expect_value(t, bytes, expected)
}

contains_bytes :: proc(haystack, needle: string) -> bool {
	if len(needle) > len(haystack) do return false
	for at in 0..=len(haystack) - len(needle) {
		if haystack[at:at + len(needle)] == needle do return true
	}
	return false
}

@(test)
pretty_exact_default_jq_fixtures :: proc(t: ^testing.T) {
	cases := []struct {input, expected: string}{
		{"null", "null"},
		{"true", "true"},
		{"false", "false"},
		{"[]", "[]"},
		{"{}", "{}"},
		{
			`{"empty_array":[],"empty_object":{},"mix":[null,true,false,1.000,"a\u0000é",{"x":[1,2]}]}`,
			"{\n" +
			"  \"empty_array\": [],\n" +
			"  \"empty_object\": {},\n" +
			"  \"mix\": [\n" +
			"    null,\n" +
			"    true,\n" +
			"    false,\n" +
			"    1.000,\n" +
			"    \"a\\u0000é\",\n" +
			"    {\n" +
			"      \"x\": [\n" +
			"        1,\n" +
			"        2\n" +
			"      ]\n" +
			"    }\n" +
			"  ]\n" +
			"}",
		},
		{
			`{"quote\"\\":"\b\t\n\f\r\u0000\u001f\u007f/ 世界 😀","n":[-0,1e-7,1e20]}`,
			"{\n" +
			"  \"quote\\\"\\\\\": \"\\b\\t\\n\\f\\r\\u0000\\u001f\\u007f/ 世界 😀\",\n" +
			"  \"n\": [\n" +
			"    -0,\n" +
			"    1E-7,\n" +
			"    1E+20\n" +
			"  ]\n" +
			"}",
		},
	}
	for test_case in cases do expect_pretty_input(t, test_case.input, test_case.expected)
}

@(test)
pretty_source_lifetime_and_serializer_reuse_are_independent :: proc(t: ^testing.T) {
	source := make([]byte, len(`{"nul":"\u0000","unicode":"é","nested":[{},[]]}`))
	copy(source, `{"nul":"\u0000","unicode":"é","nested":[{},[]]}`)
	node, parse_error := parse_value(transmute(string)source, context.allocator)
	delete(source)
	testing.expect_value(t, parse_error.kind, Scalar_Parse_Error_Kind.None)

	serializer: Pretty_Serializer
	testing.expect(t, init_pretty_serializer(&serializer, context.allocator))
	defer destroy_pretty_serializer(&serializer)
	first: Pretty_Result
	testing.expect_value(t, serialize_pretty(&serializer, &node, &first).kind, Compact_Error_Kind.None)
	testing.expect_value(t, value.destroy_value(&node), runtime.Allocator_Error.None)
	bytes, ok := pretty_result_bytes(&first)
	expected := "{\n  \"nul\": \"\\u0000\",\n  \"unicode\": \"é\",\n  \"nested\": [\n    {},\n    []\n  ]\n}"
	testing.expect(t, ok && bytes == expected)
	testing.expect_value(t, destroy_pretty_result(&first), runtime.Allocator_Error.None)

	other := value.null_value()
	second: Pretty_Result
	testing.expect_value(t, serialize_pretty(&serializer, &other, &second).kind, Compact_Error_Kind.None)
	second_bytes, second_ok := pretty_result_bytes(&second)
	testing.expect(t, second_ok && second_bytes == "null")
	testing.expect_value(t, destroy_pretty_result(&second), runtime.Allocator_Error.None)
}

@(test)
pretty_depth_boundary_is_iterative_and_preserves_layout :: proc(t: ^testing.T) {
	depths := []int{256, 257, 10_000}
	for depth in depths {
		input := make_nested_array_text(depth, "null")
		node, parse_error := parse_value(transmute(string)input, context.allocator)
		delete(input)
		testing.expect_value(t, parse_error.kind, Scalar_Parse_Error_Kind.None)
		serializer: Pretty_Serializer
		testing.expect(t, init_pretty_serializer(&serializer, context.allocator))
		result: Pretty_Result
		err := serialize_pretty(&serializer, &node, &result)
		testing.expect_value(t, err.kind, Compact_Error_Kind.None)
		if err.kind == .None {
			bytes, ok := pretty_result_bytes(&result)
			testing.expect(t, ok)
			if depth == 256 {
				testing.expect(t, contains_bytes(bytes, "null"))
				testing.expect(t, !contains_bytes(bytes, COMPACT_DEPTH_MARKER))
			} else {
				testing.expect(t, len(bytes) > len(COMPACT_DEPTH_MARKER))
				testing.expect(t, contains_bytes(bytes, COMPACT_DEPTH_MARKER))
			}
			testing.expect_value(t, destroy_pretty_result(&result), runtime.Allocator_Error.None)
		}
		testing.expect_value(t, destroy_pretty_serializer(&serializer), runtime.Allocator_Error.None)
		testing.expect_value(t, value.destroy_value(&node), runtime.Allocator_Error.None)
	}
}

@(test)
pretty_allocation_exhaustion_and_cleanup_retry :: proc(t: ^testing.T) {
	node, parse_error := parse_value(`{"a":[1,2,3],"b":"a string long enough to exercise output growth"}`, context.allocator)
	testing.expect_value(t, parse_error.kind, Scalar_Parse_Error_Kind.None)
	defer value.destroy_value(&node)
	saw_failure := false
	saw_success := false
	for fail_after in 0..<16 {
		probe := allocator_probe{backing = context.allocator, fail_after = fail_after}
		serializer: Pretty_Serializer
		testing.expect(t, init_pretty_serializer(&serializer, probe_allocator(&probe)))
		result: Pretty_Result
		err := serialize_pretty(&serializer, &node, &result)
		if err.kind == .None {
			saw_success = true
			testing.expect_value(t, destroy_pretty_result(&result), runtime.Allocator_Error.None)
		} else {
			saw_failure = true
			testing.expect_value(t, err.kind, Compact_Error_Kind.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_pretty_serializer(&serializer), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.live, 0)
	}
	testing.expect(t, saw_failure && saw_success)

	long_bytes := make([]byte, 600)
	for i in 0..<len(long_bytes) do long_bytes[i] = 'x'
	long_node, constructor_error := value.string_value(transmute(string)long_bytes, context.allocator)
	delete(long_bytes)
	testing.expect_value(t, value.constructor_error_kind(&constructor_error), value.Error.None)
	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	retry_serializer: Pretty_Serializer
	testing.expect(t, init_pretty_serializer(&retry_serializer, probe_allocator(&retry_probe)))
	retry_result: Pretty_Result
	retry_error := serialize_pretty(&retry_serializer, &long_node, &retry_result)
	testing.expect_value(t, retry_error.kind, Compact_Error_Kind.Cleanup_Failed)
	testing.expect(t, retry_probe.live > 0)
	testing.expect_value(t, destroy_pretty_serializer(&retry_serializer), runtime.Allocator_Error.None)
	testing.expect_value(t, retry_probe.live, 0)
	testing.expect_value(t, value.destroy_value(&long_node), runtime.Allocator_Error.None)
}

@(test)
pretty_owner_move_free_retry_and_size_boundary :: proc(t: ^testing.T) {
	node := value.null_value()
	serializer: Pretty_Serializer
	testing.expect(t, init_pretty_serializer(&serializer, context.allocator))
	serializer_copy := serializer
	rejected: Pretty_Result
	testing.expect_value(
		t,
		serialize_pretty(&serializer_copy, &node, &rejected).kind,
		Compact_Error_Kind.Invalid_Serializer_Owner,
	)
	testing.expect_value(
		t,
		destroy_pretty_serializer(&serializer_copy),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	compact_owner := cast(^Compact_Serializer)&serializer
	compact_owner.output_length = max(int)
	testing.expect_value(
		t,
		append_pretty_indent(compact_owner, 1).kind,
		Compact_Error_Kind.Size_Overflow,
	)
	compact_owner.output_length = 0

	result: Pretty_Result
	testing.expect_value(t, serialize_pretty(&serializer, &node, &result).kind, Compact_Error_Kind.None)
	result_copy := result
	_, copied_ok := pretty_result_bytes(&result_copy)
	testing.expect(t, !copied_ok)
	moved: Pretty_Result
	testing.expect_value(t, take_pretty_result(&moved, &result), Compact_Error_Kind.None)
	_, old_ok := pretty_result_bytes(&result)
	moved_bytes, moved_ok := pretty_result_bytes(&moved)
	testing.expect(t, !old_ok && moved_ok && moved_bytes == "null")
	testing.expect_value(t, destroy_pretty_result(&moved), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_pretty_serializer(&serializer), runtime.Allocator_Error.None)

	probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	retry_serializer: Pretty_Serializer
	testing.expect(t, init_pretty_serializer(&retry_serializer, probe_allocator(&probe)))
	retry_result: Pretty_Result
	testing.expect_value(
		t,
		serialize_pretty(&retry_serializer, &node, &retry_result).kind,
		Compact_Error_Kind.None,
	)
	testing.expect_value(
		t,
		destroy_pretty_result(&retry_result),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	retained, retained_ok := pretty_result_bytes(&retry_result)
	testing.expect(t, retained_ok && retained == "null")
	testing.expect_value(t, destroy_pretty_result(&retry_result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_pretty_serializer(&retry_serializer), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
}
