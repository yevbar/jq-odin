package json

import "base:runtime"
import "core:math"
import "core:testing"
import "jq:value"

expect_compact_input :: proc(t: ^testing.T, input, expected: string) {
	parsed, parse_error := parse_value(input, context.allocator)
	testing.expect_value(t, parse_error.kind, Scalar_Parse_Error_Kind.None)
	defer value.destroy_value(&parsed)
	serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&serializer, context.allocator))
	defer destroy_compact_serializer(&serializer)
	result: Compact_Result
	err := serialize_compact(&serializer, &parsed, &result)
	testing.expect_value(t, err.kind, Compact_Error_Kind.None)
	if err.kind != .None do return
	defer destroy_compact_result(&result)
	bytes, ok := compact_result_bytes(&result)
	testing.expect(t, ok)
	testing.expect_value(t, bytes, expected)
}

expect_compact_literal_context :: proc(
	t: ^testing.T,
	input, expected: string,
	precision, etiny: i64,
	emax := i64(999_999_999),
) {
	serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&serializer, context.allocator))
	err := append_literal_number_with_context(
		&serializer,
		input,
		precision,
		etiny,
		emax,
	)
	testing.expect_value(t, err.kind, Compact_Error_Kind.None)
	if err.kind == .None {
		bytes := transmute(string)serializer.output_memory[:serializer.output_length]
		testing.expect_value(t, bytes, expected)
	}
	testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
}

make_nested_array_text :: proc(depth: int, leaf: string) -> []byte {
	result := make([]byte, depth * 2 + len(leaf))
	for i in 0..<depth do result[i] = '['
	copy(result[depth:], leaf)
	for i in 0..<depth do result[depth + len(leaf) + i] = ']'
	return result
}

make_nested_object_text :: proc(depth: int, leaf: string) -> []byte {
	prefix := `{"k":`
	result := make([]byte, depth * (len(prefix) + 1) + len(leaf))
	at := 0
	for _ in 0..<depth {
		copy(result[at:], prefix)
		at += len(prefix)
	}
	copy(result[at:], leaf)
	at += len(leaf)
	for _ in 0..<depth {
		result[at] = '}'
		at += 1
	}
	return result
}

@(test)
compact_scalars_escaping_nul_and_utf8_match_jq :: proc(t: ^testing.T) {
	cases := []struct {input, expected: string}{
		{"null", "null"},
		{"true", "true"},
		{"false", "false"},
		{`"quote:\" slash:\\ solidus:/"`, `"quote:\" slash:\\ solidus:/"`},
		{`"\b\t\n\f\r\u0000\u0001\u001f\u007f"`,
		 `"\b\t\n\f\r\u0000\u0001\u001f\u007f"`},
		{`"héllø 世界 😀"`, `"héllø 世界 😀"`},
		{`"\u0080\u07ff\u0800\ud7ff\ue000\uffff\ud800\udc00"`,
		 `"߿ࠀ퟿￿𐀀"`},
	}
	for test_case in cases do expect_compact_input(t, test_case.input, test_case.expected)
}

@(test)
compact_decimal_numbers_match_pinned_jq_spellings :: proc(t: ^testing.T) {
	cases := []struct {input, expected: string}{
		{"-0", "-0"}, {"-0.0", "-0.0"}, {"+1", "1"},
		{"1e0", "1"}, {"1E+00", "1"}, {"1.000", "1.000"},
		{"0.000001", "0.000001"}, {"0.0000001", "1E-7"},
		{"1e15", "1E+15"}, {"1e999999999", "1E+999999999"},
		{"1e-1147483646", "1E-1147483646"},
		{"1e-1147483647", "0E-1147483646"},
		{"5e-1147483647", "1E-1147483646"},
		{"15e-1147483647", "2E-1147483646"},
		{"12345e-1147483647", "1.235E-1147483643"},
		{"99995e-1147483650", "1.0E-1147483645"},
		{"-99995e-1147483650", "-1.0E-1147483645"},
		{"1e-2000000000", "0E-1147483646"},
		{"123456789012345678901234567890", "123456789012345678901234567890"},
		{"1.2300e+4", "12300"}, {"1.2300e-4", "0.00012300"},
		{"1.2300e-5", "0.000012300"},
		{"0e999999999", "0E+999999999"},
		{"-0e-2000000000", "-0E-1147483646"},
		{"13911860366432393", "13911860366432393"},
		{"0.12345678901234567890123456789", "0.12345678901234567890123456789"},
		{"1e1000000000", "1.7976931348623157e+308"},
	}
	for test_case in cases do expect_compact_input(t, test_case.input, test_case.expected)
}

@(test)
rounded_decimal_uses_one_post_rounding_notation_decision :: proc(t: ^testing.T) {
	// jq's production precision is intentionally enormous. A bounded private
	// context exercises the identical discard branch without constructing a
	// 147,483,649-digit hostile fixture.
	cases := []struct {input, expected: string}{
		{"10000e-4", "1.000"},
		{"12345e-4", "1.235"},
		{"12345e-10", "0.000001235"},
		{"12345e-11", "1.235E-7"},
		{"12345", "1.235E+4"},
		{"99995e-11", "0.000001000"},
		{"99995e-4", "10.00"},
		{"-12345e-4", "-1.235"},
		{"-99995e-11", "-0.000001000"},
		{"0e-200", "0E-100"},
		{"-0e-200", "-0E-100"},
	}
	for test_case in cases {
		expect_compact_literal_context(t, test_case.input, test_case.expected, 4, -100)
	}
	expect_compact_literal_context(
		t,
		"99995",
		"1.7976931348623157e+308",
		4,
		-100,
		4,
	)
}

@(test)
rounded_decimal_allocation_failure_and_cleanup_remain_retryable :: proc(t: ^testing.T) {
	failure_probe := allocator_probe{backing = context.allocator, fail_after = 0}
	failure_serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(
		&failure_serializer,
		probe_allocator(&failure_probe),
	))
	failure := append_literal_number_with_context(
		&failure_serializer,
		"99995e-11",
		4,
		-100,
		999_999_999,
	)
	testing.expect_value(t, failure.kind, Compact_Error_Kind.Out_Of_Memory)
	testing.expect_value(
		t,
		destroy_compact_serializer(&failure_serializer),
		runtime.Allocator_Error.None,
	)
	testing.expect_value(t, failure_probe.live, 0)

	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 2,
		short_success = true,
	}
	retry_serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(
		&retry_serializer,
		probe_allocator(&retry_probe),
	))
	retry_error := append_literal_number_with_context(
		&retry_serializer,
		"99995e-11",
		4,
		-100,
		999_999_999,
	)
	testing.expect_value(t, retry_error.kind, Compact_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, retry_probe.live, 1)
	testing.expect_value(
		t,
		destroy_compact_serializer(&retry_serializer),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(t, retry_probe.live, 1)
	testing.expect_value(
		t,
		destroy_compact_serializer(&retry_serializer),
		runtime.Allocator_Error.None,
	)
	testing.expect_value(t, retry_probe.live, 0)
}

@(test)
compact_native_numbers_match_jq_dtoa_boundaries :: proc(t: ^testing.T) {
	cases := []struct {number: f64, expected: string}{
		{0, "0"}, {-0.0, "-0"}, {1.25, "1.25"},
		{1e-4, "0.0001"}, {1e-5, "1e-05"},
		{1e15, "1000000000000000"}, {1e16, "1e+16"},
		{0.6931471805599453, "0.6931471805599453"},
		{2.302585092994046, "2.302585092994046"},
		{math.inf_f64(1), "1.7976931348623157e+308"},
		{math.inf_f64(-1), "-1.7976931348623157e+308"},
		{math.nan_f64(), "null"},
	}
	for test_case in cases {
		node := value.number_value(test_case.number)
		serializer: Compact_Serializer
		testing.expect(t, init_compact_serializer(&serializer, context.allocator))
		result: Compact_Result
		err := serialize_compact(&serializer, &node, &result)
		testing.expect_value(t, err.kind, Compact_Error_Kind.None)
		bytes, ok := compact_result_bytes(&result)
		testing.expect(t, ok)
		testing.expect_value(t, bytes, test_case.expected)
		testing.expect_value(t, destroy_compact_result(&result), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
	}
}

@(test)
compact_empty_nested_mixed_and_duplicate_update_order :: proc(t: ^testing.T) {
	expect_compact_input(t, "[]", "[]")
	expect_compact_input(t, "{}", "{}")
	expect_compact_input(
		t,
		` { "empty-array": [], "empty-object": {}, "mixed": [null,true,2,"x",{"z":[3]}] } `,
		`{"empty-array":[],"empty-object":{},"mixed":[null,true,2,"x",{"z":[3]}]}`,
	)
	expect_compact_input(t, `{"a":1,"b":2,"a":3,"b":4}`, `{"a":3,"b":4}`)
}

@(test)
invalid_utf8_value_is_a_structured_error :: proc(t: ^testing.T) {
	cases := [][]byte{
		{0xc3, 0x28},
		{0x80},
		{0xe0, 0x80, 0x80},
		{0xed, 0xa0, 0x80},
		{0xf4, 0x90, 0x80, 0x80},
		{0xf0, 0x9f, 0x98},
	}
	for bad_bytes in cases {
		node, constructor_error := value.string_value(
			transmute(string)bad_bytes,
			context.allocator,
		)
		testing.expect_value(t, value.constructor_error_kind(&constructor_error), value.Error.None)
		serializer: Compact_Serializer
		testing.expect(t, init_compact_serializer(&serializer, context.allocator))
		result: Compact_Result
		err := serialize_compact(&serializer, &node, &result)
		testing.expect_value(t, err.kind, Compact_Error_Kind.Invalid_UTF8)
		testing.expect_value(t, err.value_kind, value.Kind.String)
		_, ok := compact_result_bytes(&result)
		testing.expect(t, !ok)
		testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
		testing.expect_value(t, value.destroy_value(&node), runtime.Allocator_Error.None)
	}
}

@(test)
serializer_reuses_after_success_and_terminal_failure :: proc(t: ^testing.T) {
	serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&serializer, context.allocator))
	null_node := value.null_value()
	first: Compact_Result
	testing.expect_value(
		t,
		serialize_compact(&serializer, &null_node, &first).kind,
		Compact_Error_Kind.None,
	)
	testing.expect_value(t, destroy_compact_result(&first), runtime.Allocator_Error.None)

	bad_bytes := [2]byte{0xc3, 0x28}
	bad_node, constructor_error := value.string_value(
		transmute(string)bad_bytes[:],
		context.allocator,
	)
	testing.expect_value(t, value.constructor_error_kind(&constructor_error), value.Error.None)
	failed: Compact_Result
	testing.expect_value(
		t,
		serialize_compact(&serializer, &bad_node, &failed).kind,
		Compact_Error_Kind.Invalid_UTF8,
	)
	_, failed_ok := compact_result_bytes(&failed)
	testing.expect(t, !failed_ok)

	true_node := value.boolean_value(true)
	last: Compact_Result
	testing.expect_value(
		t,
		serialize_compact(&serializer, &true_node, &last).kind,
		Compact_Error_Kind.None,
	)
	last_bytes, last_ok := compact_result_bytes(&last)
	testing.expect(t, last_ok && last_bytes == "true")
	testing.expect_value(t, destroy_compact_result(&last), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&bad_node), runtime.Allocator_Error.None)
}

@(test)
serializer_reuses_after_nonowning_allocation_failure :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = 0}
	serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&serializer, probe_allocator(&probe)))
	node := value.null_value()
	failed: Compact_Result
	testing.expect_value(
		t,
		serialize_compact(&serializer, &node, &failed).kind,
		Compact_Error_Kind.Out_Of_Memory,
	)
	result: Compact_Result
	testing.expect_value(
		t,
		serialize_compact(&serializer, &node, &result).kind,
		Compact_Error_Kind.None,
	)
	bytes, ok := compact_result_bytes(&result)
	testing.expect(t, ok && bytes == "null")
	testing.expect_value(t, destroy_compact_result(&result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
}

@(test)
copied_serializer_and_result_owners_are_rejected_without_freeing :: proc(t: ^testing.T) {
	node := value.null_value()
	serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&serializer, context.allocator))
	serializer_copy := serializer
	copy_result: Compact_Result
	copy_error := serialize_compact(&serializer_copy, &node, &copy_result)
	testing.expect_value(t, copy_error.kind, Compact_Error_Kind.Invalid_Serializer_Owner)
	testing.expect_value(t, destroy_compact_serializer(&serializer_copy), runtime.Allocator_Error.Invalid_Pointer)

	result: Compact_Result
	testing.expect_value(t, serialize_compact(&serializer, &node, &result).kind, Compact_Error_Kind.None)
	serializer_copy = serializer
	testing.expect_value(
		t,
		destroy_compact_serializer(&serializer_copy),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	result_copy := result
	_, copied_ok := compact_result_bytes(&result_copy)
	testing.expect(t, !copied_ok)
	testing.expect_value(t, destroy_compact_result(&result_copy), runtime.Allocator_Error.Invalid_Pointer)
	rejected_move: Compact_Result
	testing.expect_value(
		t,
		take_compact_result(&rejected_move, &result_copy),
		Compact_Error_Kind.Invalid_Result_Owner,
	)
	bytes, ok := compact_result_bytes(&result)
	testing.expect(t, ok && bytes == "null")

	moved: Compact_Result
	testing.expect_value(t, take_compact_result(&moved, &result), Compact_Error_Kind.None)
	_, old_ok := compact_result_bytes(&result)
	testing.expect(t, !old_ok)
	moved_bytes, moved_ok := compact_result_bytes(&moved)
	testing.expect(t, moved_ok && moved_bytes == "null")
	testing.expect_value(t, destroy_compact_result(&moved), runtime.Allocator_Error.None)
	second: Compact_Result
	testing.expect_value(t, serialize_compact(&serializer, &node, &second).kind, Compact_Error_Kind.None)
	second_bytes, second_ok := compact_result_bytes(&second)
	testing.expect(t, second_ok && second_bytes == "null")
	testing.expect_value(t, destroy_compact_result(&second), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
}

@(test)
checked_growth_rejects_size_overflow_before_allocation :: proc(t: ^testing.T) {
	serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&serializer, context.allocator))
	serializer.output_length = max(int)
	testing.expect_value(t, grow_output(&serializer, 1).kind, Compact_Error_Kind.Size_Overflow)
	serializer.output_length = 0
	testing.expect_value(t, grow_frames(&serializer, -1).kind, Compact_Error_Kind.Size_Overflow)
	testing.expect_value(t, grow_frames(&serializer, max(int)).kind, Compact_Error_Kind.Size_Overflow)
	testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
}

@(test)
compact_depth_cutoff_matches_jq_exact_boundary_for_arrays_and_objects :: proc(t: ^testing.T) {
	DEPTH_MARKER :: "<skipped: too deep>"
	CUTOFF_CONTAINER_COUNT :: MAX_COMPACT_PRINT_DEPTH + 1
	testing.expect_value(t, len(DEPTH_MARKER), 19)
	marker: string = DEPTH_MARKER
	marker_bytes := transmute([]byte)marker
	exact_bytes := [19]byte{0x3c, 0x73, 0x6b, 0x69, 0x70, 0x70, 0x65, 0x64, 0x3a, 0x20,
	                         0x74, 0x6f, 0x6f, 0x20, 0x64, 0x65, 0x65, 0x70, 0x3e}
	for byte_value, i in marker_bytes do testing.expect_value(t, byte_value, exact_bytes[i])

	depths := []int{255, 256, 257, 258}
	for depth in depths {
		array_input := make_nested_array_text(depth, "null")
		if depth <= MAX_COMPACT_PRINT_DEPTH {
			expect_compact_input(t, transmute(string)array_input, transmute(string)array_input)
		} else {
			array_expected := make_nested_array_text(CUTOFF_CONTAINER_COUNT, DEPTH_MARKER)
			expect_compact_input(t, transmute(string)array_input, transmute(string)array_expected)
			delete(array_expected)
		}
		delete(array_input)

		object_input := make_nested_object_text(depth, "null")
		if depth <= MAX_COMPACT_PRINT_DEPTH {
			expect_compact_input(t, transmute(string)object_input, transmute(string)object_input)
		} else {
			object_expected := make_nested_object_text(CUTOFF_CONTAINER_COUNT, DEPTH_MARKER)
			expect_compact_input(t, transmute(string)object_input, transmute(string)object_expected)
			delete(object_expected)
		}
		delete(object_input)
	}
}

@(test)
compact_depth_cutoff_preserves_mixed_containers_keys_and_later_siblings :: proc(t: ^testing.T) {
	DEPTH_MARKER :: "<skipped: too deep>"

	deep_array_input := make_nested_array_text(MAX_COMPACT_PRINT_DEPTH, `[0,1,{"x":2}]`)
	deep_array_expected := make_nested_array_text(
		MAX_COMPACT_PRINT_DEPTH,
		`[<skipped: too deep>,<skipped: too deep>,<skipped: too deep>]`,
	)
	expect_compact_input(
		t,
		transmute(string)deep_array_input,
		transmute(string)deep_array_expected,
	)
	delete(deep_array_expected)
	delete(deep_array_input)

	deep_object_input := make_nested_object_text(
		MAX_COMPACT_PRINT_DEPTH,
		`{"a":0,"quote\"\\\u0000":1,"tail":2}`,
	)
	deep_object_expected := make_nested_object_text(
		MAX_COMPACT_PRINT_DEPTH,
		`{"a":<skipped: too deep>,"quote\"\\\u0000":<skipped: too deep>,"tail":<skipped: too deep>}`,
	)
	expect_compact_input(
		t,
		transmute(string)deep_object_input,
		transmute(string)deep_object_expected,
	)
	delete(deep_object_expected)
	delete(deep_object_input)

	branch_input := make_nested_array_text(MAX_COMPACT_PRINT_DEPTH, "null")
	branch_expected := make_nested_array_text(MAX_COMPACT_PRINT_DEPTH, DEPTH_MARKER)
	input_prefix := `{"deep":`
	input_suffix := `,"tail":"ok"}`
	root_input := make([]byte, len(input_prefix) + len(branch_input) + len(input_suffix))
	copy(root_input, input_prefix)
	copy(root_input[len(input_prefix):], branch_input)
	copy(root_input[len(input_prefix) + len(branch_input):], input_suffix)
	root_expected := make([]byte, len(input_prefix) + len(branch_expected) + len(input_suffix))
	copy(root_expected, input_prefix)
	copy(root_expected[len(input_prefix):], branch_expected)
	copy(root_expected[len(input_prefix) + len(branch_expected):], input_suffix)
	expect_compact_input(t, transmute(string)root_input, transmute(string)root_expected)
	delete(root_expected)
	delete(root_input)
	delete(branch_expected)
	delete(branch_input)
}

@(test)
compact_deep_array_and_keyed_object_use_iterative_stack :: proc(t: ^testing.T) {
	DEPTH_MARKER :: "<skipped: too deep>"
	CUTOFF_CONTAINER_COUNT :: MAX_COMPACT_PRINT_DEPTH + 1
	ARRAY_DEPTH :: 10_000
	array_input := make_nested_array_text(ARRAY_DEPTH, "null")
	array_expected := make_nested_array_text(CUTOFF_CONTAINER_COUNT, DEPTH_MARKER)
	expect_compact_input(t, transmute(string)array_input, transmute(string)array_expected)
	delete(array_expected)
	delete(array_input)

	OBJECT_DEPTH :: 5_000
	object_input := make_nested_object_text(OBJECT_DEPTH, "null")
	object_expected := make_nested_object_text(CUTOFF_CONTAINER_COUNT, DEPTH_MARKER)
	expect_compact_input(t, transmute(string)object_input, transmute(string)object_expected)
	delete(object_expected)
	delete(object_input)

	MIXED_DEPTH :: 6_000
	// Each object occupies two parser frames in addition to its surrounding
	// array, so this remains below the parser's 10,000-frame limit.
	mixed_input := make([]byte, MIXED_DEPTH / 2 * 8 + 4)
	at := 0
	for _ in 0..<MIXED_DEPTH / 2 {
		copy(mixed_input[at:], `[{"k":`)
		at += 6
	}
	copy(mixed_input[at:], "null")
	at += 4
	for _ in 0..<MIXED_DEPTH / 2 {
		copy(mixed_input[at:], `}]`)
		at += 2
	}
	testing.expect_value(t, at, len(mixed_input))
	// The first 257 containers are 128 array/object pairs plus one array.
	mixed_expected := make([]byte, 128 * 8 + 2 + len(DEPTH_MARKER))
	at = 0
	for _ in 0..<128 {
		copy(mixed_expected[at:], `[{"k":`)
		at += 6
	}
	mixed_expected[at] = '['
	at += 1
	copy(mixed_expected[at:], DEPTH_MARKER)
	at += len(DEPTH_MARKER)
	mixed_expected[at] = ']'
	at += 1
	for _ in 0..<128 {
		copy(mixed_expected[at:], `}]`)
		at += 2
	}
	testing.expect_value(t, at, len(mixed_expected))
	expect_compact_input(t, transmute(string)mixed_input, transmute(string)mixed_expected)
	delete(mixed_expected)
	delete(mixed_input)
}

@(test)
depth_cutoff_allocation_failures_and_result_destroy_retry_clean_up :: proc(t: ^testing.T) {
	input := make_nested_array_text(400, `{"deep":null,"tail":"ok"}`)
	node, parse_error := parse_value(transmute(string)input, context.allocator)
	delete(input)
	testing.expect_value(t, parse_error.kind, Scalar_Parse_Error_Kind.None)
	defer value.destroy_value(&node)
	expected := make_nested_array_text(
		MAX_COMPACT_PRINT_DEPTH + 1,
		"<skipped: too deep>",
	)
	defer delete(expected)

	saw_failure, saw_success := false, false
	for fail_at in 0..<24 {
		probe := allocator_probe{backing = context.allocator, fail_after = fail_at}
		serializer: Compact_Serializer
		testing.expect(t, init_compact_serializer(&serializer, probe_allocator(&probe)))
		result: Compact_Result
		err := serialize_compact(&serializer, &node, &result)
		if err.kind == .None {
			saw_success = true
			bytes, ok := compact_result_bytes(&result)
			testing.expect(t, ok && bytes == transmute(string)expected)
			probe.free_failures_remaining = 1
			testing.expect_value(
				t,
				destroy_compact_result(&result),
				runtime.Allocator_Error.Invalid_Pointer,
			)
			retained, retained_ok := compact_result_bytes(&result)
			testing.expect(t, retained_ok && retained == bytes)
			testing.expect_value(t, destroy_compact_result(&result), runtime.Allocator_Error.None)
		} else {
			saw_failure = true
		}
		testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.live, 0)
	}
	testing.expect(t, saw_failure && saw_success)
}

@(test)
every_serializer_allocation_and_short_allocation_cleans_up :: proc(t: ^testing.T) {
	DEPTH :: 96
	input := make([]byte, DEPTH * 2 + 1026)
	for i in 0..<DEPTH do input[i] = '['
	input[DEPTH] = '"'
	for i in DEPTH + 1..<DEPTH + 1025 do input[i] = 'x'
	input[DEPTH + 1025] = '"'
	for i in 0..<DEPTH do input[DEPTH + 1026 + i] = ']'
	node, parse_error := parse_value(transmute(string)input, context.allocator)
	delete(input)
	testing.expect_value(t, parse_error.kind, Scalar_Parse_Error_Kind.None)
	defer value.destroy_value(&node)

	// The success iteration proves the range extends beyond every allocation
	// site exercised by frame and output growth.
	for fail_at in 0..<20 {
		probe := allocator_probe{backing = context.allocator, fail_after = fail_at}
		serializer: Compact_Serializer
		testing.expect(t, init_compact_serializer(&serializer, probe_allocator(&probe)))
		result: Compact_Result
		err := serialize_compact(&serializer, &node, &result)
		if err.kind == .None {
			testing.expect_value(t, destroy_compact_result(&result), runtime.Allocator_Error.None)
		}
		testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.live, 0)
	}
	for short_at in 1..=12 {
		probe := allocator_probe{
			backing = context.allocator,
			fail_after = max(int),
			short_at_plus_one = short_at,
		}
		serializer: Compact_Serializer
		testing.expect(t, init_compact_serializer(&serializer, probe_allocator(&probe)))
		result: Compact_Result
		err := serialize_compact(&serializer, &node, &result)
		if err.kind == .None {
			testing.expect_value(t, destroy_compact_result(&result), runtime.Allocator_Error.None)
		}
		testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.live, 0)
	}
}

@(test)
allocator_failure_short_growth_cleanup_retry_and_temp_isolation :: proc(t: ^testing.T) {
	long_bytes := make([]byte, 1024)
	for i in 0..<len(long_bytes) do long_bytes[i] = 'x'
	node, constructor_error := value.string_value(transmute(string)long_bytes, context.allocator)
	delete(long_bytes)
	testing.expect_value(t, value.constructor_error_kind(&constructor_error), value.Error.None)
	defer value.destroy_value(&node)

	for fail_after in 0..<3 {
		probe := allocator_probe{backing = context.allocator, fail_after = fail_after}
		serializer: Compact_Serializer
		testing.expect(t, init_compact_serializer(&serializer, probe_allocator(&probe)))
		result: Compact_Result
		err := serialize_compact(&serializer, &node, &result)
		if err.kind == .None {
			testing.expect_value(t, destroy_compact_result(&result), runtime.Allocator_Error.None)
		}
		testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.live, 0)
	}

	short_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
	}
	short_serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&short_serializer, probe_allocator(&short_probe)))
	short_result: Compact_Result
	short_error := serialize_compact(&short_serializer, &node, &short_result)
	testing.expect_value(t, short_error.kind, Compact_Error_Kind.Out_Of_Memory)
	testing.expect_value(t, destroy_compact_serializer(&short_serializer), runtime.Allocator_Error.None)
	testing.expect_value(t, short_probe.live, 0)

	short_retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 2,
		short_success = true,
	}
	short_retry_serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(
		&short_retry_serializer,
		probe_allocator(&short_retry_probe),
	))
	short_retry_result: Compact_Result
	short_retry_error := serialize_compact(
		&short_retry_serializer,
		&node,
		&short_retry_result,
	)
	testing.expect_value(t, short_retry_error.kind, Compact_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, short_retry_probe.live, 1)
	testing.expect_value(
		t,
		destroy_compact_serializer(&short_retry_serializer),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(t, short_retry_probe.live, 1)
	testing.expect_value(
		t,
		destroy_compact_serializer(&short_retry_serializer),
		runtime.Allocator_Error.None,
	)
	testing.expect_value(t, short_retry_probe.live, 0)

	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	retry_serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&retry_serializer, probe_allocator(&retry_probe)))
	retry_result: Compact_Result
	retry_error := serialize_compact(&retry_serializer, &node, &retry_result)
	testing.expect_value(t, retry_error.kind, Compact_Error_Kind.Cleanup_Failed)
	blocked_result: Compact_Result
	testing.expect_value(
		t,
		serialize_compact(&retry_serializer, &node, &blocked_result).kind,
		Compact_Error_Kind.Invalid_Serializer_Owner,
	)
	testing.expect_value(t, destroy_compact_serializer(&retry_serializer), runtime.Allocator_Error.None)
	testing.expect_value(t, retry_probe.live, 0)

	deep_input := make([]byte, 68)
	for i in 0..<32 do deep_input[i] = '['
	copy(deep_input[32:], "null")
	for i in 0..<32 do deep_input[36 + i] = ']'
	deep_node, deep_parse_error := parse_value(transmute(string)deep_input, context.allocator)
	delete(deep_input)
	testing.expect_value(t, deep_parse_error.kind, Scalar_Parse_Error_Kind.None)
	frame_retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	frame_retry_serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(
		&frame_retry_serializer,
		probe_allocator(&frame_retry_probe),
	))
	frame_retry_result: Compact_Result
	frame_retry_error := serialize_compact(
		&frame_retry_serializer,
		&deep_node,
		&frame_retry_result,
	)
	testing.expect_value(t, frame_retry_error.kind, Compact_Error_Kind.Cleanup_Failed)
	testing.expect_value(
		t,
		destroy_compact_serializer(&frame_retry_serializer),
		runtime.Allocator_Error.None,
	)
	testing.expect_value(t, frame_retry_probe.live, 0)
	testing.expect_value(t, value.destroy_value(&deep_node), runtime.Allocator_Error.None)

	temp_probe := allocator_probe{backing = context.allocator, fail_after = 0}
	temp_node, temp_parse_error := parse_value(`{"nul":"\u0000","utf8":"é"}`, context.allocator)
	testing.expect_value(t, temp_parse_error.kind, Scalar_Parse_Error_Kind.None)
	saved_temp := context.temp_allocator
	context.temp_allocator = probe_allocator(&temp_probe)
	temp_serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&temp_serializer, context.allocator))
	temp_result: Compact_Result
	temp_error := serialize_compact(&temp_serializer, &temp_node, &temp_result)
	context.temp_allocator = saved_temp
	testing.expect_value(t, temp_error.kind, Compact_Error_Kind.None)
	temp_bytes, temp_ok := compact_result_bytes(&temp_result)
	testing.expect(t, temp_ok && temp_bytes == `{"nul":"\u0000","utf8":"é"}`)
	testing.expect_value(t, destroy_compact_result(&temp_result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_compact_serializer(&temp_serializer), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&temp_node), runtime.Allocator_Error.None)
	testing.expect_value(t, temp_probe.allocations, 0)
}

@(test)
result_free_retry_and_bulk_allocator_retirement_are_safe :: proc(t: ^testing.T) {
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&serializer, probe_allocator(&probe)))
	node := value.null_value()
	result: Compact_Result
	testing.expect_value(t, serialize_compact(&serializer, &node, &result).kind, Compact_Error_Kind.None)
	testing.expect_value(t, destroy_compact_result(&result), runtime.Allocator_Error.Invalid_Pointer)
	bytes, ok := compact_result_bytes(&result)
	testing.expect(t, ok && bytes == "null")
	testing.expect_value(t, destroy_compact_result(&result), runtime.Allocator_Error.None)
	probe.free_failures_remaining = 1
	testing.expect_value(
		t,
		destroy_compact_serializer(&serializer),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(t, destroy_compact_serializer(&serializer), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)

	arena: runtime.Arena
	testing.expect_value(t, runtime.arena_init(&arena, 4096, context.allocator), runtime.Allocator_Error.None)
	bulk := runtime.arena_allocator(&arena)
	bulk_serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&bulk_serializer, bulk))
	bulk_result: Compact_Result
	testing.expect_value(t, serialize_compact(&bulk_serializer, &node, &bulk_result).kind, Compact_Error_Kind.None)
	testing.expect_value(t, destroy_compact_result(&bulk_result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_compact_serializer(&bulk_serializer), runtime.Allocator_Error.None)
	runtime.arena_destroy(&arena)
}
