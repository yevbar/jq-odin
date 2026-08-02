package syntax

import "base:runtime"
import diagnostic "jq:diagnostic"
import "core:mem"
import "core:strings"
import "core:testing"

@(private="package")
expect_string_filter :: proc(
	t: ^testing.T,
	text, expected: string,
	start := 0,
	end := -1,
) {
	actual_end := end
	if actual_end < 0 do actual_end = len(text)
	parser: Parser
	source, outcome := parse_test_filter(t, &parser, text)
	expect_parse_success(t, &parser, outcome)
	node := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, node.kind, Node_Kind.String)
	testing.expect(t, node.has_string_text)
	testing.expect_value(t, node.string_text, expected)
	expect_span(t, source, node.span, start, actual_end)
	testing.expect_value(t, parser.string_allocations.count, 1)
	testing.expect(t, raw_data(parser.string_allocations.storage[0].memory) != nil)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_plain_string_decodes_every_escape_unicode_and_exact_spans :: proc(t: ^testing.T) {
	expect_string_filter(t, `"plain"`, "plain")
	expect_string_filter(t, `""`, "")
	expect_string_filter(t, `"\"\\\/\b\f\n\r\t"`, "\"\\/\b\f\n\r\t")
	expect_string_filter(t, `"\u0041\u03bc"`, "Aμ")
	expect_string_filter(t, `"\ud83d\ude00"`, "😀")
	expect_string_filter(t, `"raw μ 😀"`, "raw μ 😀")
	expect_string_filter(t, `"\udc00"`, "�")
	expect_string_filter(t, `"\udfff"`, "�")
	expect_string_filter(t, `"\n\udc00\t"`, "\n�\t")

	nul := [3]byte{'a', 0, 'b'}
	expect_string_filter(t, `"a\u0000b"`, transmute(string)nul[:])

	controls := [34]byte{}
	controls[0] = '"'
	for control in 0..<32 do controls[control+1] = u8(control)
	controls[33] = '"'
	expect_string_filter(t, transmute(string)controls[:], transmute(string)controls[1:33])

	malformed := [8]byte{'"', 0xff, 0xc0, 0xaf, 0xe2, 'x', 0x80, '"'}
	replaced := [16]byte{
		0xef, 0xbf, 0xbd,
		0xef, 0xbf, 0xbd,
		0xef, 0xbf, 0xbd,
		0xef, 0xbf, 0xbd, 'x',
		0xef, 0xbf, 0xbd,
	}
	expect_string_filter(t, transmute(string)malformed[:], transmute(string)replaced[:])

	prefixed_malformed := [10]byte{'"', '\\', 'n', 0xff, 0xe2, 'x', 0x80, '\\', 't', '"'}
	prefixed_replaced := [12]byte{
		'\n',
		0xef, 0xbf, 0xbd,
		0xef, 0xbf, 0xbd, 'x',
		0xef, 0xbf, 0xbd,
		'\t',
	}
	expect_string_filter(
		t,
		transmute(string)prefixed_malformed[:],
		transmute(string)prefixed_replaced[:],
	)
}

@(test)
malformed_utf8_progress_matches_jq :: proc(t: ^testing.T) {
	// The checksum-pinned jq 1.8.1 oracle
	// 020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d
	// follows jvp_utf8_next's distinct progress branches: invalid leads consume
	// one byte, truncation consumes the remaining prefix, bad continuations
	// consume the valid prefix, and completed invalid units consume their full
	// width (upstream/jq/src/jv_unicode.c:41-74).
	replacement := [3]byte{0xef, 0xbf, 0xbd}
	two_replacements := [6]byte{0xef, 0xbf, 0xbd, 0xef, 0xbf, 0xbd}

	truncated_two := [3]byte{'"', 0xc2, '"'}
	truncated_two_expected := replacement
	truncated_three := [4]byte{'"', 0xe2, 0x80, '"'}
	truncated_three_expected := replacement
	truncated_four := [5]byte{'"', 0xf0, 0x9f, 0x98, '"'}
	truncated_four_expected := replacement
	stray_continuations := [4]byte{'"', 0x80, 0xbf, '"'}
	stray_continuations_expected := two_replacements
	invalid_leads := [4]byte{'"', 0xc0, 0xaf, '"'}
	invalid_leads_expected := two_replacements
	completed_overlong := [5]byte{'"', 0xe0, 0x80, 0xaf, '"'}
	completed_overlong_expected := replacement
	completed_surrogate := [5]byte{'"', 0xed, 0xa0, 0x80, '"'}
	completed_surrogate_expected := replacement
	completed_out_of_range := [6]byte{'"', 0xf4, 0x90, 0x80, 0x80, '"'}
	completed_out_of_range_expected := replacement

	bad_two_continuation := [5]byte{'"', 0xc2, 'A', 0x80, '"'}
	bad_two_continuation_expected := [7]byte{
		0xef, 0xbf, 0xbd, 'A', 0xef, 0xbf, 0xbd,
	}
	bad_three_first := [5]byte{'"', 0xe2, 'A', 0x80, '"'}
	bad_three_first_expected := bad_two_continuation_expected
	bad_three_second := [6]byte{'"', 0xe2, 0x80, 'A', 0x80, '"'}
	bad_three_second_expected := bad_two_continuation_expected
	bad_four_first := [6]byte{'"', 0xf0, 'A', 0x80, 0x80, '"'}
	bad_four_first_expected := [10]byte{
		0xef, 0xbf, 0xbd, 'A',
		0xef, 0xbf, 0xbd,
		0xef, 0xbf, 0xbd,
	}
	bad_four_second := [6]byte{'"', 0xf0, 0x9f, 'A', 0x80, '"'}
	bad_four_second_expected := bad_two_continuation_expected
	bad_four_third := [7]byte{'"', 0xf0, 0x9f, 0x98, 'A', 0x80, '"'}
	bad_four_third_expected := bad_two_continuation_expected

	adjacent_invalid := [7]byte{'"', 0xe2, 0x80, 0xf0, 0x9f, 0x98, '"'}
	adjacent_invalid_expected := two_replacements
	valid_utf8_neighbors := [10]byte{
		'"', 0xc2, 0xbc, 0xe2, 0x80, 0xf0, 0x9f, 0x98, 0x80, '"',
	}
	valid_utf8_neighbors_expected := [9]byte{
		0xc2, 0xbc, 0xef, 0xbf, 0xbd, 0xf0, 0x9f, 0x98, 0x80,
	}
	escaped_quote_neighbors := [9]byte{
		'"', 0xe2, 0x80, '\\', '"', 0xc2, '\\', '"', '"',
	}
	escaped_quote_neighbors_expected := [8]byte{
		0xef, 0xbf, 0xbd, '"', 0xef, 0xbf, 0xbd, '"',
	}
	mixed_escapes := [14]byte{
		'"', 'A', 0xe2, 0x80, '\\', 'n', 'B', 0xf0, 0x9f, 0x98, '\\', 't', 'C', '"',
	}
	mixed_escapes_expected := [11]byte{
		'A', 0xef, 0xbf, 0xbd, '\n', 'B', 0xef, 0xbf, 0xbd, '\t', 'C',
	}

	Case :: struct { source, expected: string }
	cases := [?]Case{
		{transmute(string)truncated_two[:], transmute(string)truncated_two_expected[:]},
		{transmute(string)truncated_three[:], transmute(string)truncated_three_expected[:]},
		{transmute(string)truncated_four[:], transmute(string)truncated_four_expected[:]},
		{transmute(string)stray_continuations[:], transmute(string)stray_continuations_expected[:]},
		{transmute(string)invalid_leads[:], transmute(string)invalid_leads_expected[:]},
		{transmute(string)completed_overlong[:], transmute(string)completed_overlong_expected[:]},
		{transmute(string)completed_surrogate[:], transmute(string)completed_surrogate_expected[:]},
		{transmute(string)completed_out_of_range[:], transmute(string)completed_out_of_range_expected[:]},
		{transmute(string)bad_two_continuation[:], transmute(string)bad_two_continuation_expected[:]},
		{transmute(string)bad_three_first[:], transmute(string)bad_three_first_expected[:]},
		{transmute(string)bad_three_second[:], transmute(string)bad_three_second_expected[:]},
		{transmute(string)bad_four_first[:], transmute(string)bad_four_first_expected[:]},
		{transmute(string)bad_four_second[:], transmute(string)bad_four_second_expected[:]},
		{transmute(string)bad_four_third[:], transmute(string)bad_four_third_expected[:]},
		{transmute(string)adjacent_invalid[:], transmute(string)adjacent_invalid_expected[:]},
		{transmute(string)valid_utf8_neighbors[:], transmute(string)valid_utf8_neighbors_expected[:]},
		{transmute(string)escaped_quote_neighbors[:], transmute(string)escaped_quote_neighbors_expected[:]},
		{transmute(string)mixed_escapes[:], transmute(string)mixed_escapes_expected[:]},
	}
	for test_case in cases {
		expect_string_filter(t, test_case.source, test_case.expected)
	}
}

@(test)
test_plain_strings_are_terms_at_existing_precedence :: proc(t: ^testing.T) {
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, `"a"? | ("b", "c").x`)
	expect_parse_success(t, &parser, outcome)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Pipe)
	left := parser.nodes.storage[int(root.left)]
	testing.expect_value(t, left.kind, Node_Kind.Optional)
	testing.expect_value(t, parser.nodes.storage[int(left.child)].kind, Node_Kind.String)
	right := parser.nodes.storage[int(root.right)]
	testing.expect_value(t, right.kind, Node_Kind.Field)
	group := parser.nodes.storage[int(right.child)]
	testing.expect_value(t, group.kind, Node_Kind.Parenthesized)
	comma := parser.nodes.storage[int(group.child)]
	testing.expect_value(t, comma.kind, Node_Kind.Comma)
	testing.expect_value(t, parser.nodes.storage[int(comma.left)].string_text, "b")
	testing.expect_value(t, parser.nodes.storage[int(comma.right)].string_text, "c")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_grouped_string_escape_diagnostics :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		start, end: int,
		message: string,
	}
	cases := [?]Case{
		{`"\q"`, 1, 3, "Invalid escape"},
		{`"\u"`, 1, 3, "Invalid \\uXXXX escape"},
		{`"\u12"`, 1, 5, "Invalid \\uXXXX escape"},
		{`"\u12x4"`, 1, 7, "Invalid characters in \\uXXXX escape"},
		{`"\ud800"`, 1, 7, "Invalid \\uXXXX\\uXXXX surrogate pair escape"},
		{`"\ud800\u0041"`, 1, 13, "Invalid \\uXXXX\\uXXXX surrogate pair escape"},
		{`"\udc00\ud800"`, 1, 13, "Invalid \\uXXXX\\uXXXX surrogate pair escape"},
		{`"\u0041\q"`, 1, 9, "Invalid escape"},
		{`"\n\u"`, 1, 5, "Invalid \\uXXXX escape"},
		{`"\t\u12"`, 1, 7, "Invalid \\uXXXX escape"},
		{`"\u0041\u12x4"`, 1, 13, "Invalid characters in \\uXXXX escape"},
		{`"\u0041\ud800"`, 1, 13, "Invalid \\uXXXX\\uXXXX surrogate pair escape"},
		{`"\n\t\/\q"`, 1, 9, "Invalid escape"},
		{`"\udc00\u0041\q"`, 1, 15, "Invalid escape"},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Lexical_Error)
		testing.expect_value(t, outcome.error.expected, Parse_Expectation.Close_String)
		testing.expect_value(t, outcome.error.message, test_case.message)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		for node in parser_nodes(&parser) {
			testing.expect(t, node.kind != .String)
		}
		testing.expect_value(t, parser.string_allocations.count, 0)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_plain_string_rejects_interpolation_and_unterminated_forms :: proc(t: ^testing.T) {
	Case :: struct { text: string, start, end: int, kind: Parse_Error_Kind, message: string }
	cases := [?]Case{
		{`"a\(.)b"`, 2, 4, .Unexpected_Token, "string interpolation is not supported"},
		{`"abc\`, 4, 5, .Lexical_Error, "Invalid escape"},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, test_case.kind)
		testing.expect_value(t, outcome.error.message, test_case.message)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_genuinely_unterminated_strings_point_at_opening_delimiter :: proc(t: ^testing.T) {
	cases := [?]string{
		`"`,
		`"abc`,
		`"μ😀`,
		`"valid\n`,
	}
	for text in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_End)
		testing.expect_value(t, outcome.error.expected, Parse_Expectation.Close_String)
		testing.expect_value(t, outcome.error.message, "unterminated string literal")
		expect_span(t, source, outcome.error.span, 0, 1)
		testing.expect_value(t, parser.string_allocations.count, 0)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}

	raw := [8]byte{'"', 'a', '\n', 1, '\r', '\t', 0, 'b'}
	parser: Parser
	source, outcome := parse_test_filter(t, &parser, transmute(string)raw[:])
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
	testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_End)
	testing.expect_value(t, outcome.error.expected, Parse_Expectation.Close_String)
	testing.expect_value(t, outcome.error.message, "unterminated string literal")
	expect_span(t, source, outcome.error.span, 0, 1)
	testing.expect_value(t, parser.string_allocations.count, 0)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_unclosed_malformed_escapes_keep_grouped_offending_spans :: proc(t: ^testing.T) {
	Case :: struct { text: string, end: int, message: string }
	cases := [?]Case{
		{`"\q`, 3, "Invalid escape"},
		{`"\u`, 3, "Invalid \\uXXXX escape"},
		{`"\u12`, 5, "Invalid \\uXXXX escape"},
		{`"\u12x4`, 7, "Invalid characters in \\uXXXX escape"},
		{`"\ud800`, 7, "Invalid \\uXXXX\\uXXXX surrogate pair escape"},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Lexical_Error)
		testing.expect_value(t, outcome.error.expected, Parse_Expectation.Close_String)
		testing.expect_value(t, outcome.error.message, test_case.message)
		expect_span(t, source, outcome.error.span, 1, test_case.end)
		testing.expect_value(t, parser.string_allocations.count, 0)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_decoded_string_storage_survives_source_mutation_and_release :: proc(t: ^testing.T) {
	original := [7]byte{'"', 'k', 'e', 'p', 't', 0xff, '"'}
	owned, allocation_error := make([]byte, len(original))
	testing.expect(t, allocation_error == nil)
	copy(owned, original[:])
	parser: Parser
	source := diagnostic.borrow_source("<owned-string>", transmute(string)owned)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	expect_parse_success(t, &parser, outcome)
	text := parser.nodes.storage[int(outcome.root)].string_text
	expected := [7]byte{'k', 'e', 'p', 't', 0xef, 0xbf, 0xbd}
	testing.expect_value(t, text, transmute(string)expected[:])
	for &byte in owned do byte = 'x'
	testing.expect_value(t, text, transmute(string)expected[:])
	delete(owned)
	testing.expect_value(t, text, transmute(string)expected[:])
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_string_allocation_failures_are_atomic_and_leak_free :: proc(t: ^testing.T) {
	text :: `"one", "two\u0000", "三"`
	baseline_data := Test_Allocator{backing = context.allocator, alive = true}
	baseline: Parser
	_, baseline_outcome := parse_test_filter(t, &baseline, text, test_allocator(&baseline_data))
	expect_parse_success(t, &baseline, baseline_outcome)
	allocation_points := baseline_data.request_count
	testing.expect(t, allocation_points >= 6)
	testing.expect_value(t, destroy_parser(&baseline), runtime.Allocator_Error.None)

	for fail_at in 1..=allocation_points {
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		data := Test_Allocator{
			backing = mem.tracking_allocator(&tracker),
			fail_at = fail_at,
			alive = true,
		}
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text, test_allocator(&data))
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		testing.expect_value(t, len(tracker.allocation_map), 0)
		mem.tracking_allocator_destroy(&tracker)
	}

	nil_parser: Parser
	_, nil_outcome := parse_test_filter(t, &nil_parser, `"x"`, runtime.Allocator{})
	testing.expect_value(t, nil_outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, destroy_parser(&nil_parser), runtime.Allocator_Error.None)
}

@(test)
test_short_string_allocation_and_free_failure_are_retryable :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	data := Test_Allocator{backing = mem.tracking_allocator(&tracker), alive = true}
	parser: Parser
	testing.expect(t, init_parser(
		&parser,
		diagnostic.borrow_source("<short-string>", `"abc"`),
		test_allocator(&data),
	))
	// Request 1 is scanner state, request 2 is decoded text.
	data.short_at = 2
	data.free_failures_remaining = 1
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect(t, parser.pending_string_text != nil)
	testing.expect_value(t, parser.nodes.count, 0)
	copy_parser := parser
	expect_invalid_parser_copy(t, &copy_parser)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_string_private_registry_ignores_public_payload_corruption :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	data := Test_Allocator{backing = mem.tracking_allocator(&tracker), alive = true}
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, `"a"|"bb"|"ccc"`, test_allocator(&data))
	expect_parse_success(t, &parser, outcome)
	strings_found: [3]^Node
	count := 0
	for &node in parser_nodes(&parser) {
		if node.kind == .String {
			strings_found[count] = &node
			count += 1
		}
	}
	testing.expect_value(t, count, 3)
	stack := [3]byte{'x', 0, 'y'}
	strings_found[0].string_text = strings_found[1].string_text
	strings_found[0].has_string_text = false
	strings_found[1].string_text = transmute(string)stack[:]
	strings_found[2].string_text = "static"
	strings_found[2].has_string_text = false
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_long_string_scanning_and_decoding_are_iterative :: proc(t: ^testing.T) {
	payload, payload_error := strings.repeat(`a\u03bc`, 100_000)
	testing.expect(t, payload_error == nil)
	defer delete(payload)
	text, text_error := strings.concatenate([]string{`"`, payload, `"`})
	testing.expect(t, text_error == nil)
	defer delete(text)
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text)
	expect_parse_success(t, &parser, outcome)
	node := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, len(node.string_text), 300_000)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(private="package")
nested_string_filter :: proc(t: ^testing.T, depth: int, term: string) -> string {
	opens, opens_error := strings.repeat("(", depth)
	testing.expect(t, opens_error == nil)
	closes, closes_error := strings.repeat(")", depth)
	testing.expect(t, closes_error == nil)
	result, result_error := strings.concatenate([]string{opens, term, closes})
	testing.expect(t, result_error == nil)
	delete(opens)
	delete(closes)
	return result
}

@(test)
test_string_terms_use_exact_jq_parser_stack_budget :: proc(t: ^testing.T) {
	// The checksum-pinned jq 1.8.1 oracle accepts each completed form through
	// 9,993 groups and reports memory exhaustion at 9,994. Ordinary one-token
	// leaves retain their separately pinned 9,994/9,995 boundary.
	malformed_raw_bytes := [3]byte{'"', 0xff, '"'}
	terms := [?]string{
		`""`,
		`"plain"`,
		`"\n"`,
		`"\u03bc"`,
		transmute(string)malformed_raw_bytes[:],
	}
	for term in terms {
		success_text := nested_string_filter(t, 9_993, term)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, success_text)
		expect_parse_success(t, &parser, outcome)
		testing.expect_value(t, parser.nodes.count, 9_994)
		testing.expect_value(t, parser.string_allocations.count, 1)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(success_text)

		failure_text := nested_string_filter(t, 9_994, term)
		_, failure := parse_test_filter(t, &parser, failure_text)
		testing.expect_value(t, failure.kind, Parse_Outcome_Kind.Resource_Failure)
		testing.expect_value(t, failure.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		testing.expect_value(t, parser.string_allocations.count, 0)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(failure_text)
	}
}

@(test)
test_malformed_and_unterminated_strings_keep_event_local_stack_diagnostics :: proc(t: ^testing.T) {
	// jq diagnoses the first malformed QQSTRING_TEXT lookahead before entering
	// the extra String state, even where valid string progress would exhaust it.
	malformed := nested_string_filter(t, 9_994, `"\q"`)
	parser: Parser
	source, malformed_outcome := parse_test_filter(t, &parser, malformed)
	testing.expect_value(t, malformed_outcome.kind, Parse_Outcome_Kind.Input_Error)
	testing.expect_value(t, malformed_outcome.error.kind, Parse_Error_Kind.Lexical_Error)
	testing.expect_value(t, malformed_outcome.error.message, "Invalid escape")
	expect_span(t, source, malformed_outcome.error.span, 9_995, 9_997)
	testing.expect_value(t, parser.string_allocations.count, 0)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	delete(malformed)

	unterminated_success_depth := nested_string_filter(t, 9_993, `"plain`)
	unterminated_source, unterminated := parse_test_filter(t, &parser, unterminated_success_depth)
	testing.expect_value(t, unterminated.kind, Parse_Outcome_Kind.Input_Error)
	testing.expect_value(t, unterminated.error.kind, Parse_Error_Kind.Unexpected_End)
	testing.expect_value(t, unterminated.error.message, "unterminated string literal")
	expect_span(t, unterminated_source, unterminated.error.span, 9_993, 9_994)
	testing.expect_value(t, parser.string_allocations.count, 0)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	delete(unterminated_success_depth)

	unterminated_failure_depth := nested_string_filter(t, 9_994, `"plain`)
	_, exhausted := parse_test_filter(t, &parser, unterminated_failure_depth)
	testing.expect_value(t, exhausted.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, exhausted.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, parser.string_allocations.count, 0)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	delete(unterminated_failure_depth)
}

@(test)
test_decoded_string_size_preflight_checks_wide_boundaries :: proc(t: ^testing.T) {
	limit := u64(max(int))
	testing.expect(t, decoded_string_source_size_fits(limit))
	testing.expect(t, !decoded_string_source_size_fits(limit+1))

	total: u64
	testing.expect(t, checked_decoded_string_size_add(&total, limit, 1))
	testing.expect_value(t, total, limit)
	testing.expect(t, !checked_decoded_string_size_add(&total, 1, 1))
	testing.expect_value(t, total, limit)

	// Each malformed raw UTF-8 decoding unit expands to three replacement bytes.
	malformed_units := limit/3
	total = 0
	testing.expect(t, checked_decoded_string_size_add(&total, malformed_units, 3))
	testing.expect_value(t, total, malformed_units*3)
	testing.expect(t, !checked_decoded_string_size_add(&total, 1, 3))
	testing.expect_value(t, total, malformed_units*3)
	total = 0
	testing.expect(t, !checked_decoded_string_size_add(&total, malformed_units+1, 3))
	testing.expect_value(t, total, u64(0))

	narrowed, narrow_ok := narrow_decoded_string_size(limit)
	testing.expect(t, narrow_ok)
	testing.expect_value(t, narrowed, max(int))
	narrowed, narrow_ok = narrow_decoded_string_size(limit+1)
	testing.expect(t, !narrow_ok)
	testing.expect_value(t, narrowed, 0)
}
