package json

import "base:runtime"
import "core:testing"
import "jq:value"

@(private)
expect_array_error_at :: proc(
	t: ^testing.T,
	input: string,
	kind: Scalar_Parse_Error_Kind,
	detection, cause: int,
) {
	parsed, err := parse_value(input, context.allocator)
	defer value.destroy_value(&parsed)
	defer destroy_scalar_parse_error(&err)
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, kind)
	testing.expect_value(t, err.detection_offset, detection)
	testing.expect(t, err.has_cause_offset)
	testing.expect_value(t, err.cause_offset, cause)
}

@(private)
array_element :: proc(t: ^testing.T, array: ^value.Value, index: int) -> value.Value {
	element, ok := value.array_element_copy(array, index)
	testing.expect(t, ok)
	return element
}

@(test)
parse_value_preserves_scalars_and_accepts_objects :: proc(t: ^testing.T) {
	inputs := [5]string{"null", " true ", "-12.5", `"text"`, "\xef\xbb\xbf false"}
	kinds := [5]value.Kind{.Null, .Boolean, .Number, .String, .Boolean}
	for input, index in inputs {
		parsed, err := parse_value(input, context.allocator)
		testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
		testing.expect_value(t, value.kind_of(&parsed), kinds[index])
		testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
	}
	object, object_error := parse_value(`{"x": 1}`, context.allocator)
	testing.expect_value(t, object_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&object), value.Kind.Object)
	testing.expect_value(t, value.destroy_value(&object), runtime.Allocator_Error.None)
	mixed, mixed_error := parse_value(`[{"x": 1}]`, context.allocator)
	testing.expect_value(t, mixed_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&mixed), value.Kind.Array)
	testing.expect_value(t, value.destroy_value(&mixed), runtime.Allocator_Error.None)

	legacy, legacy_error := parse_scalar("[]", context.allocator)
	testing.expect_value(t, value.kind_of(&legacy), value.Kind.Invalid)
	testing.expect_value(t, legacy_error.kind, Scalar_Parse_Error_Kind.Array_Not_Supported)
}

@(test)
empty_flat_and_nested_arrays_own_complete_values :: proc(t: ^testing.T) {
	empty, empty_error := parse_value(" \t[]\r\n", context.allocator)
	testing.expect_value(t, empty_error.kind, Scalar_Parse_Error_Kind.None)
	empty_length, empty_ok := value.array_length(&empty)
	testing.expect(t, empty_ok && empty_length == 0)
	testing.expect_value(t, value.destroy_value(&empty), runtime.Allocator_Error.None)

	input_text := `[
        null, true, false, -12.50e+2, "a\u0000b",
        [], [1, [2, ["three"]]]
	    ]`
	input_bytes := make([]byte, len(input_text))
	copy(input_bytes, transmute([]byte)input_text)
	defer delete(input_bytes)
	parsed, err := parse_value(transmute(string)input_bytes, context.allocator)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	length, ok := value.array_length(&parsed)
	testing.expect(t, ok && length == 7)

	text := array_element(t, &parsed, 4)
	text_view, text_ok := value.string_borrowed(&text)
	testing.expect(t, text_ok && text_view == "a\x00b")
	testing.expect_value(t, value.destroy_value(&text), runtime.Allocator_Error.None)

	nested := array_element(t, &parsed, 6)
	nested_length, nested_ok := value.array_length(&nested)
	testing.expect(t, nested_ok && nested_length == 2)
	deep := array_element(t, &nested, 1)
	deeper := array_element(t, &deep, 1)
	deepest := array_element(t, &deeper, 0)
	deep_text, deep_text_ok := value.string_borrowed(&deepest)
	testing.expect(t, deep_text_ok && deep_text == "three")
	testing.expect_value(t, value.destroy_value(&deepest), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&deeper), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&deep), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&nested), runtime.Allocator_Error.None)

	// Mutating the borrowed input after parsing cannot affect owned strings or
	// numeric literal payloads in the returned Value tree.
	for &byte in input_bytes {
		byte = 'x'
	}
	owned_number := array_element(t, &parsed, 3)
	spelling, spelling_ok := value.literal_spelling_borrowed(&owned_number)
	testing.expect(t, spelling_ok && spelling == "-12.50e+2")
	testing.expect_value(t, value.destroy_value(&owned_number), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
}

@(test)
array_syntax_errors_have_stable_detection_and_cause_offsets :: proc(t: ^testing.T) {
	Case :: struct {
		input: string,
		kind: Scalar_Parse_Error_Kind,
		detection: int,
		cause: int,
	}
	cases := []Case{
		{"[", .Unfinished_Array, 0, 1},
		{"[[1]", .Unfinished_Array, 3, 4},
		{"[1,]", .Expected_Array_Element, 3, 3},
		{"[1, ]", .Expected_Array_Element, 4, 4},
		{"[,1]", .Expected_Value_Before_Separator, 1, 1},
		{"[1,,2]", .Expected_Value_Before_Separator, 3, 3},
		{"[}", .Unmatched_Object_Closer, 1, 1},
		{"[1}", .Object_Key_Value_Pairs_Required, 2, 2},
		{"[:]", .Expected_String_Key_Before_Colon, 1, 1},
		{"[1,:]", .Expected_String_Key_Before_Colon, 3, 3},
		{"[1:]", .Unexpected_Colon, 2, 2},
		{"[1 2]", .Expected_Separator, 4, 3},
		{`["a" "b"]`, .Expected_Separator, 7, 5},
		{"[1 [2]]", .Expected_Separator, 3, 3},
		{"[1]x", .Invalid_Number, 3, 3},
		{"[1][2]", .Unexpected_Extra_Values, 3, 3},
		{"]", .Unmatched_Array_Closer, 0, 0},
		{"}", .Unmatched_Object_Closer, 0, 0},
		{",", .Expected_Value_Before_Separator, 0, 0},
		{":", .Expected_String_Key_Before_Colon, 0, 0},
	}
	for test_case in cases {
		expect_array_error_at(
			t,
			test_case.input,
			test_case.kind,
			test_case.detection,
			test_case.cause,
		)
	}
}

@(test)
later_input_uses_jq_one_shot_precedence :: proc(t: ^testing.T) {
	expect_array_error_at(t, "[] 2", .Unexpected_Extra_Values, 3, 3)
	expect_array_error_at(t, "[] 1e+", .Invalid_Number, 5, 6)
	expect_array_error_at(t, "[] [1,]", .Expected_Array_Element, 6, 6)
	expect_array_error_at(t, "[] {", .Unfinished_Object, 3, 4)
	expect_array_error_at(t, "null false", .Unexpected_Extra_Values, 5, 5)
	expect_array_error_at(t, "null [", .Unfinished_Array, 5, 6)
}

@(test)
array_elements_reuse_scalar_utf8_number_nul_and_bom_rules :: proc(t: ^testing.T) {
	bom_array := [9]byte{0xef, 0xbb, 0xbf, '[', 'n', 'u', 'l', 'l', ']'}
	parsed, err := parse_value(transmute(string)bom_array[:], context.allocator)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)

	bad_utf8 := [5]byte{'[', '"', 0xff, '"', ']'}
	normalized, normalized_error := parse_value(transmute(string)bad_utf8[:], context.allocator)
	testing.expect_value(t, normalized_error.kind, Scalar_Parse_Error_Kind.None)
	normalized_text := array_element(t, &normalized, 0)
	view, view_ok := value.string_borrowed(&normalized_text)
	testing.expect(t, view_ok && view == "�")
	testing.expect_value(t, value.destroy_value(&normalized_text), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&normalized), runtime.Allocator_Error.None)

	numeric_nul := [5]byte{'[', '1', 0, 'x', ']'}
	nul_number, nul_error := parse_value(transmute(string)numeric_nul[:], context.allocator)
	testing.expect_value(t, nul_error.kind, Scalar_Parse_Error_Kind.None)
	first := array_element(t, &nul_number, 0)
	spelling, spelling_ok := value.literal_spelling_borrowed(&first)
	testing.expect(t, spelling_ok && spelling == "1")
	testing.expect_value(t, value.destroy_value(&first), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&nul_number), runtime.Allocator_Error.None)

	literal_nul := [5]byte{'[', '"', 0, '"', ']'}
	expect_array_error_at(
		t,
		transmute(string)literal_nul[:],
		.Unescaped_Control,
		3,
		2,
	)
	expect_array_error_at(t, "[1e+]", .Invalid_Number, 4, 4)
}

@(test)
array_numbers_keep_jq_decnumber_boundaries :: proc(t: ^testing.T) {
	spellings := []string{
		"01", "1.", ".1", "+1", "-.1", "1.e2", "9007199254740993",
		"1e9999999999", "1e-9999999999",
	}
	parsed, err := parse_value(
		"[01,1.,.1,+1,-.1,1.e2,9007199254740993,1e9999999999,1e-9999999999]",
		context.allocator,
	)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	length, ok := value.array_length(&parsed)
	testing.expect(t, ok && length == len(spellings))
	for expected, index in spellings {
		element := array_element(t, &parsed, index)
		spelling, spelling_ok := value.literal_spelling_borrowed(&element)
		testing.expect(t, spelling_ok && spelling == expected)
		testing.expect_value(t, value.destroy_value(&element), runtime.Allocator_Error.None)
	}
	testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
}

@(private)
nested_null_input :: proc(depth: int) -> []byte {
	bytes := make([]byte, depth * 2 + 4)
	for i in 0..<depth {
		bytes[i] = '['
	}
	copy(bytes[depth:depth + 4], "null")
	for i in 0..<depth {
		bytes[depth + 4 + i] = ']'
	}
	return bytes
}

@(test)
public_parser_enforces_array_syntactic_entry_boundary :: proc(t: ^testing.T) {
	accepted_bytes := nested_null_input(MAX_PARSING_DEPTH)
	accepted, accepted_error := parse_value(transmute(string)accepted_bytes, context.allocator)
	delete(accepted_bytes)
	testing.expect_value(t, accepted_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&accepted), value.Kind.Array)
	testing.expect_value(t, value.destroy_value(&accepted), runtime.Allocator_Error.None)

	rejected_bytes := nested_null_input(MAX_PARSING_DEPTH + 1)
	rejected, rejected_error := parse_value(transmute(string)rejected_bytes, context.allocator)
	delete(rejected_bytes)
	testing.expect_value(t, value.kind_of(&rejected), value.Kind.Invalid)
	testing.expect_value(t, rejected_error.kind, Scalar_Parse_Error_Kind.Depth_Limit)
	testing.expect_value(t, rejected_error.detection_offset, MAX_PARSING_DEPTH)
	testing.expect(t, rejected_error.has_cause_offset)
	testing.expect_value(t, rejected_error.cause_offset, MAX_PARSING_DEPTH)
	testing.expect_value(t, destroy_scalar_parse_error(&rejected_error), runtime.Allocator_Error.None)

	brackets := make([]byte, (MAX_PARSING_DEPTH + 1) * 2 + 4)
	brackets[0] = '['
	brackets[1] = '"'
	for i in 0..<MAX_PARSING_DEPTH + 1 {
		brackets[2 + i] = '['
		brackets[2 + MAX_PARSING_DEPTH + 1 + i] = '}'
	}
	brackets[len(brackets) - 2] = '"'
	brackets[len(brackets) - 1] = ']'
	string_array, string_error := parse_value(transmute(string)brackets, context.allocator)
	testing.expect_value(t, string_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.destroy_value(&string_array), runtime.Allocator_Error.None)
	delete(brackets)
}

@(test)
public_parser_gives_boundary_opener_depth_precedence_over_separator :: proc(t: ^testing.T) {
	shallow, shallow_error := parse_value("[null[", context.allocator)
	testing.expect_value(t, value.kind_of(&shallow), value.Kind.Invalid)
	testing.expect_value(t, shallow_error.kind, Scalar_Parse_Error_Kind.Expected_Separator)
	testing.expect_value(t, shallow_error.detection_offset, 5)
	testing.expect_value(t, destroy_scalar_parse_error(&shallow_error), runtime.Allocator_Error.None)

	boundary := make([]byte, MAX_PARSING_DEPTH + 5)
	for i in 0..<MAX_PARSING_DEPTH do boundary[i] = '['
	copy(boundary[MAX_PARSING_DEPTH:MAX_PARSING_DEPTH + 4], "null")
	boundary[len(boundary) - 1] = '{'
	boundary_value, boundary_error := parse_value(transmute(string)boundary, context.allocator)
	delete(boundary)
	testing.expect_value(t, value.kind_of(&boundary_value), value.Kind.Invalid)
	testing.expect_value(t, boundary_error.kind, Scalar_Parse_Error_Kind.Depth_Limit)
	testing.expect_value(t, boundary_error.detection_offset, MAX_PARSING_DEPTH + 4)
	testing.expect(t, boundary_error.has_cause_offset)
	testing.expect_value(t, boundary_error.cause_offset, MAX_PARSING_DEPTH + 4)
	testing.expect_value(t, destroy_scalar_parse_error(&boundary_error), runtime.Allocator_Error.None)
}

@(test)
array_allocation_failure_sweep_is_inert_and_leak_free :: proc(t: ^testing.T) {
	input := `[["a",1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17], ["b"]]`
	for fail_after in 0..<28 {
		probe := allocator_probe{backing = context.allocator, fail_after = fail_after}
		parsed, err := parse_value(input, probe_allocator(&probe))
		parse_ok := err.kind == .None
		if parse_ok {
			testing.expect_value(t, value.kind_of(&parsed), value.Kind.Array)
			testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
		} else {
			testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
			testing.expect_value(t, destroy_scalar_parse_error(&err), runtime.Allocator_Error.None)
		}
		testing.expect_value(t, probe.live, 0)
		if parse_ok {
			testing.expect_value(t, probe.allocations, probe.frees)
		} else {
			testing.expect_value(t, probe.allocations, probe.frees + 1)
		}
	}
}

@(test)
frame_allocation_requires_exact_storage_and_retries_failed_free :: proc(t: ^testing.T) {
	saved_temp_allocator := context.temp_allocator

	nil_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		nil_success = true,
	}
	context.temp_allocator = probe_allocator(&nil_probe)
	nil_result, nil_error := parse_value("[]", context.allocator)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, value.kind_of(&nil_result), value.Kind.Invalid)
	testing.expect_value(t, nil_error.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, nil_probe.live, 0)

	short_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
	}
	context.temp_allocator = probe_allocator(&short_probe)
	short_result, short_error := parse_value("[]", context.allocator)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, value.kind_of(&short_result), value.Kind.Invalid)
	testing.expect_value(t, short_error.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, short_probe.live, 0)

	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
		free_failures_remaining = 2,
	}
	context.temp_allocator = probe_allocator(&retry_probe)
	retry_result, retry_error := parse_value("[]", context.allocator)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, value.kind_of(&retry_result), value.Kind.Invalid)
	testing.expect_value(t, retry_error.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, retry_error.cause_kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(
		t,
		destroy_scalar_parse_error(&retry_error),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(t, destroy_scalar_parse_error(&retry_error), runtime.Allocator_Error.None)
	testing.expect_value(t, retry_probe.live, 0)
}

@(test)
frame_and_value_cleanup_failures_are_retryable :: proc(t: ^testing.T) {
	value_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 2,
	}
	temporary_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = probe_allocator(&temporary_probe)
	parsed, err := parse_value(`[[1],`, probe_allocator(&value_probe))
	context.temp_allocator = saved_temp_allocator

	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, err.cause_kind, Scalar_Parse_Error_Kind.Unfinished_Array)
	testing.expect(t, value_probe.live > 0)
	testing.expect_value(
		t,
		destroy_scalar_parse_error(&err),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	cleanup_result, _ := retry_scalar_parse_error_cleanup(&err)
	testing.expect_value(t, cleanup_result, scalar_parse_cleanup_retry_result.Terminal)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value_probe.live, 0)
	testing.expect_value(t, temporary_probe.live, 0)
}

@(test)
bulk_allocator_retirement_is_successful_cleanup :: proc(t: ^testing.T) {
	arena: runtime.Arena
	init_error := runtime.arena_init(&arena, 65536, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error.None)
	bulk := runtime.arena_allocator(&arena)
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = bulk
	parsed, err := parse_value(`[["bulk"], 1, 2, 3]`, bulk)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
	runtime.arena_destroy(&arena)
}
