package syntax

import "base:runtime"
import diagnostic "jq:diagnostic"
import "core:mem"
import "core:strings"
import "core:testing"

@(private="package")
parse_test_filter :: proc(
	t: ^testing.T,
	parser: ^Parser,
	text: string,
	allocator := context.allocator,
) -> (diagnostic.Source, Parse_Outcome) {
	source := diagnostic.borrow_source(text, text)
	testing.expect(t, init_parser(parser, source, allocator))
	return source, parse_filter(parser)
}

@(private="package")
expect_node_span :: proc(
	t: ^testing.T,
	parser: ^Parser,
	node: Node_Id,
	start, end: int,
) {
	expect_span(t, parser.source, parser.nodes.storage[int(node)].span, start, end)
}

@(private="package")
expect_parse_success :: proc(t: ^testing.T, parser: ^Parser, outcome: Parse_Outcome) {
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	testing.expect(t, int(outcome.root) >= 0)
	testing.expect(t, int(outcome.root) < parser.nodes.count)
}

@(test)
test_parser_every_supported_standalone_form :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		kind: Node_Kind,
	}
	cases := [?]Case{
		{".", .Identity},
		{".name", .Field},
		{"(.)", .Parenthesized},
		{"., .name", .Comma},
		{". | .name", .Pipe},
		{".?", .Optional},
	}

	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, root.kind, test_case.kind)
		expect_span(t, source, root.span, 0, len(test_case.text))
		if root.kind == .Field {
			testing.expect(t, root.has_name_span)
			expect_span(t, source, root.name_span, 1, 5)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_parser_comma_pipe_precedence_and_associativity :: proc(t: ^testing.T) {
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "., .a, .b | .c | .d")
	expect_parse_success(t, &parser, outcome)

	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Pipe)
	left := parser.nodes.storage[int(root.left)]
	right := parser.nodes.storage[int(root.right)]
	testing.expect_value(t, left.kind, Node_Kind.Comma)
	testing.expect_value(t, parser.nodes.storage[int(left.left)].kind, Node_Kind.Comma)
	testing.expect_value(t, right.kind, Node_Kind.Pipe)
	expect_node_span(t, &parser, root.left, 0, 9)
	expect_node_span(t, &parser, root.right, 12, 19)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)

	parenthesized: Parser
	_, grouped := parse_test_filter(t, &parenthesized, "., (.a | .b)")
	expect_parse_success(t, &parenthesized, grouped)
	grouped_root := parenthesized.nodes.storage[int(grouped.root)]
	testing.expect_value(t, grouped_root.kind, Node_Kind.Comma)
	rhs := parenthesized.nodes.storage[int(grouped_root.right)]
	testing.expect_value(t, rhs.kind, Node_Kind.Parenthesized)
	testing.expect_value(
		t,
		parenthesized.nodes.storage[int(rhs.child)].kind,
		Node_Kind.Pipe,
	)
	testing.expect_value(t, destroy_parser(&parenthesized), runtime.Allocator_Error.None)
}

@(test)
test_parser_postfix_optional_binds_and_chains :: proc(t: ^testing.T) {
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, ". | .name??, (.)?")
	expect_parse_success(t, &parser, outcome)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Pipe)
	comma := parser.nodes.storage[int(root.right)]
	testing.expect_value(t, comma.kind, Node_Kind.Comma)

	outer_optional := parser.nodes.storage[int(comma.left)]
	testing.expect_value(t, outer_optional.kind, Node_Kind.Optional)
	inner_optional := parser.nodes.storage[int(outer_optional.child)]
	testing.expect_value(t, inner_optional.kind, Node_Kind.Optional)
	testing.expect_value(
		t,
		parser.nodes.storage[int(inner_optional.child)].kind,
		Node_Kind.Field,
	)
	expect_node_span(t, &parser, comma.left, 4, 11)

	group_optional := parser.nodes.storage[int(comma.right)]
	testing.expect_value(t, group_optional.kind, Node_Kind.Optional)
	testing.expect_value(
		t,
		parser.nodes.storage[int(group_optional.child)].kind,
		Node_Kind.Parenthesized,
	)
	expect_node_span(t, &parser, comma.right, 13, 17)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_postfix_fields_and_optionals_chain_with_exact_spans :: proc(t: ^testing.T) {
	parser: Parser
	source, outcome := parse_test_filter(t, &parser, " .a.b?.c?? ")
	expect_parse_success(t, &parser, outcome)

	outer_optional := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, outer_optional.kind, Node_Kind.Optional)
	testing.expect(t, outer_optional.has_child)
	expect_span(t, source, outer_optional.span, 1, 10)

	inner_optional_id := outer_optional.child
	inner_optional := parser.nodes.storage[int(inner_optional_id)]
	testing.expect_value(t, inner_optional.kind, Node_Kind.Optional)
	expect_node_span(t, &parser, inner_optional_id, 1, 9)

	field_c_id := inner_optional.child
	field_c := parser.nodes.storage[int(field_c_id)]
	testing.expect_value(t, field_c.kind, Node_Kind.Field)
	testing.expect(t, field_c.has_child && field_c.has_name_span)
	expect_node_span(t, &parser, field_c_id, 1, 8)
	expect_span(t, source, field_c.name_span, 7, 8)

	optional_b_id := field_c.child
	optional_b := parser.nodes.storage[int(optional_b_id)]
	testing.expect_value(t, optional_b.kind, Node_Kind.Optional)
	expect_node_span(t, &parser, optional_b_id, 1, 6)

	field_b_id := optional_b.child
	field_b := parser.nodes.storage[int(field_b_id)]
	testing.expect_value(t, field_b.kind, Node_Kind.Field)
	testing.expect(t, field_b.has_child && field_b.has_name_span)
	expect_node_span(t, &parser, field_b_id, 1, 5)
	expect_span(t, source, field_b.name_span, 4, 5)

	field_a := parser.nodes.storage[int(field_b.child)]
	testing.expect_value(t, field_a.kind, Node_Kind.Field)
	testing.expect(t, !field_a.has_child && field_a.has_name_span)
	expect_span(t, source, field_a.span, 1, 3)
	expect_span(t, source, field_a.name_span, 2, 3)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_postfix_field_acceptance_matrix :: proc(t: ^testing.T) {
	cases := [?]string{
		".a.b",
		"(.a).b",
		".a?.b",
		".a.b?",
		".a??.b",
		".? .a",
		".a.b, .c.d",
		".a | .b.c",
	}

	for text in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		expect_parse_success(t, &parser, outcome)
		expect_node_span(t, &parser, outcome.root, 0, len(text))
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_parser_postfix_field_precedence_and_nesting :: proc(t: ^testing.T) {
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "(.a?).b, .c.d | .e?.f")
	expect_parse_success(t, &parser, outcome)

	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Pipe)
	left := parser.nodes.storage[int(root.left)]
	testing.expect_value(t, left.kind, Node_Kind.Comma)
	group_field := parser.nodes.storage[int(left.left)]
	testing.expect_value(t, group_field.kind, Node_Kind.Field)
	testing.expect_value(
		t,
		parser.nodes.storage[int(group_field.child)].kind,
		Node_Kind.Parenthesized,
	)
	field_d := parser.nodes.storage[int(left.right)]
	testing.expect_value(t, field_d.kind, Node_Kind.Field)
	testing.expect_value(t, parser.nodes.storage[int(field_d.child)].kind, Node_Kind.Field)
	right_field := parser.nodes.storage[int(root.right)]
	testing.expect_value(t, right_field.kind, Node_Kind.Field)
	testing.expect_value(
		t,
		parser.nodes.storage[int(right_field.child)].kind,
		Node_Kind.Optional,
	)
	expect_node_span(t, &parser, root.left, 0, 13)
	expect_node_span(t, &parser, root.right, 16, 21)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_precise_nested_composed_spans :: proc(t: ^testing.T) {
	parser: Parser
	source, outcome := parse_test_filter(t, &parser, " ( .x? , (.) )? ")
	expect_parse_success(t, &parser, outcome)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Optional)
	expect_span(t, source, root.span, 1, 15)

	group := parser.nodes.storage[int(root.child)]
	testing.expect_value(t, group.kind, Node_Kind.Parenthesized)
	expect_span(t, source, group.span, 1, 14)
	comma := parser.nodes.storage[int(group.child)]
	testing.expect_value(t, comma.kind, Node_Kind.Comma)
	expect_span(t, source, comma.span, 3, 12)
	expect_node_span(t, &parser, comma.left, 3, 6)
	expect_node_span(t, &parser, comma.right, 9, 12)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_rejects_malformed_delimiters_and_trailing_tokens :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		kind: Parse_Error_Kind,
		expected: Parse_Expectation,
		start, end: int,
	}
	cases := [?]Case{
		{"", .Unexpected_End, .Expression, 0, 0},
		{"(", .Unexpected_End, .Expression, 1, 1},
		{"(.", .Unexpected_End, .Close_Paren, 2, 2},
		{"(.,)", .Unexpected_Token, .Expression, 3, 4},
		{".,", .Unexpected_End, .Expression, 2, 2},
		{". |", .Unexpected_End, .Expression, 3, 3},
		{".)", .Lexical_Error, .End_Of_Input, 1, 2},
		{"(.) .", .Unexpected_End, .End_Of_Input, 5, 5},
		{".a.", .Unexpected_End, .End_Of_Input, 3, 3},
		{".a?.", .Unexpected_End, .End_Of_Input, 4, 4},
		{".a?name", .Unexpected_Token, .End_Of_Input, 3, 7},
		{"(.a).?", .Unexpected_Token, .End_Of_Input, 5, 6},
		{".a..b", .Unexpected_Token, .End_Of_Input, 2, 4},
		{".a.b,", .Unexpected_End, .Expression, 5, 5},
		{".a.b | .c.", .Unexpected_End, .End_Of_Input, 10, 10},
	}

	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, test_case.kind)
		testing.expect_value(t, outcome.error.expected, test_case.expected)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_parser_postfix_dot_error_boundary_matches_jq :: proc(t: ^testing.T) {
	parser: Parser
	source, outcome := parse_test_filter(t, &parser, "(.a).?")
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
	testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_Token)
	testing.expect(t, outcome.error.has_actual)
	testing.expect_value(t, outcome.error.actual, Token_Kind.Question)
	expect_span(t, source, outcome.error.span, 5, 6)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_1818_filter_acceptance_corpus :: proc(t: ^testing.T) {
	accepted := [?]string{
		".",
		".a",
		"(.)",
		".?",
		".a.b",
		".a?.b?",
		"(.a?).b",
		"., .a | .b",
		".a | .b, .c",
	}
	rejected := [?]string{
		"",
		"(",
		".a.",
		"(.a).?",
		".a..b",
		".a?name",
		"[]",
		". // .",
		".a.b,",
	}
	filter_count := 0
	for padding_width in 0 ..= 100 {
		padding, padding_error := strings.repeat(" ", padding_width)
		testing.expect(t, padding_error == nil)
		for base in accepted {
			text, text_error := strings.concatenate([]string{padding, base})
			testing.expect(t, text_error == nil)
			parser: Parser
			_, outcome := parse_test_filter(t, &parser, text)
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
			testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
			delete(text)
			filter_count += 1
		}
		for base in rejected {
			text, text_error := strings.concatenate([]string{padding, base})
			testing.expect(t, text_error == nil)
			parser: Parser
			_, outcome := parse_test_filter(t, &parser, text)
			testing.expect(t, outcome.kind != .Success)
			testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
			delete(text)
			filter_count += 1
		}
		delete(padding)
	}
	testing.expect_value(t, filter_count, 1818)
}

@(test)
test_parser_rejects_every_unsupported_token_class_and_lexer_errors :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		kind: Parse_Error_Kind,
		start, end: int,
	}
	cases := [?]Case{
		{"name", .Unexpected_Token, 0, 4},
		{"1", .Unexpected_Token, 0, 1},
		{"[]", .Unexpected_Token, 0, 1},
		{"..", .Unexpected_Token, 0, 2},
		{". // .", .Unexpected_Token, 2, 4},
		{". + .", .Unexpected_Token, 2, 3},
		{"\x00.", .Lexical_Error, 0, 1},
		{". \xff", .Lexical_Error, 2, 3},
	}

	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, test_case.kind)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_parser_embedded_nul_is_not_end_of_input :: proc(t: ^testing.T) {
	parser: Parser
	source, outcome := parse_test_filter(t, &parser, ".\x00?")
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
	testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Lexical_Error)
	testing.expect_value(t, outcome.error.expected, Parse_Expectation.End_Of_Input)
	expect_span(t, source, outcome.error.span, 1, 2)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(private="package")
nested_filter :: proc(depth: int) -> string {
	opens, open_error := strings.repeat("(", depth)
	assert(open_error == nil)
	closes, close_error := strings.repeat(")", depth)
	assert(close_error == nil)
	result, result_error := strings.concatenate([]string{opens, ".", closes})
	assert(result_error == nil)
	delete(opens)
	delete(closes)
	return result
}

@(private="package")
pipe_filter :: proc(pipe_count: int) -> string {
	prefix, prefix_error := strings.repeat(".|", pipe_count)
	assert(prefix_error == nil)
	result, result_error := strings.concatenate([]string{prefix, "."})
	assert(result_error == nil)
	delete(prefix)
	return result
}

@(test)
test_parser_accepts_oracle_supported_deep_groups :: proc(t: ^testing.T) {
	// Pinned jq 1.8.1 accepts every depth here. 9994 is its last successful
	// nested-group probe before the generated Bison stack reports exhaustion.
	depths := [?]int{128, 129, 1000, 9994}
	for depth in depths {
		text := nested_filter(depth)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		expect_parse_success(t, &parser, outcome)
		testing.expect_value(t, parser.nodes.count, depth+1)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_parser_accepts_oracle_supported_deep_right_associative_pipes :: proc(t: ^testing.T) {
	// Pinned jq 1.8.1 accepts every depth here. 4997 is its last successful
	// pipe-chain probe before the generated Bison stack reports exhaustion.
	pipe_counts := [?]int{128, 129, 1000, 4997}
	for pipe_count in pipe_counts {
		text := pipe_filter(pipe_count)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		expect_parse_success(t, &parser, outcome)
		testing.expect_value(t, parser.nodes.count, pipe_count*2+1)

		pipe := outcome.root
		for index in 0 ..< pipe_count {
			node := parser.nodes.storage[int(pipe)]
			testing.expect_value(t, node.kind, Node_Kind.Pipe)
			testing.expect_value(
				t,
				parser.nodes.storage[int(node.left)].kind,
				Node_Kind.Identity,
			)
			pipe = node.right
			if index+1 < pipe_count {
				testing.expect_value(
					t,
					parser.nodes.storage[int(pipe)].kind,
					Node_Kind.Pipe,
				)
			}
		}
		testing.expect_value(
			t,
			parser.nodes.storage[int(pipe)].kind,
			Node_Kind.Identity,
		)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_parser_rejects_deep_incomplete_forms_like_oracle :: proc(t: ^testing.T) {
	depths := [?]int{128, 129, 1000}
	for depth in depths {
		balanced := nested_filter(depth)
		unterminated := balanced[:len(balanced)-1]
		group_parser: Parser
		_, group_outcome := parse_test_filter(t, &group_parser, unterminated)
		testing.expect_value(t, group_outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(
			t,
			group_outcome.error.kind,
			Parse_Error_Kind.Unexpected_End,
		)
		testing.expect_value(
			t,
			group_outcome.error.expected,
			Parse_Expectation.Close_Paren,
		)
		testing.expect_value(
			t,
			destroy_parser(&group_parser),
			runtime.Allocator_Error.None,
		)
		delete(balanced)

		incomplete, repeat_error := strings.repeat(".|", depth)
		assert(repeat_error == nil)
		pipe_parser: Parser
		_, pipe_outcome := parse_test_filter(t, &pipe_parser, incomplete)
		testing.expect_value(t, pipe_outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(
			t,
			pipe_outcome.error.kind,
			Parse_Error_Kind.Unexpected_End,
		)
		testing.expect_value(
			t,
			pipe_outcome.error.expected,
			Parse_Expectation.Expression,
		)
		testing.expect_value(
			t,
			destroy_parser(&pipe_parser),
			runtime.Allocator_Error.None,
		)
		delete(incomplete)
	}
}

@(test)
test_parser_every_allocation_failure_keeps_cleanup_owner :: proc(t: ^testing.T) {
	text :: "((((.root.first?.second)))) | (.x?.y, .z??.last)"
	baseline_data := Test_Allocator{backing = context.allocator, alive = true}
	baseline: Parser
	_, baseline_outcome := parse_test_filter(
		t,
		&baseline,
		text,
		test_allocator(&baseline_data),
	)
	expect_parse_success(t, &baseline, baseline_outcome)
	allocation_points := baseline_data.request_count
	testing.expect(t, allocation_points > 1)
	testing.expect_value(t, destroy_parser(&baseline), runtime.Allocator_Error.None)

	for fail_at in 1 ..= allocation_points {
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		allocator_data := Test_Allocator{
			backing = mem.tracking_allocator(&tracker),
			fail_at = fail_at,
			alive = true,
		}
		parser: Parser
		_, outcome := parse_test_filter(
			t,
			&parser,
			text,
			test_allocator(&allocator_data),
		)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		testing.expect(t, len(tracker.allocation_map) == 0)
		mem.tracking_allocator_destroy(&tracker)
	}
}

@(test)
test_parser_growth_free_failure_retains_replacement_for_retry :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
		free_failures_remaining = 1,
		resize_unsupported = true,
	}
	parser: Parser
	_, outcome := parse_test_filter(
		t,
		&parser,
		".a????????????????????",
		test_allocator(&allocator_data),
	)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.nodes.count, 8)
	testing.expect_value(t, parser.nodes.state, Fallible_Buffer_State.Transfer_Pending)
	active_pointer := raw_data(parser.nodes.storage)
	replacement_pointer := raw_data(parser.nodes.replacement)
	testing.expect(t, active_pointer != nil)
	testing.expect(t, replacement_pointer != nil)
	testing.expect(t, replacement_pointer != active_pointer)
	testing.expect_value(t, len(tracker.allocation_map), 2)
	testing.expect_value(t, allocator_data.resize_call_count, 0)

	testing.expect_value(
		t,
		retry_fallible_buffer_transfer(&parser.nodes),
		runtime.Allocator_Error.None,
	)
	testing.expect_value(t, parser.nodes.state, Fallible_Buffer_State.Owned)
	testing.expect(t, raw_data(parser.nodes.storage) == replacement_pointer)
	testing.expect(t, parser.nodes.replacement == nil)
	testing.expect_value(t, parser.nodes.count, 8)
	testing.expect_value(t, len(tracker.allocation_map), 1)

	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	allocator_data.alive = false
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.calls_after_retirement, 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_parser_pending_growth_cleanup_failure_is_retryable :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
		free_failures_remaining = 2,
		resize_unsupported = true,
	}
	parser: Parser
	_, outcome := parse_test_filter(
		t,
		&parser,
		".a????????????????????",
		test_allocator(&allocator_data),
	)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.nodes.state, Fallible_Buffer_State.Transfer_Pending)
	testing.expect_value(t, len(tracker.allocation_map), 2)

	first_destroy := destroy_parser(&parser)
	testing.expect_value(t, first_destroy, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	testing.expect_value(t, parser.nodes.state, Fallible_Buffer_State.Transfer_Pending)
	testing.expect(t, parser.nodes.storage != nil)
	testing.expect(t, parser.nodes.replacement != nil)
	testing.expect_value(t, len(tracker.allocation_map), 2)

	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, parser.state, Parser_State.Destroyed)
	testing.expect_value(t, parser.nodes.state, Fallible_Buffer_State.Empty)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_parser_failed_destruction_is_retryable :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
		free_failures_remaining = 1,
	}
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, ".", test_allocator(&allocator_data))
	expect_parse_success(t, &parser, outcome)
	allocation_count := len(tracker.allocation_map)
	testing.expect(t, allocation_count > 0)

	first_error := destroy_parser(&parser)
	testing.expect_value(t, first_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	testing.expect_value(t, len(tracker.allocation_map), allocation_count)
	testing.expect_value(t, parser.nodes.count, 1)

	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect(t, len(tracker.allocation_map) == 0)
	allocator_data.alive = false
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.calls_after_retirement, 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_parser_failed_scanner_destruction_preserves_both_owners :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
		free_failures_remaining = 1,
	}
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "(.)", test_allocator(&allocator_data))
	expect_parse_success(t, &parser, outcome)
	allocation_count := len(tracker.allocation_map)
	testing.expect(t, allocation_count >= 2)

	first_error := destroy_parser(&parser)
	testing.expect_value(t, first_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	testing.expect_value(t, parser.scanner.state, Scanner_State.Active)
	testing.expect_value(t, parser.nodes.count, 2)
	testing.expect_value(t, len(tracker.allocation_map), allocation_count)

	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect(t, len(tracker.allocation_map) == 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_bulk_lifetime_parser_destruction_retires_all_handles :: proc(t: ^testing.T) {
	arena: runtime.Arena
	init_error := runtime.arena_init(&arena, 4096, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error.None)
	if init_error != nil {
		return
	}

	allocator_data := Test_Allocator{
		backing = runtime.arena_allocator(&arena),
		alive = true,
	}
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "(.)", test_allocator(&allocator_data))
	expect_parse_success(t, &parser, outcome)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.free_count, 2)

	allocator_data.alive = false
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.calls_after_retirement, 0)
	runtime.arena_destroy(&arena)
}
