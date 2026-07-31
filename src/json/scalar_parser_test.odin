package json

import "base:runtime"
import "core:mem"
import "core:testing"
import "jq:value"

TRACKING_MEMORY : bool : #config(ODIN_TEST_TRACK_MEMORY, true)

@(private)
expect_string_parse :: proc(t: ^testing.T, input, expected: string) {
	parsed, err := parse_scalar(input, context.allocator)
	defer value.destroy_value(&parsed)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.String)
	actual, ok := value.string_borrowed(&parsed)
	testing.expect(t, ok)
	testing.expect_value(t, actual, expected)
}

@(private)
expect_parse_error :: proc(
	t: ^testing.T,
	input: string,
	kind: Scalar_Parse_Error_Kind,
	offset: int,
) {
	parsed, err := parse_scalar(input, context.allocator)
	defer value.destroy_value(&parsed)
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, kind)
	testing.expect(t, err.has_cause_offset)
	testing.expect_value(t, err.cause_offset, offset)
}

@(private)
expect_parse_error_at :: proc(
	t: ^testing.T,
	input: string,
	kind: Scalar_Parse_Error_Kind,
	detection_offset, cause_offset: int,
) {
	parsed, err := parse_scalar(input, context.allocator)
	defer value.destroy_value(&parsed)
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, kind)
	testing.expect_value(t, err.detection_offset, detection_offset)
	testing.expect(t, err.has_cause_offset)
	testing.expect_value(t, err.cause_offset, cause_offset)
}

@(test)
every_scalar_kind_and_owned_number_spelling :: proc(t: ^testing.T) {
	null, null_error := parse_scalar("null", context.allocator)
	truth, true_error := parse_scalar(" true ", context.allocator)
	falsity, false_error := parse_scalar("\tfalse\r\n", context.allocator)
	number, number_error := parse_scalar("-12.50e+2", context.allocator)
	text, string_error := parse_scalar(`"scalar"`, context.allocator)
	defer value.destroy_value(&null)
	defer value.destroy_value(&truth)
	defer value.destroy_value(&falsity)
	defer value.destroy_value(&number)
	defer value.destroy_value(&text)

	testing.expect_value(t, null_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, true_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, false_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, number_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, string_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&null), value.Kind.Null)
	got_true, true_ok := value.boolean_value_get(&truth)
	got_false, false_ok := value.boolean_value_get(&falsity)
	testing.expect(t, true_ok && got_true)
	testing.expect(t, false_ok && !got_false)
	spelling, spelling_ok := value.literal_spelling_borrowed(&number)
	testing.expect(t, spelling_ok && spelling == "-12.50e+2")
	number_kind, number_kind_ok := value.number_kind(&number)
	testing.expect(t, number_kind_ok && number_kind == .Literal)
	view, text_ok := value.string_borrowed(&text)
	testing.expect(t, text_ok && view == "scalar")
}

@(test)
number_tokens_follow_jq_decnumber_grammar :: proc(t: ^testing.T) {
	valid := []string{
		"0", "-0", "1", "-12", "1.0", "0.25", "1e2", "1E+2", "1e-2",
		"9007199254740993", "01", "-01", "1.", ".1", "+1", "-.1", "1.e2",
		"00e2", "NaN", "nan", "Infinity", "-Infinity",
	}
	for literal in valid {
		parsed, err := parse_scalar(literal, context.allocator)
		testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
		testing.expect_value(t, value.kind_of(&parsed), value.Kind.Number)
		if literal != "NaN" && literal != "nan" {
			spelling, ok := value.literal_spelling_borrowed(&parsed)
			testing.expect(t, ok && spelling == literal)
		}
		testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
	}

	Case :: struct {
		input:  string,
		offset: int,
	}
	invalid := []Case{
		{"1e", 2},
		{"1e+", 3},
		{"1x", 1},
		{"--1", 1},
		{"  1.x", 4},
		{"1e+x", 3},
		{"1e+ ", 3},
		{"-", 1},
	}
	for test_case in invalid {
		expect_parse_error(t, test_case.input, .Invalid_Number, test_case.offset)
	}
}

@(test)
numeric_validation_precedes_trailing_input_classification :: proc(t: ^testing.T) {
	Case :: struct {
		input:      string,
		kind:       Scalar_Parse_Error_Kind,
		detection:  int,
		cause:      int,
	}
	test_cases := []Case{
		{"1x,", .Invalid_Number, 2, 1},
		{"1x]", .Invalid_Number, 2, 1},
		{"1e}", .Invalid_Number, 2, 2},
		{"1e true", .Invalid_Number, 2, 2},
		{"1,", .Trailing_Input, 1, 1},
		{"1]", .Trailing_Input, 1, 1},
		{"1}", .Trailing_Input, 1, 1},
		{"1 true", .Trailing_Input, 2, 2},
	}
	for test_case in test_cases {
		expect_parse_error_at(
			t,
			test_case.input,
			test_case.kind,
			test_case.detection,
			test_case.cause,
		)
	}
}

@(test)
numeric_nul_uses_prefix_without_changing_other_token_kinds :: proc(t: ^testing.T) {
	accepted_one_suffix := [3]byte{'1', 0, 'x'}
	accepted_one_end := [2]byte{'1', 0}
	accepted_negative_suffix := [5]byte{'-', '0', '1', 0, 'x'}
	accepted := [3]string{
		transmute(string)accepted_one_suffix[:],
		transmute(string)accepted_one_end[:],
		transmute(string)accepted_negative_suffix[:],
	}
	expected_spellings := [3]string{"1", "1", "-01"}
	for input, index in accepted {
		parsed, err := parse_scalar(input, context.allocator)
		testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
		spelling, ok := value.literal_spelling_borrowed(&parsed)
		testing.expect(t, ok && spelling == expected_spellings[index])
		testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
	}

	nul_first_bytes := [1]byte{0}
	expect_parse_error_at(
		t,
		transmute(string)nul_first_bytes[:],
		.Invalid_Number,
		0,
		0,
	)
	invalid_prefix_bytes := [4]byte{'1', 'e', 0, 'x'}
	expect_parse_error_at(
		t,
		transmute(string)invalid_prefix_bytes[:],
		.Invalid_Number,
		3,
		2,
	)
	invalid_sign_bytes := [3]byte{'+', 0, 'x'}
	expect_parse_error_at(
		t,
		transmute(string)invalid_sign_bytes[:],
		.Invalid_Number,
		2,
		1,
	)

	keyword_suffix_bytes := [6]byte{'t', 'r', 'u', 'e', 0, 'x'}
	expect_parse_error_at(
		t,
		transmute(string)keyword_suffix_bytes[:],
		.Invalid_Literal,
		5,
		4,
	)
	keyword_middle_bytes := [5]byte{'t', 'r', 0, 'u', 'e'}
	expect_parse_error_at(
		t,
		transmute(string)keyword_middle_bytes[:],
		.Invalid_Literal,
		4,
		2,
	)
	numeric_n_bytes := [5]byte{'n', 0, 'u', 'l', 'l'}
	expect_parse_error_at(
		t,
		transmute(string)numeric_n_bytes[:],
		.Invalid_Number,
		4,
		0,
	)
	string_bytes := [5]byte{'"', 'a', 0, 'b', '"'}
	expect_parse_error_at(
		t,
		transmute(string)string_bytes[:],
		.Unescaped_Control,
		4,
		2,
	)
}

@(test)
diagnostic_detection_cursor_is_distinct_from_local_cause :: proc(t: ^testing.T) {
	Case :: struct {
		input:      string,
		kind:       Scalar_Parse_Error_Kind,
		detection:  int,
		cause:      int,
		jq_column:  int,
	}
	test_cases := []Case{
		{"1x", .Invalid_Number, 1, 1, 2},
		{"1x ", .Invalid_Number, 2, 1, 3},
		{"1e", .Invalid_Number, 1, 2, 2},
		{"1e ", .Invalid_Number, 2, 2, 3},
		{"1e+", .Invalid_Number, 2, 3, 3},
		{"1e+ ", .Invalid_Number, 3, 3, 4},
		{`"\q"`, .Invalid_Escape, 3, 2, 4},
		{`"\u12xz"`, .Invalid_Unicode_Escape, 7, 5, 8},
	}
	for test_case in test_cases {
		expect_parse_error_at(
			t,
			test_case.input,
			test_case.kind,
			test_case.detection,
			test_case.cause,
		)
		testing.expect_value(t, test_case.detection + 1, test_case.jq_column)
	}
}

@(test)
one_complete_leading_bom_is_stripped_at_document_boundary :: proc(t: ^testing.T) {
	bom_null_bytes := [7]byte{0xef, 0xbb, 0xbf, 'n', 'u', 'l', 'l'}
	parsed, err := parse_scalar(transmute(string)bom_null_bytes[:], context.allocator)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Null)
	value.destroy_value(&parsed)

	bom_invalid_number := [5]byte{0xef, 0xbb, 0xbf, '1', 'x'}
	expect_parse_error_at(
		t,
		transmute(string)bom_invalid_number[:],
		.Invalid_Number,
		4,
		4,
	)

	partial_one := [1]byte{0xef}
	partial_two := [2]byte{0xef, 0xbb}
	mismatch_two := [2]byte{0xef, 'x'}
	mismatch_three := [3]byte{0xef, 0xbb, 'x'}
	expect_parse_error_at(t, transmute(string)partial_one[:], .Expected_Value, 0, 1)
	expect_parse_error_at(t, transmute(string)partial_two[:], .Expected_Value, 1, 2)
	expect_parse_error_at(t, transmute(string)mismatch_two[:], .Malformed_BOM, 1, 1)
	expect_parse_error_at(t, transmute(string)mismatch_three[:], .Malformed_BOM, 2, 2)

	double_bom := [10]byte{
		0xef, 0xbb, 0xbf, 0xef, 0xbb, 0xbf, 'n', 'u', 'l', 'l',
	}
	expect_parse_error_at(
		t,
		transmute(string)double_bom[:],
		.Invalid_Number,
		9,
		3,
	)
	bad_bom_suffix := [3]byte{0xef, 0xbb, 0x20}
	expect_parse_error_at(t, transmute(string)bad_bom_suffix[:], .Malformed_BOM, 2, 2)
	full_then_partial_bom := [5]byte{0xef, 0xbb, 0xbf, 0xef, 0xbb}
	expect_parse_error_at(
		t,
		transmute(string)full_then_partial_bom[:],
		.Invalid_Number,
		4,
		3,
	)
}

@(test)
all_string_escapes_unicode_and_embedded_nul :: proc(t: ^testing.T) {
	expect_string_parse(t, `""`, "")
	expect_string_parse(t, `"\"\\\/\b\f\t\n\r"`, "\"\\/\b\f\t\n\r")
	expect_string_parse(t, `"A\u03bb\uD83D\uDE00\uDC00\u0000Z"`, "Aλ😀�\x00Z")

	parsed, err := parse_scalar(`"a\u0000b"`, context.allocator)
	defer value.destroy_value(&parsed)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	view, ok := value.string_borrowed(&parsed)
	testing.expect(t, ok && len(view) == 3 && view[1] == 0)
}

@(test)
malformed_raw_utf8_matches_jq_point_boundaries :: proc(t: ^testing.T) {
	truncated_bytes := [4]byte{'"', 0xe2, 0x82, '"'}
	truncated := transmute(string)truncated_bytes[:]
	expect_string_parse(t, truncated, "�")

	split_bytes := [5]byte{'"', 0xe2, 0x82, 'A', '"'}
	split := transmute(string)split_bytes[:]
	expect_string_parse(t, split, "�A")

	continuations_bytes := [4]byte{'"', 0x80, 0x81, '"'}
	continuations := transmute(string)continuations_bytes[:]
	expect_string_parse(t, continuations, "��")

	surrogate_bytes := [5]byte{'"', 0xed, 0xa0, 0x80, '"'}
	surrogate := transmute(string)surrogate_bytes[:]
	expect_string_parse(t, surrogate, "�")

	c0 := [4]byte{'"', 0xc0, 0x80, '"'}
	c1 := [4]byte{'"', 0xc1, 0xbf, '"'}
	c2 := [4]byte{'"', 0xc2, 0x80, '"'}
	f0 := [6]byte{'"', 0xf0, 0x90, 0x80, 0x80, '"'}
	f0_overlong := [6]byte{'"', 0xf0, 0x80, 0x80, 0x80, '"'}
	f4 := [6]byte{'"', 0xf4, 0x8f, 0xbf, 0xbf, '"'}
	f4_above_range := [6]byte{'"', 0xf4, 0x90, 0x80, 0x80, '"'}
	f5 := [6]byte{'"', 0xf5, 0x80, 0x80, 0x80, '"'}
	f6 := [6]byte{'"', 0xf6, 0x80, 0x80, 0x80, '"'}
	f7 := [6]byte{'"', 0xf7, 0x80, 0x80, 0x80, '"'}
	boundary_cases := []struct {input, expected: string}{
		{transmute(string)c0[:], "��"},
		{transmute(string)c1[:], "��"},
		{transmute(string)c2[:], "\u0080"},
		{transmute(string)f0[:], "\U00010000"},
		{transmute(string)f0_overlong[:], "�"},
		{transmute(string)f4[:], "\U0010ffff"},
		{transmute(string)f4_above_range[:], "�"},
		{transmute(string)f5[:], "����"},
		{transmute(string)f6[:], "����"},
		{transmute(string)f7[:], "����"},
	}
	for test_case in boundary_cases {
		expect_string_parse(t, test_case.input, test_case.expected)
	}
}

@(test)
malformed_utf8_is_normalized_after_json_escapes_are_decoded :: proc(t: ^testing.T) {
	three_consumed := [5]byte{'"', 0xe2, '\\', 'n', '"'}
	three_separate := [6]byte{'"', 0xe2, 0x82, '\\', 'n', '"'}
	four_consumed_one := [5]byte{'"', 0xf0, '\\', 'n', '"'}
	four_consumed_two := [6]byte{'"', 0xf0, 0x90, '\\', 'n', '"'}
	four_separate := [7]byte{'"', 0xf0, 0x90, 0x80, '\\', 'n', '"'}
	test_cases := []struct {input, expected: string}{
		{transmute(string)three_consumed[:], "�"},
		{transmute(string)three_separate[:], "�\n"},
		{transmute(string)four_consumed_one[:], "�"},
		{transmute(string)four_consumed_two[:], "�"},
		{transmute(string)four_separate[:], "�\n"},
	}
	for test_case in test_cases {
		expect_string_parse(t, test_case.input, test_case.expected)
	}
}

@(test)
exact_whitespace_missing_trailing_and_container_errors :: proc(t: ^testing.T) {
	valid_whitespace := []string{" null ", "\tnull\t", "\rnull\r", "\nnull\n", " \t\r\nnull \t\r\n"}
	for input in valid_whitespace {
		parsed, err := parse_scalar(input, context.allocator)
		testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
		testing.expect_value(t, value.kind_of(&parsed), value.Kind.Null)
		value.destroy_value(&parsed)
	}
	expect_parse_error(t, "\vnull", .Invalid_Number, 0)
	expect_parse_error(t, "null\v", .Invalid_Literal, 4)
	expect_parse_error(t, "null true", .Trailing_Input, 5)
	expect_parse_error(t, "1,", .Trailing_Input, 1)
	expect_parse_error(t, `"one""two"`, .Trailing_Input, 5)
	expect_parse_error(t, "[]", .Array_Not_Supported, 0)
	expect_parse_error(t, "{}", .Object_Not_Supported, 0)
}

@(test)
missing_value_distinguishes_last_detection_byte_from_eof_cause :: proc(t: ^testing.T) {
	expect_parse_error_at(t, "", .Expected_Value, 0, 0)
	expect_parse_error_at(t, " ", .Expected_Value, 0, 1)
	expect_parse_error_at(t, " \t\r\n", .Expected_Value, 3, 4)

	bom_only := [3]byte{0xef, 0xbb, 0xbf}
	bom_space := [4]byte{0xef, 0xbb, 0xbf, ' '}
	bom_whitespace := [7]byte{0xef, 0xbb, 0xbf, ' ', '\t', '\r', '\n'}
	expect_parse_error_at(t, transmute(string)bom_only[:], .Expected_Value, 2, 3)
	expect_parse_error_at(t, transmute(string)bom_space[:], .Expected_Value, 3, 4)
	expect_parse_error_at(t, transmute(string)bom_whitespace[:], .Expected_Value, 6, 7)
}

@(test)
unfinished_and_malformed_string_errors_have_byte_offsets :: proc(t: ^testing.T) {
	expect_parse_error(t, `"abc`, .Unfinished_String, 4)
	expect_parse_error(t, `"abc\`, .Unfinished_String, 5)
	expect_parse_error(t, `"\q`, .Unfinished_String, 3)
	expect_parse_error(t, `"\u12`, .Unfinished_String, 5)
	unfinished_nul := [2]byte{'"', 0}
	unfinished_control := [3]byte{'"', 'a', 0x1f}
	unfinished_utf8 := [3]byte{'"', 0xf5, 0x80}
	early_three_matched := [4]byte{'"', 0xe2, 'A', '"'}
	early_three_unfinished := [3]byte{'"', 0xe2, 'A'}
	early_four_matched := [5]byte{'"', 0xf0, 0x90, 'A', '"'}
	early_four_unfinished := [4]byte{'"', 0xf0, 0x90, 'A'}
	expect_parse_error(t, transmute(string)unfinished_nul[:], .Unfinished_String, 2)
	expect_parse_error(t, transmute(string)unfinished_control[:], .Unfinished_String, 3)
	expect_parse_error(t, transmute(string)unfinished_utf8[:], .Unfinished_String, 3)
	expect_string_parse(t, transmute(string)early_three_matched[:], "�")
	expect_parse_error(t, transmute(string)early_three_unfinished[:], .Unfinished_String, 3)
	expect_string_parse(t, transmute(string)early_four_matched[:], "�")
	expect_parse_error(t, transmute(string)early_four_unfinished[:], .Unfinished_String, 4)
	expect_parse_error(t, `"\u12xz"`, .Invalid_Unicode_Escape, 5)
	invalid_escapes := []struct {
		input:  string,
		offset: int,
	}{
		{`"\q"`, 2},
		{`  "\?"`, 4},
		{`  "λraw\z"`, 9},
	}
	for test_case in invalid_escapes {
		expect_parse_error(t, test_case.input, .Invalid_Escape, test_case.offset)
	}
	expect_parse_error(t, `"\uD800"`, .Invalid_Surrogate_Pair, 7)
	expect_parse_error(t, `"\uD800\u0041"`, .Invalid_Surrogate_Pair, 9)

	for control := byte(0); control < 0x20; control += 1 {
		control_bytes := [3]byte{'"', control, '"'}
		input := transmute(string)control_bytes[:]
		expect_parse_error(t, input, .Unescaped_Control, 1)
	}
}

@(test)
unicode_escape_errors_prefer_observed_bytes_over_eof :: proc(t: ^testing.T) {
	Case :: struct {
		input:  string,
		kind:   Scalar_Parse_Error_Kind,
		offset: int,
	}
	test_cases := []Case{
		{`"\u"`, .Invalid_Unicode_Escape, 3},
		{`"\u1"`, .Invalid_Unicode_Escape, 4},
		{`"\u12"`, .Invalid_Unicode_Escape, 5},
		{`"\u123"`, .Invalid_Unicode_Escape, 6},
		{`"\u`, .Unfinished_String, 3},
		{`"\u1`, .Unfinished_String, 4},
		{`"\u12`, .Unfinished_String, 5},
		{`"\u123`, .Unfinished_String, 6},
		{`  "\u"`, .Invalid_Unicode_Escape, 5},
		{`  "\u1"`, .Invalid_Unicode_Escape, 6},
		{`  "\u12"`, .Invalid_Unicode_Escape, 7},
		{`  "\u123"`, .Invalid_Unicode_Escape, 8},
		{`"\u12"ffff`, .Invalid_Unicode_Escape, 5},
	}
	for test_case in test_cases {
		expect_parse_error(t, test_case.input, test_case.kind, test_case.offset)
	}
}

allocator_probe :: struct {
	backing:        runtime.Allocator,
	allocations:    int,
	frees:          int,
	live:           int,
	fail_after:     int,
	allocation_limit: int,
	maximum_request: int,
	free_failures_remaining: int,
	retired:        bool,
	called_retired: bool,
	nil_success:    bool,
	short_success:  bool,
}

allocator_probe_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	probe := cast(^allocator_probe)data
	if probe.retired {
		probe.called_retired = true
		return nil, .Invalid_Argument
	}
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		probe.maximum_request = max(probe.maximum_request, size)
		if probe.allocations == probe.fail_after ||
		   (probe.allocation_limit > 0 && size > probe.allocation_limit) {
			probe.allocations += 1
			return nil, .Out_Of_Memory
		}
		probe.allocations += 1
		if probe.nil_success {
			return nil, nil
		}
		if probe.short_success {
			short_size := max(size - 1, 0)
			result, err := probe.backing.procedure(
				probe.backing.data,
				mode,
				short_size,
				alignment,
				old_memory,
				old_size,
				location,
			)
			if err == nil && len(result) > 0 {
				probe.live += 1
			}
			return result, err
		}
		result, err := probe.backing.procedure(
			probe.backing.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			location,
		)
		if err == nil && len(result) > 0 {
			probe.live += 1
		}
		return result, err
	case .Free:
		probe.frees += 1
		if probe.free_failures_remaining > 0 {
			probe.free_failures_remaining -= 1
			return nil, .Invalid_Pointer
		}
		result, err := probe.backing.procedure(
			probe.backing.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			location,
		)
		if err == nil {
			probe.live -= 1
		}
		return result, err
	}
	return probe.backing.procedure(
		probe.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(test)
string_scratch_is_bounded_by_quoted_token :: proc(t: ^testing.T) {
	WHITESPACE_BYTES :: 1_000_000
	input_bytes := make([]byte, WHITESPACE_BYTES + 3)
	defer delete(input_bytes)
	input_bytes[0], input_bytes[1], input_bytes[2] = '"', 'x', '"'
	for i in 3..<len(input_bytes) {
		input_bytes[i] = ' '
	}

	temporary_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		allocation_limit = 3,
	}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = probe_allocator(&temporary_probe)
	parsed, err := parse_scalar(transmute(string)input_bytes, context.allocator)
	context.temp_allocator = saved_temp_allocator
	defer value.destroy_value(&parsed)

	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.String)
	testing.expect_value(t, temporary_probe.allocations, 1)
	testing.expect_value(t, temporary_probe.maximum_request, 3)
	testing.expect_value(t, temporary_probe.frees, 1)
	testing.expect_value(t, temporary_probe.live, 0)
}

@(test)
scratch_allocation_requires_the_exact_requested_slice :: proc(t: ^testing.T) {
	saved_temp_allocator := context.temp_allocator

	nil_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		nil_success = true,
	}
	context.temp_allocator = probe_allocator(&nil_probe)
	nil_result, nil_error := parse_scalar(`"nil"`, context.allocator)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, value.kind_of(&nil_result), value.Kind.Invalid)
	testing.expect_value(t, nil_error.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, nil_error.detection_offset, 0)
	testing.expect_value(t, nil_probe.allocations, 1)
	testing.expect_value(t, nil_probe.frees, 0)
	testing.expect_value(t, nil_probe.live, 0)

	short_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
	}
	context.temp_allocator = probe_allocator(&short_probe)
	short_result, short_error := parse_scalar(`"short"`, context.allocator)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, value.kind_of(&short_result), value.Kind.Invalid)
	testing.expect_value(t, short_error.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, short_probe.allocations, 1)
	testing.expect_value(t, short_probe.frees, 1)
	testing.expect_value(t, short_probe.live, 0)

	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 2,
		short_success = true,
	}
	context.temp_allocator = probe_allocator(&retry_probe)
	retry_result, retry_error := parse_scalar(`"retry"`, context.allocator)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, value.kind_of(&retry_result), value.Kind.Invalid)
	testing.expect_value(t, retry_error.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, retry_error.cause_kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, retry_probe.live, 1)
	testing.expect_value(
		t,
		destroy_scalar_parse_error(&retry_error),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(t, retry_error.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, retry_probe.live, 1)
	testing.expect_value(t, destroy_scalar_parse_error(&retry_error), runtime.Allocator_Error.None)
	testing.expect_value(t, retry_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, retry_probe.live, 0)
}

@(test)
caller_allocator_exact_length_failures_cover_strings_and_numbers :: proc(t: ^testing.T) {
	inputs := [2]string{`"caller"`, "1.25"}
	for input in inputs {
		nil_probe := allocator_probe{
			backing = context.allocator,
			fail_after = max(int),
			nil_success = true,
		}
		nil_result, nil_error := parse_scalar(input, probe_allocator(&nil_probe))
		testing.expect_value(t, value.kind_of(&nil_result), value.Kind.Invalid)
		testing.expect_value(t, nil_error.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
		testing.expect_value(t, nil_probe.allocations, 1)
		testing.expect_value(t, nil_probe.frees, 0)
		testing.expect_value(t, nil_probe.live, 0)

		short_probe := allocator_probe{
			backing = context.allocator,
			fail_after = max(int),
			short_success = true,
		}
		short_result, short_error := parse_scalar(input, probe_allocator(&short_probe))
		testing.expect_value(t, value.kind_of(&short_result), value.Kind.Invalid)
		testing.expect_value(t, short_error.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
		testing.expect_value(t, short_probe.allocations, 1)
		testing.expect_value(t, short_probe.frees, 1)
		testing.expect_value(t, short_probe.live, 0)

		retry_probe := allocator_probe{
			backing = context.allocator,
			fail_after = max(int),
			free_failures_remaining = 1,
			short_success = true,
		}
		retry_result, retry_error := parse_scalar(input, probe_allocator(&retry_probe))
		testing.expect_value(t, value.kind_of(&retry_result), value.Kind.Invalid)
		testing.expect_value(t, retry_error.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
		testing.expect_value(t, retry_error.cause_kind, Scalar_Parse_Error_Kind.Allocation_Failure)
		testing.expect_value(t, retry_probe.frees, 1)
		testing.expect_value(t, retry_probe.live, 1)
		testing.expect_value(t, destroy_scalar_parse_error(&retry_error), runtime.Allocator_Error.None)
		testing.expect_value(t, retry_error.kind, Scalar_Parse_Error_Kind.None)
		testing.expect_value(t, retry_probe.frees, 2)
		testing.expect_value(t, retry_probe.live, 0)
	}
}

@(test)
scratch_free_failure_retains_every_retryable_handle :: proc(t: ^testing.T) {
	temporary_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	value_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = probe_allocator(&temporary_probe)
	parsed, err := parse_scalar(`"retryable"`, probe_allocator(&value_probe))
	context.temp_allocator = saved_temp_allocator

	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, err.cause_kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, temporary_probe.live, 1)
	testing.expect_value(t, value_probe.live, 1)

	first_cleanup := destroy_scalar_parse_error(&err)
	testing.expect_value(t, first_cleanup, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, temporary_probe.live, 0)
	testing.expect_value(t, value_probe.live, 1)

	testing.expect_value(t, destroy_scalar_parse_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, temporary_probe.live, 0)
	testing.expect_value(t, value_probe.live, 0)
	testing.expect_value(t, temporary_probe.frees, 2)
	testing.expect_value(t, value_probe.frees, 2)
}

@(test)
scratch_cleanup_supersedes_constructor_failure_without_losing_it :: proc(t: ^testing.T) {
	temporary_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	value_probe := allocator_probe{backing = context.allocator, fail_after = 0}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = probe_allocator(&temporary_probe)
	parsed, err := parse_scalar(`"construction"`, probe_allocator(&value_probe))
	context.temp_allocator = saved_temp_allocator

	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, err.cause_kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, temporary_probe.live, 1)
	testing.expect_value(t, value_probe.live, 0)
	testing.expect_value(t, value_probe.allocations, 1)
	testing.expect_value(t, value_probe.frees, 0)

	testing.expect_value(t, destroy_scalar_parse_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, temporary_probe.live, 0)
}

@(test)
scratch_and_constructor_cleanup_failures_remain_independently_retryable :: proc(t: ^testing.T) {
	temporary_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	value_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 2,
		short_success = true,
	}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = probe_allocator(&temporary_probe)
	parsed, err := parse_scalar(`"both-retryable"`, probe_allocator(&value_probe))
	context.temp_allocator = saved_temp_allocator

	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, err.cause_kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, temporary_probe.live, 1)
	testing.expect_value(t, value_probe.live, 1)

	first_cleanup := destroy_scalar_parse_error(&err)
	testing.expect_value(t, first_cleanup, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, temporary_probe.live, 0)
	testing.expect_value(t, value_probe.live, 1)

	testing.expect_value(t, destroy_scalar_parse_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, temporary_probe.live, 0)
	testing.expect_value(t, value_probe.live, 0)
	testing.expect_value(t, temporary_probe.frees, 2)
	testing.expect_value(t, value_probe.frees, 3)
}

probe_allocator :: proc(probe: ^allocator_probe) -> runtime.Allocator {
	return {procedure = allocator_probe_proc, data = probe}
}

@(test)
numeric_trailing_input_retires_or_retains_the_constructed_value :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	parsed, err := parse_scalar("1 true", probe_allocator(&probe))
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Trailing_Input)
	testing.expect_value(t, probe.allocations, 1)
	testing.expect_value(t, probe.frees, 1)
	testing.expect_value(t, probe.live, 0)

	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	retry_result, retry_error := parse_scalar("1 true", probe_allocator(&retry_probe))
	testing.expect_value(t, value.kind_of(&retry_result), value.Kind.Invalid)
	testing.expect_value(t, retry_error.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, retry_error.cause_kind, Scalar_Parse_Error_Kind.Trailing_Input)
	testing.expect_value(t, retry_probe.live, 1)
	testing.expect_value(t, destroy_scalar_parse_error(&retry_error), runtime.Allocator_Error.None)
	testing.expect_value(t, retry_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, retry_probe.live, 0)
}

@(test)
allocation_failure_sweep_is_inert_and_leak_free :: proc(t: ^testing.T) {
	temporary_probe := allocator_probe{backing = context.allocator, fail_after = 0}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = probe_allocator(&temporary_probe)
	temporary_result, temporary_error := parse_scalar(`"allocated"`, context.allocator)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, temporary_error.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, temporary_error.detection_offset, 0)
	testing.expect_value(t, value.kind_of(&temporary_result), value.Kind.Invalid)
	testing.expect_value(t, temporary_probe.frees, 0)

	value_probe := allocator_probe{backing = context.allocator, fail_after = 0}
	value_result, value_error := parse_scalar(`"allocated"`, probe_allocator(&value_probe))
	testing.expect_value(t, value_error.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, value_error.detection_offset, 0)
	testing.expect_value(t, value.kind_of(&value_result), value.Kind.Invalid)
	testing.expect_value(t, value_probe.frees, 0)

	number_probe := allocator_probe{backing = context.allocator, fail_after = 0}
	number, number_error := parse_scalar("1.25", probe_allocator(&number_probe))
	testing.expect_value(t, number_error.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, value.kind_of(&number), value.Kind.Invalid)
	testing.expect_value(t, number_probe.frees, 0)

	trailing_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	trailing, trailing_error := parse_scalar(`"allocated" x`, probe_allocator(&trailing_probe))
	testing.expect_value(t, trailing_error.kind, Scalar_Parse_Error_Kind.Trailing_Input)
	testing.expect_value(t, value.kind_of(&trailing), value.Kind.Invalid)
	testing.expect_value(t, trailing_probe.allocations, 0)
	testing.expect_value(t, trailing_probe.allocations, trailing_probe.frees)
}

@(test)
caller_allocator_provenance_take_and_destroy :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	parsed, err := parse_scalar(`"owned"`, probe_allocator(&probe))
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, probe.allocations, 1)
	testing.expect_value(t, probe.frees, 0)

	moved := value.take_value(&parsed)
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	view, ok := value.string_borrowed(&moved)
	testing.expect(t, ok && view == "owned")
	saved_allocator := context.allocator
	context.allocator = runtime.Allocator{}
	testing.expect_value(t, value.destroy_value(&moved), runtime.Allocator_Error.None)
	context.allocator = saved_allocator
	testing.expect_value(t, probe.frees, 1)
	testing.expect_value(t, value.kind_of(&moved), value.Kind.Invalid)

	probe.retired = true
	testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&moved), runtime.Allocator_Error.None)
	testing.expect(t, !probe.called_retired)
}

@(test)
json_tests_run_with_allocation_tracking :: proc(t: ^testing.T) {
	when TRACKING_MEMORY {
		tracker := cast(^mem.Tracking_Allocator)context.allocator.data
		testing.expect(t, tracker != nil)
	} else {
		testing.expect(t, false, "json tests require Odin allocation tracking")
	}
}
