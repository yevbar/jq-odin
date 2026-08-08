package json

import "core:testing"
import "jq:value"

@(test)
parse_next_value_preserves_stream_order_and_boundaries :: proc(t: ^testing.T) {
	input := "\ufeff 1\n {\"a\":2} \t [3,null] "
	start := 0
	expected := [3]string{"1", "{\"a\":2}", "[3,null]"}
	for expected_text in expected {
		parsed, next, done, err := parse_next_value(input, start, context.allocator)
		testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
		testing.expect(t, !done)
		serializer: Compact_Serializer
		testing.expect(t, init_compact_serializer(&serializer, context.allocator))
		result: Compact_Result
		print_error := serialize_compact(&serializer, &parsed, &result)
		testing.expect_value(t, print_error.kind, Compact_Error_Kind.None)
		printed, printed_ok := compact_result_bytes(&result)
		testing.expect(t, printed_ok && printed == expected_text)
		testing.expect_value(t, destroy_compact_result(&result), nil)
		testing.expect_value(t, destroy_compact_serializer(&serializer), nil)
		testing.expect_value(t, value.destroy_value(&parsed), nil)
		testing.expect(t, next > start)
		start = next
	}

	parsed, next, done, err := parse_next_value(input, start, context.allocator)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect(t, done && next == len(input))
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
}

@(test)
parse_next_value_reports_stream_errors_without_consuming_a_later_value :: proc(t: ^testing.T) {
	input := "true @ 2"
	first, start, done, first_error := parse_next_value(input, 0, context.allocator)
	testing.expect_value(t, first_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect(t, !done && start == 5)
	testing.expect_value(t, value.destroy_value(&first), nil)

	failed, next, failed_done, err := parse_next_value(input, start, context.allocator)
	testing.expect_value(t, value.kind_of(&failed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Invalid_Number)
	testing.expect(t, !failed_done && next == 6)
	testing.expect_value(t, destroy_scalar_parse_error(&err), nil)
}

@(test)
parse_next_value_rejects_bom_outside_source_boundary :: proc(t: ^testing.T) {
	input := "1 \ufeff 2"
	first, next, _, first_error := parse_next_value(input, 0, context.allocator)
	testing.expect_value(t, first_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.destroy_value(&first), nil)

	second, _, done, err := parse_next_value(input, next, context.allocator)
	testing.expect_value(t, value.kind_of(&second), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Invalid_Number)
	testing.expect(t, !done)
	testing.expect_value(t, destroy_scalar_parse_error(&err), nil)
}

@(test)
parse_next_value_owns_result_after_borrowed_source_is_released :: proc(t: ^testing.T) {
	input_text := `{"text":"é","items":[null,2]}`
	input_bytes := make([]byte, len(input_text))
	copy(input_bytes, input_text)
	parsed, next, done, err := parse_next_value(
		transmute(string)input_bytes,
		0,
		context.allocator,
	)
	// Poison the source allocation before releasing it. A result that borrows
	// input_bytes would serialize the marker bytes instead of the original text.
	for &byte in input_bytes do byte = 0xA5
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect(t, !done && next > 0)
	defer value.destroy_value(&parsed)

	serializer: Compact_Serializer
	testing.expect(t, init_compact_serializer(&serializer, context.allocator))
	defer destroy_compact_serializer(&serializer)
	result: Compact_Result
	print_error := serialize_compact(&serializer, &parsed, &result)
	testing.expect_value(t, print_error.kind, Compact_Error_Kind.None)
	if print_error.kind == .None {
		printed, ok := compact_result_bytes(&result)
		testing.expect(t, ok && printed == `{"text":"é","items":[null,2]}`)
		testing.expect_value(t, destroy_compact_result(&result), nil)
	}
	delete(input_bytes)
}
