package syntax

import "base:runtime"
import diagnostic "jq:diagnostic"
import "core:mem"
import "core:strings"
import "core:testing"

@(test)
test_select_lowers_to_existing_if_shape :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<select>", "select(. > 1)")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.If)
	testing.expect(t, root.has_if_condition && root.has_if_then && root.has_if_else)
	testing.expect_value(t, parser.nodes.storage[int(root.if_then)].kind, Node_Kind.Identity)
	testing.expect_value(t, parser.nodes.storage[int(root.if_else)].kind, Node_Kind.Empty)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parenthesized_generator_binary_expression_parses :: proc(t: ^testing.T) {
	cases := [?]string{
		`1 * (range(0;3) / 2)`,
		`10 - (range(0;3) + 1)`,
		`1 + (range(0;3) * 2)`,
		`(range(0;3) / 2) * 4`,
		`100 / (range(1;3) * 5)`,
	}
	for text in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		expect_parse_success(t, &parser, outcome)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_log2_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<log2>", "log2")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Log2)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_mktime_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<mktime>", "mktime")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Mktime)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_exp_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<exp>", "exp")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Exp)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_exp2_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<exp2>", "exp2")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Exp2)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_exp10_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<exp10>", "exp10")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Exp10)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_asin_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<asin>", "asin")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Asin)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_acos_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<acos>", "acos")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Acos)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_cos_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<cos>", "cos")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Cos)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_sin_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<sin>", "sin")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Sin)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_tan_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<tan>", "tan")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Tan)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_sinh_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<sinh>", "sinh")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Sinh)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_error_parses_literal_string_argument :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<error>", `error("foo")`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Error)
	testing.expect(t, root.has_child)
	child := parser.nodes.storage[int(root.child)]
	testing.expect_value(t, child.kind, Node_Kind.String)
	testing.expect_value(t, child.string_text, "foo")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_try_error_catch_parses_two_children :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<try>", `try error("boom") catch .`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Try)
	testing.expect(t, root.left >= 0 && root.right >= 0)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_log10_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<log10>", "log10")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Log10)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_first_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<first>", "first")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.First)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_isinfinite_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<isinfinite>", "isinfinite")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Isinfinite)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_last_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<last>", "last")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Last)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

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

@(test)
test_log_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<log>", "log")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Log)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
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

@(private="package")
expect_binary_node :: proc(
	t: ^testing.T,
	parser: ^Parser,
	node_id: Node_Id,
	operator: Binary_Operator,
	span_start, span_end, operator_start, operator_end: int,
) -> Node {
	node := parser.nodes.storage[int(node_id)]
	testing.expect_value(t, node.form, Node_Form.Binary)
	testing.expect_value(t, node.binary_operator, operator)
	testing.expect(t, node.has_operator_span)
	testing.expect(t, !node.has_child)
	expect_span(t, parser.source, node.span, span_start, span_end)
	expect_span(t, parser.source, node.operator_span, operator_start, operator_end)
	return node
}

@(test)
test_parser_lexical_as_binding_and_variable_reference :: proc(t: ^testing.T) {
	parser: Parser
	source, outcome := parse_test_filter(t, &parser, "2 as $c | $c")
	expect_parse_success(t, &parser, outcome)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Binding)
	expect_span(t, source, root.name_span, 6, 7)
	testing.expect_value(t, parser.nodes.storage[int(root.left)].kind, Node_Kind.Number)
	testing.expect_value(t, parser.nodes.storage[int(root.right)].kind, Node_Kind.Variable)
	expect_span(t, source, parser.nodes.storage[int(root.right)].name_span, 11, 12)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_container_literals_preserve_source_structure :: proc(t: ^testing.T) {
	Case :: struct { text: string, kind: Container_Kind }
	cases := [?]Case{{"[]", .Array}, {"{}", .Object}}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, root.container_kind, test_case.kind)
		expect_span(t, source, root.span, 0, len(test_case.text))
		testing.expect(t, !root.has_child && !root.has_value)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}

	parser: Parser
	source, outcome := parse_test_filter(t, &parser, "{a: []}")
	expect_parse_success(t, &parser, outcome)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.container_kind, Container_Kind.Object)
	testing.expect(t, root.has_value)
	entry := parser.nodes.storage[int(root.value)]
	testing.expect_value(t, entry.container_kind, Container_Kind.Object_Entry)
	testing.expect(t, entry.has_name_span && entry.has_value)
	expect_span(t, source, entry.name_span, 1, 2)
	value := parser.nodes.storage[int(entry.value)]
	testing.expect_value(t, value.container_kind, Container_Kind.Array)
	expect_span(t, source, value.span, 4, 6)
	expect_span(t, source, root.span, 0, 7)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_object_keys_cover_source_forms :: proc(t: ^testing.T) {
	cases := [?]string{"{\"a\":1}", "{a}", "{if:1}", "{(.):1}"}
	for text in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		expect_parse_success(t, &parser, outcome)
		root := parser.nodes.storage[int(outcome.root)]
		entry := parser.nodes.storage[int(root.value)]
		testing.expect(t, entry.has_key && entry.has_value)
		testing.expect_value(t, parser.nodes.storage[int(entry.key)].span.start, entry.name_span.start)
		testing.expect_value(t, parser.nodes.storage[int(entry.value)].span.end, entry.span.end)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_parser_container_values_stop_at_entry_commas :: proc(t: ^testing.T) {
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "{a:1,b:2}")
	expect_parse_success(t, &parser, outcome)
	root := parser.nodes.storage[int(outcome.root)]
	first := parser.nodes.storage[int(root.value)]
	second := parser.nodes.storage[int(first.next)]
	testing.expect_value(t, parser.nodes.storage[int(first.value)].number_text, "1")
	testing.expect_value(t, parser.nodes.storage[int(second.value)].number_text, "2")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)

	parser = {}
	_, outcome = parse_test_filter(t, &parser, "{a:(1,2),b:3}")
	expect_parse_success(t, &parser, outcome)
	root = parser.nodes.storage[int(outcome.root)]
	first = parser.nodes.storage[int(root.value)]
	value := parser.nodes.storage[int(first.value)]
	testing.expect_value(t, value.kind, Node_Kind.Parenthesized)
	testing.expect(t, value.has_child)
	testing.expect_value(t, parser.nodes.storage[int(value.child)].kind, Node_Kind.Comma)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_unary_minus_accepts_recursive_container_terms :: proc(t: ^testing.T) {
	cases := [?]string{"-[]", "-{}"}
	for text in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		expect_parse_success(t, &parser, outcome)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, root.kind, Node_Kind.Negate)
		testing.expect(t, root.has_child)
		testing.expect_value(t, parser.nodes.storage[int(root.child)].container_kind,
			Container_Kind.Array if text == "-[]" else Container_Kind.Object)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_parser_container_nesting_budget_preserves_jq_depth :: proc(t: ^testing.T) {
	depth := JQ_CONTAINER_NESTING_CAP
	opens, open_error := strings.repeat("[", depth)
	closes, close_error := strings.repeat("]", depth)
	testing.expect(t, open_error == nil && close_error == nil)
	text, text_error := strings.concatenate([]string{opens, "0", closes})
	testing.expect(t, text_error == nil)
	delete(opens)
	delete(closes)
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text)
	expect_parse_success(t, &parser, outcome)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	delete(text)

	depth += 1
	opens, open_error = strings.repeat("[", depth)
	closes, close_error = strings.repeat("]", depth)
	testing.expect(t, open_error == nil && close_error == nil)
	text, text_error = strings.concatenate([]string{opens, "0", closes})
	testing.expect(t, text_error == nil)
	delete(opens)
	delete(closes)
	parser = {}
	_, outcome = parse_test_filter(t, &parser, text)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	delete(text)
}

@(test)
test_parser_deep_arrays_resume_outer_queries :: proc(t: ^testing.T) {
	// Every flattened array frame gets its own query lookahead.  In particular,
	// a continuation may recur at each enclosing close rather than appearing
	// only immediately after the innermost value.
	continuations := [?]string{",1]", "|.]", "+1]", ".foo]", "?]"}
	for continuation in continuations {
		depth := JQ_NATIVE_CONTAINER_RECURSION_GUARD + 2
		opens, open_error := strings.repeat("[", depth)
		repeated, repeated_error := strings.repeat(continuation, depth-1)
		testing.expect(t, open_error == nil && repeated_error == nil)
		text, text_error := strings.concatenate([]string{opens, "0]", repeated})
		testing.expect(t, text_error == nil)
		delete(opens)
		delete(repeated)

		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		expect_parse_success(t, &parser, outcome)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_parser_deep_objects_follow_shared_stack_budget :: proc(t: ^testing.T) {
		make_nested_object_filter :: proc(depth: int) -> string {
			prefix, prefix_error := strings.repeat("{a:", depth)
			suffix, suffix_error := strings.repeat("}", depth)
			if prefix_error != nil || suffix_error != nil {
				return ""
			}
			text, text_error := strings.concatenate([]string{prefix, "0", suffix})
			delete(prefix)
			delete(suffix)
			if text_error != nil {
				return ""
			}
			return text
		}

	// Object nesting is governed by the shared parser-stack budget, not the
	// array-only iterative-path threshold.
	for depth_index := 0; depth_index < 3; depth_index += 1 {
		depth := 1070
		if depth_index == 0 {
			depth = JQ_NATIVE_CONTAINER_RECURSION_GUARD - 1
		} else if depth_index == 1 {
			depth = JQ_NATIVE_CONTAINER_RECURSION_GUARD
		}
		text := make_nested_object_filter(depth)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		expect_parse_success(t, &parser, outcome)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_parser_container_and_expression_depth_share_budget :: proc(t: ^testing.T) {
	// Both prefixes remain live while the innermost term is shifted. The
	// independent limits used to accept this although jq exhausts its shared
	// generated-parser stack.
	opens, open_error := strings.repeat("[", 6_000)
	minuses, minus_error := strings.repeat("-", 6_000)
	closes, close_error := strings.repeat("]", 6_000)
	text, text_error := strings.concatenate([]string{opens, minuses, "0", closes})
	testing.expect(t, open_error == nil && minus_error == nil && close_error == nil && text_error == nil)
	delete(opens)
	delete(minuses)
	delete(closes)

	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	delete(text)
}

@(test)
test_parser_object_budget_checks_before_entering_frame :: proc(t: ^testing.T) {
	// Model the 9,995th opener directly: with 9,994 object frames already live,
	// the next object must fail before incrementing or recursing into its value.
	parser: Parser
	source, _ := parse_test_filter(t, &parser, "{a:0}")
	// parse_test_filter has already parsed this source; reinitialize to exercise
	// the opener boundary without constructing thousands of native frames.
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	parser = {}
	testing.expect(t, init_parser(&parser, source, context.allocator))
	advance(&parser)
	parser.container_depth = JQ_CONTAINER_NESTING_CAP
	_, ok := parse_container(&parser, .Open_Brace)
	testing.expect(t, !ok)
	testing.expect_value(t, parser.failure.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, parser.failure.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_container_literals_reject_malformed_forms_at_delimiters :: proc(t: ^testing.T) {
	Case :: struct { text: string, start, end: int, expected: Parse_Expectation }
	cases := [?]Case{
		{"[1,]", 3, 4, .Expression},
		{"{a:}", 3, 4, .Expression},
		{"{a 1}", 3, 4, .Close_Brace},
		{"[", 1, 1, .Expression},
		{"{", 1, 1, .Close_Brace},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.expected, test_case.expected)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_parser_scalar_literals_preserve_kinds_spans_and_numeric_source :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		kind: Node_Kind,
		boolean_value: bool,
		number_text: string,
	}
	cases := [?]Case{
		{"null", .Null, false, ""},
		{"true", .Boolean, true, ""},
		{"false", .Boolean, false, ""},
		{"0", .Number, false, "0"},
		{"01", .Number, false, "01"},
		{"1.", .Number, false, "1."},
		{".1", .Number, false, ".1"},
		{"12.34", .Number, false, "12.34"},
		{"1e2", .Number, false, "1e2"},
		{"1E+2", .Number, false, "1E+2"},
		{".1e-2", .Number, false, ".1e-2"},
		{"-1", .Negate, false, "1"},
		{"-  .1E+2", .Negate, false, ".1E+2"},
	}
	for test_case in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		node := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, node.kind, test_case.kind)
		expect_span(t, parser.source, node.span, 0, len(test_case.text))
		if node.kind == .Boolean {
			testing.expect_value(t, node.boolean_value, test_case.boolean_value)
		}
		number := node
		if node.kind == .Negate {
			testing.expect(t, node.has_child)
			number = parser.nodes.storage[int(node.child)]
			testing.expect_value(t, number.kind, Node_Kind.Number)
		}
		if number.kind == .Number {
			testing.expect(t, number.has_number_text)
			testing.expect_value(t, number.number_text, test_case.number_text)
		} else {
			testing.expect(t, !node.has_number_text)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_scalar_keyword_calls_are_rejected_at_delimiter_without_literal_nodes :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		start, end: int,
	}
	cases := [?]Case{
		{"true(.)", 4, 5},
		{"false()", 5, 6},
		{"null(1)", 4, 5},
		{"true (.)", 5, 6},
		{"false\n()", 6, 7},
		{"null \n (1)", 7, 8},
		{"-true(.)", 5, 6},
		{"(false())", 6, 7},
		{"null(1)?", 4, 5},
		{"-(true\n(.))", 7, 8},
		{"(null \n (1))?", 8, 9},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_Token)
		testing.expect_value(t, outcome.error.expected, Parse_Expectation.Expression)
		testing.expect_value(t, outcome.error.actual, Token_Kind.Open_Paren)
		testing.expect(t, outcome.error.has_actual)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		for node in parser_nodes(&parser) {
			testing.expect(t, node.kind != .Boolean && node.kind != .Null)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_unsupported_scalar_keyword_call_cleanup_and_copy_safety :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	parser: Parser
	source, outcome := parse_test_filter(
		t,
		&parser,
		"true \n (.)",
		test_allocator(&allocator_data),
	)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
	testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_Token)
	expect_span(t, source, outcome.error.span, 7, 8)
	testing.expect_value(t, parser.nodes.count, 0)
	testing.expect_value(t, allocator_data.request_count, 1)
	testing.expect_value(t, len(tracker.allocation_map), 1)

	copied := parser
	expect_invalid_parser_copy(t, &copied)
	testing.expect_value(t, len(tracker.allocation_map), 1)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	expect_invalid_parser_copy(t, &copied)
	allocator_data.alive = false
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_repeated_unary_minus_preserves_source_nesting_spans_and_number_lexeme :: proc(t: ^testing.T) {
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "--1")
	expect_parse_success(t, &parser, outcome)
	outer := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, outer.kind, Node_Kind.Negate)
	expect_span(t, parser.source, outer.span, 0, 3)
	inner := parser.nodes.storage[int(outer.child)]
	testing.expect_value(t, inner.kind, Node_Kind.Negate)
	expect_span(t, parser.source, inner.span, 1, 3)
	number := parser.nodes.storage[int(inner.child)]
	testing.expect_value(t, number.kind, Node_Kind.Number)
	expect_span(t, parser.source, number.span, 2, 3)
	testing.expect_value(t, number.number_text, "1")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)

	spaced: Parser
	_, spaced_outcome := parse_test_filter(t, &spaced, "- 1")
	expect_parse_success(t, &spaced, spaced_outcome)
	spaced_negate := spaced.nodes.storage[int(spaced_outcome.root)]
	testing.expect_value(t, spaced_negate.kind, Node_Kind.Negate)
	expect_span(t, spaced.source, spaced_negate.span, 0, 3)
	spaced_number := spaced.nodes.storage[int(spaced_negate.child)]
	expect_span(t, spaced.source, spaced_number.span, 2, 3)
	testing.expect_value(t, spaced_number.number_text, "1")
	testing.expect_value(t, destroy_parser(&spaced), runtime.Allocator_Error.None)
}

@(private="package")
make_nested_term_filter :: proc(
	t: ^testing.T,
	outer_minuses, groups, inner_minuses, postfixes: int,
	payload := "1",
) -> string {
	outer, outer_error := strings.repeat("-", outer_minuses)
	testing.expect(t, outer_error == nil)
	opens, opens_error := strings.repeat("(", groups)
	testing.expect(t, opens_error == nil)
	inner, inner_error := strings.repeat("-", inner_minuses)
	testing.expect(t, inner_error == nil)
	closes, closes_error := strings.repeat(")", groups)
	testing.expect(t, closes_error == nil)
	postfix, postfix_error := strings.repeat("?", postfixes)
	testing.expect(t, postfix_error == nil)
	text, text_error := strings.concatenate([]string{outer, opens, inner, payload, closes, postfix})
	testing.expect(t, text_error == nil)
	delete(outer)
	delete(opens)
	delete(inner)
	delete(closes)
	delete(postfix)
	return text
}

@(test)
test_unary_minus_accepts_every_supported_term_start_and_postfix_placement :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		kinds: []Node_Kind,
		spans: [][2]int,
		kind_count: int,
		boolean_value: bool,
		field_name: string,
	}
	cases := [?]Case{
		{"-.", []Node_Kind{.Negate, .Identity}, [][2]int{{0, 2}, {1, 2}}, 2, false, ""},
		{"- .a", []Node_Kind{.Negate, .Field}, [][2]int{{0, 4}, {2, 4}}, 2, false, "a"},
		{"-.?", []Node_Kind{.Negate, .Optional, .Identity}, [][2]int{{0, 3}, {1, 3}, {1, 2}}, 3, false, ""},
		{"-.a?", []Node_Kind{.Negate, .Optional, .Field}, [][2]int{{0, 4}, {1, 4}, {1, 3}}, 3, false, "a"},
		{"-(.a?)", []Node_Kind{.Negate, .Parenthesized, .Optional, .Field}, [][2]int{{0, 6}, {1, 6}, {2, 5}, {2, 4}}, 4, false, "a"},
		{"-(.a)?", []Node_Kind{.Negate, .Optional, .Parenthesized, .Field}, [][2]int{{0, 6}, {1, 6}, {1, 5}, {2, 4}}, 4, false, "a"},
		{"(-.a)?", []Node_Kind{.Optional, .Parenthesized, .Negate, .Field}, [][2]int{{0, 6}, {0, 5}, {1, 4}, {2, 4}}, 4, false, "a"},
		{"-(-.a?)", []Node_Kind{.Negate, .Parenthesized, .Negate, .Optional, .Field}, [][2]int{{0, 7}, {1, 7}, {2, 6}, {3, 6}, {3, 5}}, 5, false, "a"},
		{"-true", []Node_Kind{.Negate, .Boolean}, [][2]int{{0, 5}, {1, 5}}, 2, true, ""},
		{"--false", []Node_Kind{.Negate, .Negate, .Boolean}, [][2]int{{0, 7}, {1, 7}, {2, 7}}, 3, false, ""},
		{"-(null)", []Node_Kind{.Negate, .Parenthesized, .Null}, [][2]int{{0, 7}, {1, 7}, {2, 6}}, 3, false, ""},
		{"-1", []Node_Kind{.Negate, .Number}, [][2]int{{0, 2}, {1, 2}}, 2, false, ""},
	}

	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		expect_span(t, source, parser.nodes.storage[int(outcome.root)].span, 0, len(test_case.text))

		node_id := outcome.root
		for index in 0..<test_case.kind_count {
			node := parser.nodes.storage[int(node_id)]
			testing.expect_value(t, node.kind, test_case.kinds[index])
			expect_span(t, source, node.span, test_case.spans[index][0], test_case.spans[index][1])
			if index+1 < test_case.kind_count {
				testing.expect(t, node.has_child)
				node_id = node.child
			} else if node.kind == .Boolean {
				testing.expect_value(t, node.boolean_value, test_case.boolean_value)
			} else if node.kind == .Field {
				name_start, name_end, name_ok := diagnostic.span_offsets(source, node.name_span)
				testing.expect(t, node.has_name_span && name_ok)
				testing.expect_value(t, diagnostic.source_bytes(source)[name_start:name_end], test_case.field_name)
			}
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_unary_minus_grouped_query_structure_preserves_precedence_and_associativity :: proc(t: ^testing.T) {
	pipe_parser: Parser
	pipe_source, pipe_outcome := parse_test_filter(t, &pipe_parser, "-(. | .)")
	expect_parse_success(t, &pipe_parser, pipe_outcome)
	negate := pipe_parser.nodes.storage[int(pipe_outcome.root)]
	testing.expect_value(t, negate.kind, Node_Kind.Negate)
	expect_span(t, pipe_source, negate.span, 0, 8)
	group := pipe_parser.nodes.storage[int(negate.child)]
	testing.expect_value(t, group.kind, Node_Kind.Parenthesized)
	expect_span(t, pipe_source, group.span, 1, 8)
	pipe := pipe_parser.nodes.storage[int(group.child)]
	testing.expect_value(t, pipe.kind, Node_Kind.Pipe)
	expect_span(t, pipe_source, pipe.span, 2, 7)
	testing.expect_value(t, pipe_parser.nodes.storage[int(pipe.left)].kind, Node_Kind.Identity)
	testing.expect_value(t, pipe_parser.nodes.storage[int(pipe.right)].kind, Node_Kind.Identity)
	expect_node_span(t, &pipe_parser, pipe.left, 2, 3)
	expect_node_span(t, &pipe_parser, pipe.right, 6, 7)
	testing.expect_value(t, destroy_parser(&pipe_parser), runtime.Allocator_Error.None)

	comma_parser: Parser
	comma_source, comma_outcome := parse_test_filter(t, &comma_parser, "-(., .)")
	expect_parse_success(t, &comma_parser, comma_outcome)
	comma_negate := comma_parser.nodes.storage[int(comma_outcome.root)]
	testing.expect_value(t, comma_negate.kind, Node_Kind.Negate)
	expect_span(t, comma_source, comma_negate.span, 0, 7)
	comma_group := comma_parser.nodes.storage[int(comma_negate.child)]
	testing.expect_value(t, comma_group.kind, Node_Kind.Parenthesized)
	comma := comma_parser.nodes.storage[int(comma_group.child)]
	testing.expect_value(t, comma.kind, Node_Kind.Comma)
	expect_span(t, comma_source, comma.span, 2, 6)
	testing.expect_value(t, comma_parser.nodes.storage[int(comma.left)].kind, Node_Kind.Identity)
	testing.expect_value(t, comma_parser.nodes.storage[int(comma.right)].kind, Node_Kind.Identity)
	expect_node_span(t, &comma_parser, comma.left, 2, 3)
	expect_node_span(t, &comma_parser, comma.right, 5, 6)
	testing.expect_value(t, destroy_parser(&comma_parser), runtime.Allocator_Error.None)

	mixed_parser: Parser
	_, mixed_outcome := parse_test_filter(t, &mixed_parser, "-(., . | .)")
	expect_parse_success(t, &mixed_parser, mixed_outcome)
	mixed_negate := mixed_parser.nodes.storage[int(mixed_outcome.root)]
	mixed_group := mixed_parser.nodes.storage[int(mixed_negate.child)]
	mixed_pipe := mixed_parser.nodes.storage[int(mixed_group.child)]
	testing.expect_value(t, mixed_negate.kind, Node_Kind.Negate)
	testing.expect_value(t, mixed_group.kind, Node_Kind.Parenthesized)
	testing.expect_value(t, mixed_pipe.kind, Node_Kind.Pipe)
	testing.expect_value(t, mixed_parser.nodes.storage[int(mixed_pipe.left)].kind, Node_Kind.Comma)
	testing.expect_value(t, mixed_parser.nodes.storage[int(mixed_pipe.right)].kind, Node_Kind.Identity)
	testing.expect_value(t, destroy_parser(&mixed_parser), runtime.Allocator_Error.None)
}

@(test)
test_limit_accepts_comma_generator_and_negative_literal_count :: proc(t: ^testing.T) {
	comma_parser: Parser
	_, comma_outcome := parse_test_filter(t, &comma_parser, "limit(1; 1, error)")
	expect_parse_success(t, &comma_parser, comma_outcome)
	limit := comma_parser.nodes.storage[int(comma_outcome.root)]
	testing.expect_value(t, limit.kind, Node_Kind.Limit)
	testing.expect_value(t, comma_parser.nodes.storage[int(limit.left)].kind, Node_Kind.Number)
	generator := comma_parser.nodes.storage[int(limit.right)]
	testing.expect_value(t, generator.kind, Node_Kind.Comma)
	testing.expect_value(t, comma_parser.nodes.storage[int(generator.left)].kind, Node_Kind.Number)
	testing.expect_value(t, comma_parser.nodes.storage[int(generator.right)].kind, Node_Kind.Error)
	testing.expect_value(t, destroy_parser(&comma_parser), runtime.Allocator_Error.None)

	negative_parser: Parser
	_, negative_outcome := parse_test_filter(t, &negative_parser, "limit(-1; error)")
	expect_parse_success(t, &negative_parser, negative_outcome)
	negative_limit := negative_parser.nodes.storage[int(negative_outcome.root)]
	testing.expect_value(t, negative_limit.kind, Node_Kind.Limit)
	negative := negative_parser.nodes.storage[int(negative_limit.left)]
	testing.expect_value(t, negative.kind, Node_Kind.Negate)
	testing.expect(t, negative.has_child)
	testing.expect_value(t, negative_parser.nodes.storage[int(negative.child)].kind, Node_Kind.Number)
	testing.expect_value(t, negative_parser.nodes.storage[int(negative_limit.right)].kind, Node_Kind.Error)
	testing.expect_value(t, destroy_parser(&negative_parser), runtime.Allocator_Error.None)
}

@(test)
test_unary_minus_does_not_broaden_identifier_or_unsupported_term_subset :: proc(t: ^testing.T) {
	Case :: struct { text: string, start, end: int, actual: Token_Kind }
	cases := [?]Case{
		{"-name", 1, 5, .Identifier},
		{"-name?", 1, 5, .Identifier},
		{"-truex", 1, 6, .Identifier},
		{"-false_", 1, 7, .Identifier},
		{"-nullfoo", 1, 8, .Identifier},
		{"-+1", 1, 2, .Plus},
	}

	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_Token)
		testing.expect_value(t, outcome.error.expected, Parse_Expectation.Expression)
		testing.expect_value(t, outcome.error.actual, test_case.actual)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_supported_term_leaves_preserve_exact_prefix_and_postfix_stack_budgets :: proc(t: ^testing.T) {
	Case :: struct {
		outer_minuses, groups, inner_minuses, postfixes: int,
		payload: string,
		succeeds: bool,
	}
	cases := [?]Case{
		{9_995, 0, 0, 0, ".", true},
		{9_996, 0, 0, 0, ".", false},
		{9_995, 0, 0, 0, ".a", true},
		{9_996, 0, 0, 0, ".a", false},
		{0, 9_994, 0, 0, ".", true},
		{0, 9_995, 0, 0, ".", false},
		{0, 0, 9_994, 1, ".a", true},
		{0, 0, 9_995, 1, ".a", false},
		{9_995, 0, 0, 0, "true", true},
		{9_996, 0, 0, 0, "true", false},
		{0, 9_994, 0, 0, "false", true},
		{0, 9_995, 0, 0, "false", false},
		{0, 4_000, 5_995, 0, "null", true},
		{0, 4_000, 5_996, 0, "null", false},
		{9_993, 1, 0, 0, "true", true},
		{9_994, 1, 0, 0, "true", false},
		{0, 0, 9_994, 1, "false", true},
		{0, 0, 9_995, 1, "false", false},
		{0, 4_000, 5_994, 1, "null", true},
		{0, 4_000, 5_995, 1, "null", true},
		{0, 4_000, 5_996, 1, "null", false},
	}

	for test_case in cases {
		text := make_nested_term_filter(
			t,
			test_case.outer_minuses,
			test_case.groups,
			test_case.inner_minuses,
			test_case.postfixes,
			test_case.payload,
		)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		if test_case.succeeds {
			expect_parse_success(t, &parser, outcome)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_grouped_pipe_and_comma_leaves_preserve_exact_query_stack_boundary :: proc(t: ^testing.T) {
	Case :: struct { groups: int, payload: string, kind: Node_Kind, succeeds: bool }
	cases := [?]Case{
		{9_993, ". | .", .Pipe, true},
		{9_994, ". | .", .Pipe, false},
		{9_993, "., .", .Comma, true},
		{9_994, "., .", .Comma, false},
	}
	for test_case in cases {
		text := make_nested_term_filter(t, 0, test_case.groups, 0, 0, test_case.payload)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		if test_case.succeeds {
			expect_parse_success(t, &parser, outcome)
			node_id := outcome.root
			for _ in 0..<test_case.groups {
				node := parser.nodes.storage[int(node_id)]
				testing.expect_value(t, node.kind, Node_Kind.Parenthesized)
				node_id = node.child
			}
			testing.expect_value(t, parser.nodes.storage[int(node_id)].kind, test_case.kind)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(private="package")
expect_parser_resource_limit :: proc(t: ^testing.T, text: string) {
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_exact_unary_minus_stack_budget_without_native_recursion :: proc(t: ^testing.T) {
	SUCCESS_DEPTH :: 9_995
	success_text := make_nested_term_filter(t, SUCCESS_DEPTH, 0, 0, 0)
	defer delete(success_text)

	parser: Parser
	_, outcome := parse_test_filter(t, &parser, success_text)
	expect_parse_success(t, &parser, outcome)
	testing.expect_value(t, parser.nodes.count, SUCCESS_DEPTH+1)
	node_id := outcome.root
	for start in 0..<SUCCESS_DEPTH {
		node := parser.nodes.storage[int(node_id)]
		testing.expect_value(t, node.kind, Node_Kind.Negate)
		expect_span(t, parser.source, node.span, start, SUCCESS_DEPTH+1)
		node_id = node.child
	}
	number := parser.nodes.storage[int(node_id)]
	testing.expect_value(t, number.kind, Node_Kind.Number)
	expect_span(t, parser.source, number.span, SUCCESS_DEPTH, SUCCESS_DEPTH+1)
	testing.expect_value(t, number.number_text, "1")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)

	failure_text := make_nested_term_filter(t, SUCCESS_DEPTH+1, 0, 0, 0)
	defer delete(failure_text)
	expect_parser_resource_limit(t, failure_text)
}

@(private="package")
binary_minus_filter :: proc(t: ^testing.T, minus_count: int, rhs := false, grouped := false) -> string {
	minuses, minus_error := strings.repeat("-", minus_count)
	testing.expect(t, minus_error == nil)
	prefix := "1+" if rhs else ""
	suffix := "2" if rhs else "1+2"
	open := "(" if grouped else ""
	close := ")" if grouped else ""
	result, result_error := strings.concatenate([]string{open, prefix, minuses, suffix, close})
	testing.expect(t, result_error == nil)
	delete(minuses)
	return result
}

@(private="package")
query_binary_minus_filter :: proc(
	t: ^testing.T,
	prefix: string,
	minus_count: int,
	suffix: string,
) -> string {
	minuses, minus_error := strings.repeat("-", minus_count)
	testing.expect(t, minus_error == nil)
	result, result_error := strings.concatenate([]string{prefix, minuses, suffix})
	testing.expect(t, result_error == nil)
	delete(minuses)
	return result
}

@(test)
test_binary_arithmetic_exact_unary_minus_parser_stack_boundaries :: proc(t: ^testing.T) {
	Case :: struct { minus_count: int, rhs, grouped, succeeds: bool }
	cases := [?]Case{
		{9_995, false, false, true},
		{9_996, false, false, false},
		{9_993, true, false, true},
		{9_994, true, false, false},
		{9_992, true, true, true},
		{9_993, true, true, false},
	}
	for test_case in cases {
		text := binary_minus_filter(t, test_case.minus_count, test_case.rhs, test_case.grouped)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		if test_case.succeeds {
			expect_parse_success(t, &parser, outcome)
			root := parser.nodes.storage[int(outcome.root)]
			if test_case.grouped {
				testing.expect_value(t, root.kind, Node_Kind.Parenthesized)
				root = parser.nodes.storage[int(root.child)]
			}
			testing.expect_value(t, root.form, Node_Form.Binary)
			testing.expect_value(t, root.binary_operator, Binary_Operator.Add)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_comma_binary_rhs_preserves_exact_neighboring_query_stack_boundaries :: proc(t: ^testing.T) {
	Case :: struct { prefix: string, minus_count: int, suffix: string, succeeds: bool }
	cases := [?]Case{
		// One live comma plus the pending binary operator.
		{"1,2+", 9_991, "3", true},
		{"1,2+", 9_992, "3", false},
		// The same state inside one surrounding group.
		{"(1,2+", 9_990, "3)", true},
		{"(1,2+", 9_991, "3)", false},
		// A live pipe and binary retain the established neighboring boundary.
		{"1|2+", 9_991, "3", true},
		{"1|2+", 9_992, "3", false},
		// The first postfix state adds one entry at the deepest event.
		{"1,2+", 9_990, "3?", true},
		{"1,2+", 9_991, "3?", false},
		// Pipe, comma, and binary are simultaneously suspended.
		{"1|2,3+", 9_989, "4", true},
		{"1|2,3+", 9_990, "4", false},
		// Two comma queries, a group, and binary are simultaneously suspended.
		{"1,(2,3+", 9_988, "4)", true},
		{"1,(2,3+", 9_989, "4)", false},
	}
	for test_case in cases {
		text := query_binary_minus_filter(
			t,
			test_case.prefix,
			test_case.minus_count,
			test_case.suffix,
		)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		if test_case.succeeds {
			expect_parse_success(t, &parser, outcome)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_parser_exact_group_and_prefix_order_stack_budgets :: proc(t: ^testing.T) {
	Case :: struct {
		outer_minuses, groups, inner_minuses: int,
		succeeds: bool,
	}
	cases := [?]Case{
		{0, 9_994, 0, true},
		{0, 9_995, 0, false},
		{0, 4_000, 5_995, true},
		{0, 4_000, 5_996, false},
		{4_000, 5_994, 0, true},
		{4_000, 5_995, 0, false},
		{9_993, 1, 0, true},
		{9_994, 1, 0, false},
	}

	for test_case in cases {
		text := make_nested_term_filter(
			t,
			test_case.outer_minuses,
			test_case.groups,
			test_case.inner_minuses,
			0,
		)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		if test_case.succeeds {
			expect_parse_success(t, &parser, outcome)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_parser_only_first_postfix_increases_live_stack_depth :: proc(t: ^testing.T) {
	Case :: struct {
		groups, inner_minuses, postfixes: int,
		succeeds: bool,
	}
	cases := [?]Case{
		{0, 9_994, 1, true},
		{0, 9_995, 1, false},
		{0, 9_994, 4, true},
		{4_000, 5_994, 1, true},
		{4_000, 5_995, 1, true},
		{4_000, 5_996, 1, false},
		{4_000, 5_994, 4, true},
	}

	for test_case in cases {
		text := make_nested_term_filter(
			t,
			0,
			test_case.groups,
			test_case.inner_minuses,
			test_case.postfixes,
		)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		if test_case.succeeds {
			expect_parse_success(t, &parser, outcome)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_parser_stack_budget_preserves_below_limit_ast_and_spans :: proc(t: ^testing.T) {
	parser: Parser
	source, outcome := parse_test_filter(t, &parser, "((--1))??")
	expect_parse_success(t, &parser, outcome)
	outer_optional := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, outer_optional.kind, Node_Kind.Optional)
	expect_span(t, source, outer_optional.span, 0, 9)
	inner_optional := parser.nodes.storage[int(outer_optional.child)]
	testing.expect_value(t, inner_optional.kind, Node_Kind.Optional)
	expect_span(t, source, inner_optional.span, 0, 8)
	outer_group := parser.nodes.storage[int(inner_optional.child)]
	testing.expect_value(t, outer_group.kind, Node_Kind.Parenthesized)
	expect_span(t, source, outer_group.span, 0, 7)
	inner_group := parser.nodes.storage[int(outer_group.child)]
	testing.expect_value(t, inner_group.kind, Node_Kind.Parenthesized)
	expect_span(t, source, inner_group.span, 1, 6)
	outer_negate := parser.nodes.storage[int(inner_group.child)]
	testing.expect_value(t, outer_negate.kind, Node_Kind.Negate)
	expect_span(t, source, outer_negate.span, 2, 5)
	inner_negate := parser.nodes.storage[int(outer_negate.child)]
	testing.expect_value(t, inner_negate.kind, Node_Kind.Negate)
	expect_span(t, source, inner_negate.span, 3, 5)
	number := parser.nodes.storage[int(inner_negate.child)]
	testing.expect_value(t, number.kind, Node_Kind.Number)
	expect_span(t, source, number.span, 4, 5)
	testing.expect_value(t, number.number_text, "1")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)

	ordered_parser: Parser
	ordered_source, ordered_outcome := parse_test_filter(t, &ordered_parser, "--((1))")
	expect_parse_success(t, &ordered_parser, ordered_outcome)
	ordered_outer := ordered_parser.nodes.storage[int(ordered_outcome.root)]
	testing.expect_value(t, ordered_outer.kind, Node_Kind.Negate)
	expect_span(t, ordered_source, ordered_outer.span, 0, 7)
	ordered_inner := ordered_parser.nodes.storage[int(ordered_outer.child)]
	testing.expect_value(t, ordered_inner.kind, Node_Kind.Negate)
	expect_span(t, ordered_source, ordered_inner.span, 1, 7)
	ordered_group := ordered_parser.nodes.storage[int(ordered_inner.child)]
	testing.expect_value(t, ordered_group.kind, Node_Kind.Parenthesized)
	expect_span(t, ordered_source, ordered_group.span, 2, 7)
	nested_group := ordered_parser.nodes.storage[int(ordered_group.child)]
	testing.expect_value(t, nested_group.kind, Node_Kind.Parenthesized)
	expect_span(t, ordered_source, nested_group.span, 3, 6)
	ordered_number := ordered_parser.nodes.storage[int(nested_group.child)]
	testing.expect_value(t, ordered_number.kind, Node_Kind.Number)
	expect_span(t, ordered_source, ordered_number.span, 4, 5)
	testing.expect_value(t, destroy_parser(&ordered_parser), runtime.Allocator_Error.None)
}

@(test)
test_parser_stack_limit_failure_cleanup_is_retryable :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	text := make_nested_term_filter(t, 9_996, 0, 0, 0)
	defer delete(text)
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text, test_allocator(&allocator_data))
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect(t, len(tracker.allocation_map) > 0)
	allocator_data.free_failures_remaining = 1
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	testing.expect(t, len(tracker.allocation_map) > 0)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_comma_binary_stack_limit_failure_cleanup_is_retryable :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	text := query_binary_minus_filter(t, "1,2+", 9_992, "3")
	defer delete(text)
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text, test_allocator(&allocator_data))
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect(t, len(tracker.allocation_map) > 0)
	allocator_data.free_failures_remaining = 1
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	testing.expect(t, len(tracker.allocation_map) > 0)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_scalar_literals_compose_at_existing_term_precedence :: proc(t: ^testing.T) {
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "null?, (true | false, - 1)?.field")
	expect_parse_success(t, &parser, outcome)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Comma)
	testing.expect_value(t, parser.nodes.storage[int(root.left)].kind, Node_Kind.Optional)
	rhs := parser.nodes.storage[int(root.right)]
	testing.expect_value(t, rhs.kind, Node_Kind.Field)
	testing.expect_value(t, parser.nodes.storage[int(rhs.child)].kind, Node_Kind.Optional)
	group := parser.nodes.storage[int(parser.nodes.storage[int(rhs.child)].child)]
	testing.expect_value(t, group.kind, Node_Kind.Parenthesized)
	pipe := parser.nodes.storage[int(group.child)]
	testing.expect_value(t, pipe.kind, Node_Kind.Pipe)
	comma := parser.nodes.storage[int(pipe.right)]
	testing.expect_value(t, comma.kind, Node_Kind.Comma)
	negate := parser.nodes.storage[int(comma.right)]
	testing.expect_value(t, negate.kind, Node_Kind.Negate)
	number := parser.nodes.storage[int(negate.child)]
	testing.expect_value(t, number.kind, Node_Kind.Number)
	testing.expect_value(t, number.number_text, "1")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)

	negative_parser: Parser
	_, negative_outcome := parse_test_filter(t, &negative_parser, "-1?.field")
	expect_parse_success(t, &negative_parser, negative_outcome)
	negative := negative_parser.nodes.storage[int(negative_outcome.root)]
	testing.expect_value(t, negative.kind, Node_Kind.Negate)
	field := negative_parser.nodes.storage[int(negative.child)]
	testing.expect_value(t, field.kind, Node_Kind.Field)
	optional := negative_parser.nodes.storage[int(field.child)]
	testing.expect_value(t, optional.kind, Node_Kind.Optional)
	testing.expect_value(t, negative_parser.nodes.storage[int(optional.child)].kind, Node_Kind.Number)
	testing.expect_value(t, destroy_parser(&negative_parser), runtime.Allocator_Error.None)
}

@(test)
test_scalar_keyword_and_rejected_number_boundaries_are_not_split :: proc(t: ^testing.T) {
	Case :: struct { text: string, start, end: int, actual: Token_Kind }
	cases := [?]Case{
		{"nullfoo", 0, 7, .Identifier},
		{"truex", 0, 5, .Identifier},
		{"false_", 0, 6, .Identifier},
		{"1foo", 1, 4, .Identifier},
		{"1e", 1, 2, .Identifier},
		{"1e+", 1, 2, .Identifier},
		{".1e+", 2, 3, .Identifier},
		{"1..2", 2, 4, .Number},
		{"+1", 0, 1, .Plus},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_Token)
		testing.expect_value(t, outcome.error.actual, test_case.actual)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_owned_numeric_text_survives_caller_input_release :: proc(t: ^testing.T) {
	input := make([]byte, len("- 1.25e+2"))
	copy(input, "- 1.25e+2")
	source := diagnostic.borrow_source("<released-input>", string(input))
	parser: Parser
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	expect_parse_success(t, &parser, outcome)
	negate := &parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, negate.kind, Node_Kind.Negate)
	node := &parser.nodes.storage[int(negate.child)]
	testing.expect(t, node.has_number_text)
	delete(input)
	testing.expect_value(t, node.number_text, "1.25e+2")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
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
test_binary_arithmetic_each_operator_has_exact_ast_and_source_spans :: proc(t: ^testing.T) {
	Case :: struct { text: string, operator: Binary_Operator }
	cases := [?]Case{
		{"1 + 2", .Add},
		{"1 - 2", .Subtract},
		{"1 * 2", .Multiply},
		{"1 / 2", .Divide},
		{"1 % 2", .Modulo},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		root := expect_binary_node(t, &parser, outcome.root, test_case.operator, 0, 5, 2, 3)
		testing.expect_value(t, parser.nodes.storage[int(root.left)].kind, Node_Kind.Number)
		testing.expect_value(t, parser.nodes.storage[int(root.right)].kind, Node_Kind.Number)
		expect_node_span(t, &parser, root.left, 0, 1)
		expect_node_span(t, &parser, root.right, 4, 5)
		distinct_source := diagnostic.borrow_source("<distinct>", test_case.text)
		_, _, distinct_ok := diagnostic.span_offsets(distinct_source, root.operator_span)
		testing.expect(t, !distinct_ok)
		testing.expect_value(t, parser_source(&parser), source)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_binary_arithmetic_precedence_and_left_associativity :: proc(t: ^testing.T) {
	text :: "1 - 2 - 3 + 4 * 5 / 6 % 7"
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text)
	expect_parse_success(t, &parser, outcome)

	add := expect_binary_node(t, &parser, outcome.root, .Add, 0, len(text), 10, 11)
	second_subtract := expect_binary_node(t, &parser, add.left, .Subtract, 0, 9, 6, 7)
	first_subtract := expect_binary_node(t, &parser, second_subtract.left, .Subtract, 0, 5, 2, 3)
	testing.expect_value(t, parser.nodes.storage[int(first_subtract.left)].number_text, "1")
	testing.expect_value(t, parser.nodes.storage[int(first_subtract.right)].number_text, "2")
	testing.expect_value(t, parser.nodes.storage[int(second_subtract.right)].number_text, "3")

	modulo := expect_binary_node(t, &parser, add.right, .Modulo, 12, len(text), 22, 23)
	divide := expect_binary_node(t, &parser, modulo.left, .Divide, 12, 21, 18, 19)
	multiply := expect_binary_node(t, &parser, divide.left, .Multiply, 12, 17, 14, 15)
	testing.expect_value(t, parser.nodes.storage[int(multiply.left)].number_text, "4")
	testing.expect_value(t, parser.nodes.storage[int(multiply.right)].number_text, "5")
	testing.expect_value(t, parser.nodes.storage[int(divide.right)].number_text, "6")
	testing.expect_value(t, parser.nodes.storage[int(modulo.right)].number_text, "7")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_binary_arithmetic_parentheses_unary_minus_and_postfix_precedence :: proc(t: ^testing.T) {
	text :: "-1 + 2 * -(3 + 4)?"
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text)
	expect_parse_success(t, &parser, outcome)
	add := expect_binary_node(t, &parser, outcome.root, .Add, 0, len(text), 3, 4)
	left_negate := parser.nodes.storage[int(add.left)]
	testing.expect_value(t, left_negate.kind, Node_Kind.Negate)
	expect_node_span(t, &parser, add.left, 0, 2)
	multiply := expect_binary_node(t, &parser, add.right, .Multiply, 5, len(text), 7, 8)
	testing.expect_value(t, parser.nodes.storage[int(multiply.left)].number_text, "2")
	right_negate := parser.nodes.storage[int(multiply.right)]
	testing.expect_value(t, right_negate.kind, Node_Kind.Negate)
	optional := parser.nodes.storage[int(right_negate.child)]
	testing.expect_value(t, optional.kind, Node_Kind.Optional)
	group := parser.nodes.storage[int(optional.child)]
	testing.expect_value(t, group.kind, Node_Kind.Parenthesized)
	inner := expect_binary_node(t, &parser, group.child, .Add, 11, 16, 13, 14)
	testing.expect_value(t, parser.nodes.storage[int(inner.left)].number_text, "3")
	testing.expect_value(t, parser.nodes.storage[int(inner.right)].number_text, "4")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)

	chain: Parser
	_, chain_outcome := parse_test_filter(t, &chain, "1 - - -2")
	expect_parse_success(t, &chain, chain_outcome)
	subtract := expect_binary_node(t, &chain, chain_outcome.root, .Subtract, 0, 8, 2, 3)
	outer := chain.nodes.storage[int(subtract.right)]
	inner_negate := chain.nodes.storage[int(outer.child)]
	testing.expect_value(t, outer.kind, Node_Kind.Negate)
	testing.expect_value(t, inner_negate.kind, Node_Kind.Negate)
	testing.expect_value(t, destroy_parser(&chain), runtime.Allocator_Error.None)
}

@(test)
test_binary_arithmetic_comma_pipe_and_optional_interactions :: proc(t: ^testing.T) {
	text :: "1? + 2?, 3 * 4 | (5 % 2)?"
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text)
	expect_parse_success(t, &parser, outcome)
	pipe := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, pipe.kind, Node_Kind.Pipe)
	comma := parser.nodes.storage[int(pipe.left)]
	testing.expect_value(t, comma.kind, Node_Kind.Comma)
	add := parser.nodes.storage[int(comma.left)]
	multiply := parser.nodes.storage[int(comma.right)]
	testing.expect_value(t, add.form, Node_Form.Binary)
	testing.expect_value(t, add.binary_operator, Binary_Operator.Add)
	testing.expect_value(t, parser.nodes.storage[int(add.left)].kind, Node_Kind.Optional)
	testing.expect_value(t, parser.nodes.storage[int(add.right)].kind, Node_Kind.Optional)
	testing.expect_value(t, multiply.form, Node_Form.Binary)
	testing.expect_value(t, multiply.binary_operator, Binary_Operator.Multiply)
	right_optional := parser.nodes.storage[int(pipe.right)]
	testing.expect_value(t, right_optional.kind, Node_Kind.Optional)
	right_group := parser.nodes.storage[int(right_optional.child)]
	modulo := parser.nodes.storage[int(right_group.child)]
	testing.expect_value(t, modulo.form, Node_Form.Binary)
	testing.expect_value(t, modulo.binary_operator, Binary_Operator.Modulo)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_binary_arithmetic_whitespace_and_minus_token_boundaries_match_oracle :: proc(t: ^testing.T) {
	Case :: struct { text: string, operator: Binary_Operator }
	cases := [?]Case{
		{"1+2", .Add},
		{".1+.2", .Add},
		{"1e-2+3", .Add},
		{"1 +\n -2", .Add},
		{"1+-2", .Add},
		{"1--2", .Subtract},
		{"1*-2", .Multiply},
		{"1/-2", .Divide},
		{"1%-2", .Modulo},
		{"--1+2", .Add},
	}
	for test_case in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, root.form, Node_Form.Binary)
		testing.expect_value(t, root.binary_operator, test_case.operator)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_comparison_each_operator_has_exact_ast_and_source_spans :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		operator: Binary_Operator,
		operator_start, operator_end: int,
	}
	cases := [?]Case{
		{"1 == 2", .Equal, 2, 4},
		{"1 != 2", .Not_Equal, 2, 4},
		{"1 < 2", .Less, 2, 3},
		{"1 <= 2", .Less_Equal, 2, 4},
		{"1 > 2", .Greater, 2, 3},
		{"1 >= 2", .Greater_Equal, 2, 4},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		root := expect_binary_node(
			t,
			&parser,
			outcome.root,
			test_case.operator,
			0,
			len(test_case.text),
			test_case.operator_start,
			test_case.operator_end,
		)
		testing.expect_value(t, parser.nodes.storage[int(root.left)].kind, Node_Kind.Number)
		testing.expect_value(t, parser.nodes.storage[int(root.right)].kind, Node_Kind.Number)
		expect_node_span(t, &parser, root.left, 0, 1)
		expect_node_span(t, &parser, root.right, len(test_case.text)-1, len(test_case.text))
		distinct_source := diagnostic.borrow_source("<distinct-comparison>", test_case.text)
		_, _, distinct_ok := diagnostic.span_offsets(distinct_source, root.operator_span)
		testing.expect(t, !distinct_ok)
		testing.expect_value(t, parser_source(&parser), source)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_comparison_precedence_is_looser_than_arithmetic_and_tighter_than_query :: proc(t: ^testing.T) {
	text :: "1 + 2 * 3 <= -4 % 5, 6 | 7 > 8"
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text)
	expect_parse_success(t, &parser, outcome)

	pipe := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, pipe.kind, Node_Kind.Pipe)
	comma := parser.nodes.storage[int(pipe.left)]
	testing.expect_value(t, comma.kind, Node_Kind.Comma)
	less_equal := expect_binary_node(t, &parser, comma.left, .Less_Equal, 0, 19, 10, 12)
	add := expect_binary_node(t, &parser, less_equal.left, .Add, 0, 9, 2, 3)
	multiply := expect_binary_node(t, &parser, add.right, .Multiply, 4, 9, 6, 7)
	testing.expect_value(t, parser.nodes.storage[int(multiply.left)].number_text, "2")
	testing.expect_value(t, parser.nodes.storage[int(multiply.right)].number_text, "3")
	modulo := expect_binary_node(t, &parser, less_equal.right, .Modulo, 13, 19, 16, 17)
	testing.expect_value(t, parser.nodes.storage[int(modulo.left)].kind, Node_Kind.Negate)
	testing.expect_value(t, parser.nodes.storage[int(comma.right)].number_text, "6")
	greater := expect_binary_node(t, &parser, pipe.right, .Greater, 25, len(text), 27, 28)
	testing.expect_value(t, parser.nodes.storage[int(greater.left)].number_text, "7")
	testing.expect_value(t, parser.nodes.storage[int(greater.right)].number_text, "8")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_comparison_postfix_unary_grouping_and_comments_match_oracle_boundaries :: proc(t: ^testing.T) {
	Case :: struct { text: string, operator: Binary_Operator }
	cases := [?]Case{
		{"1<2", .Less},
		{"1 <=\n-2", .Less_Equal},
		{"1<# comment\n2", .Less},
		{"1# lhs\n==# operator\n1", .Equal},
		{"1? > 0?", .Greater},
		{"-(1 < 2)", .Less},
		{"(1 >= 2)?", .Greater_Equal},
	}
	for test_case in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		root := parser.nodes.storage[int(outcome.root)]
		if root.kind == .Negate || root.kind == .Optional {
			root = parser.nodes.storage[int(root.child)]
		}
		if root.kind == .Parenthesized {
			root = parser.nodes.storage[int(root.child)]
		}
		testing.expect_value(t, root.form, Node_Form.Binary)
		testing.expect_value(t, root.binary_operator, test_case.operator)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_comparison_operators_are_nonassociative_without_parentheses :: proc(t: ^testing.T) {
	Case :: struct { text: string, start, end: int, actual: Token_Kind }
	cases := [?]Case{
		{"1 < 2 < 3", 6, 7, .Less},
		{"1 < 2 <= 3", 6, 8, .Less_Equal},
		{"1 == 1 != 0", 7, 9, .Not_Equal},
		{"1 + 2 <= 3 * 4 >= 5", 15, 17, .Greater_Equal},
		{"1 > 2 == 3", 6, 8, .Equal},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_Token)
		testing.expect_value(t, outcome.error.expected, Parse_Expectation.End_Of_Input)
		testing.expect(t, outcome.error.has_actual)
		testing.expect_value(t, outcome.error.actual, test_case.actual)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_comparison_chain_diagnostic_uses_active_parenthesized_boundary :: proc(t: ^testing.T) {
	Case :: struct { text: string, start, end: int, actual: Token_Kind }
	cases := [?]Case{
		// One, two, and deeper active parenthesized frames.
		{"(1 < 2 < 3)", 7, 8, .Less},
		{"((1 < 2 == 3))", 8, 10, .Equal},
		{"((((1 != 2 >= 3))))", 11, 13, .Greater_Equal},
		// The group remains the active diagnostic boundary under prefix and postfix forms.
		{"-(1 < 2 < 3)", 8, 9, .Less},
		{"(1 < 2 != 3)?", 7, 9, .Not_Equal},
		{"-(1 < 2 <= 3)?", 8, 10, .Less_Equal},
		// A grouped chain can occur on either side of supported comma and pipe forms.
		{"(1 < 2 < 3), .", 7, 8, .Less},
		{"., (1 < 2 == 3)", 10, 12, .Equal},
		{"(1 < 2 != 3) | .", 7, 9, .Not_Equal},
		{". | (1 < 2 >= 3)", 11, 13, .Greater_Equal},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_Token)
		testing.expect_value(t, outcome.error.expected, Parse_Expectation.Close_Paren)
		testing.expect(t, outcome.error.has_actual)
		testing.expect_value(t, outcome.error.actual, test_case.actual)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_parentheses_explicitly_group_comparison_chains :: proc(t: ^testing.T) {
	Case :: struct { text: string, outer, inner: Binary_Operator, inner_on_left: bool }
	cases := [?]Case{
		{"(1 < 2) < 3", .Less, .Less, true},
		{"1 == (1 != 0)", .Equal, .Not_Equal, false},
		{"(1 + 2 <= 4) >= 0", .Greater_Equal, .Less_Equal, true},
	}
	for test_case in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		outer := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, outer.form, Node_Form.Binary)
		testing.expect_value(t, outer.binary_operator, test_case.outer)
		group_id := outer.left if test_case.inner_on_left else outer.right
		group := parser.nodes.storage[int(group_id)]
		testing.expect_value(t, group.kind, Node_Kind.Parenthesized)
		inner := parser.nodes.storage[int(group.child)]
		testing.expect_value(t, inner.form, Node_Form.Binary)
		testing.expect_value(t, inner.binary_operator, test_case.inner)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_comparison_exact_generated_parser_stack_boundaries :: proc(t: ^testing.T) {
	Case :: struct { prefix: string, minus_count: int, suffix: string, succeeds: bool }
	cases := [?]Case{
		{"", 9_995, "1<2", true},
		{"", 9_996, "1<2", false},
		{"1<", 9_993, "2", true},
		{"1<", 9_994, "2", false},
		{"(1<", 9_992, "2)", true},
		{"(1<", 9_993, "2)", false},
		{"1<2+", 9_991, "3", true},
		{"1<2+", 9_992, "3", false},
	}
	for test_case in cases {
		text := query_binary_minus_filter(t, test_case.prefix, test_case.minus_count, test_case.suffix)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		if test_case.succeeds {
			expect_parse_success(t, &parser, outcome)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_boolean_and_alternative_operators_have_exact_ast_and_source_spans :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		operator: Binary_Operator,
		operator_start, operator_end: int,
	}
	cases := [?]Case{
		{"true and false", .And, 5, 8},
		{"false or true", .Or, 6, 8},
		{"null // 42", .Defined_Or, 5, 7},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		root := expect_binary_node(
			t,
			&parser,
			outcome.root,
			test_case.operator,
			0,
			len(test_case.text),
			test_case.operator_start,
			test_case.operator_end,
		)
		_, _, left_span_ok := diagnostic.span_offsets(source, parser.nodes.storage[int(root.left)].span)
		_, _, right_span_ok := diagnostic.span_offsets(source, parser.nodes.storage[int(root.right)].span)
		testing.expect(t, left_span_ok && right_span_ok)
		distinct_source := diagnostic.borrow_source("<distinct-boolean>", test_case.text)
		_, _, distinct_ok := diagnostic.span_offsets(distinct_source, root.operator_span)
		testing.expect(t, !distinct_ok)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_boolean_and_alternative_precedence_matches_jq_grammar :: proc(t: ^testing.T) {
	text :: "1 // 2 or 3 and 4 == 5 + 6 * 7, 8 | 9 // 10"
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text)
	expect_parse_success(t, &parser, outcome)

	pipe := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, pipe.kind, Node_Kind.Pipe)
	comma := parser.nodes.storage[int(pipe.left)]
	testing.expect_value(t, comma.kind, Node_Kind.Comma)
	alternative := expect_binary_node(t, &parser, comma.left, .Defined_Or, 0, 30, 2, 4)
	boolean_or := expect_binary_node(t, &parser, alternative.right, .Or, 5, 30, 7, 9)
	boolean_and := expect_binary_node(t, &parser, boolean_or.right, .And, 10, 30, 12, 15)
	comparison := expect_binary_node(t, &parser, boolean_and.right, .Equal, 16, 30, 18, 20)
	add := expect_binary_node(t, &parser, comparison.right, .Add, 21, 30, 23, 24)
	multiply := expect_binary_node(t, &parser, add.right, .Multiply, 25, 30, 27, 28)
	testing.expect_value(t, parser.nodes.storage[int(comma.right)].number_text, "8")
	right_alternative := expect_binary_node(t, &parser, pipe.right, .Defined_Or, 36, len(text), 38, 40)
	testing.expect_value(t, parser.nodes.storage[int(right_alternative.left)].number_text, "9")
	testing.expect_value(t, parser.nodes.storage[int(right_alternative.right)].number_text, "10")
	testing.expect_value(t, parser.nodes.storage[int(multiply.left)].number_text, "6")
	testing.expect_value(t, parser.nodes.storage[int(multiply.right)].number_text, "7")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_boolean_is_left_associative_and_alternative_is_right_associative :: proc(t: ^testing.T) {
	Case :: struct { text: string, operator: Binary_Operator, right_associative: bool }
	cases := [?]Case{
		{"true and false and true", .And, false},
		{"false or false or true", .Or, false},
		{"null // false // true", .Defined_Or, true},
	}
	for test_case in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, test_case.text)
		expect_parse_success(t, &parser, outcome)
		outer := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, outer.form, Node_Form.Binary)
		testing.expect_value(t, outer.binary_operator, test_case.operator)
		nested_id := outer.right if test_case.right_associative else outer.left
		nested := parser.nodes.storage[int(nested_id)]
		testing.expect_value(t, nested.form, Node_Form.Binary)
		testing.expect_value(t, nested.binary_operator, test_case.operator)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_boolean_and_alternative_grouping_comments_newlines_and_postfix :: proc(t: ^testing.T) {
	cases := [?]string{
		"(true or false) and true",
		"true# lhs\n and# operator\n false",
		"null //\n-1?",
		"(null // false)? or true",
		"-(1 == 1 and 2 < 3)",
	}
	for text in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		expect_parse_success(t, &parser, outcome)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_boolean_and_alternative_malformed_diagnostics_are_structured :: proc(t: ^testing.T) {
	Case :: struct { text: string, start, end: int, actual: Token_Kind, expected: Parse_Expectation }
	cases := [?]Case{
		{"and true", 0, 3, .And, .Expression},
		{"or false", 0, 2, .Or, .Expression},
		{"// null", 0, 2, .Defined_Or, .Expression},
		{"true and or false", 9, 11, .Or, .Expression},
		{"false or // true", 9, 11, .Defined_Or, .Expression},
		{"null // and true", 8, 11, .And, .Expression},
		{"1 / / 2", 4, 5, .Divide, .Expression},
		{"1 /// 2", 4, 5, .Divide, .Expression},
		{"(true and)", 9, 10, .Close_Paren, .Expression},
	}
	for test_case in cases {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, test_case.text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_Token)
		testing.expect_value(t, outcome.error.expected, test_case.expected)
		testing.expect(t, outcome.error.has_actual)
		testing.expect_value(t, outcome.error.actual, test_case.actual)
		expect_span(t, source, outcome.error.span, test_case.start, test_case.end)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}

	missing_rhs := [?]string{"true and", "false or", "null //"}
	for text in missing_rhs {
		parser: Parser
		source, outcome := parse_test_filter(t, &parser, text)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, outcome.error.kind, Parse_Error_Kind.Unexpected_End)
		testing.expect_value(t, outcome.error.expected, Parse_Expectation.Expression)
		expect_span(t, source, outcome.error.span, len(text), len(text))
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(private="package")
alternative_filter :: proc(operator_count: int) -> string {
	prefix, prefix_error := strings.repeat("null//", operator_count)
	assert(prefix_error == nil)
	result, result_error := strings.concatenate([]string{prefix, "null"})
	assert(result_error == nil)
	delete(prefix)
	return result
}

@(test)
test_boolean_and_alternative_exact_generated_parser_stack_boundaries :: proc(t: ^testing.T) {
	for operator_count in 4_997..=4_998 {
		text := alternative_filter(operator_count)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		if operator_count == 4_997 {
			expect_parse_success(t, &parser, outcome)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}

	Case :: struct { prefix: string, minus_count: int, suffix: string, succeeds: bool }
	cases := [?]Case{
		{"true and ", 9_993, "1", true},
		{"true and ", 9_994, "1", false},
		{"false or ", 9_993, "1", true},
		{"false or ", 9_994, "1", false},
		{"null // ", 9_993, "1", true},
		{"null // ", 9_994, "1", false},
	}
	for test_case in cases {
		text := query_binary_minus_filter(t, test_case.prefix, test_case.minus_count, test_case.suffix)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		if test_case.succeeds {
			expect_parse_success(t, &parser, outcome)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_alternative_stack_limit_failure_cleanup_is_retryable :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	text := alternative_filter(4_998)
	defer delete(text)
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text, test_allocator(&allocator_data))
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect(t, len(tracker.allocation_map) > 0)
	allocator_data.free_failures_remaining = 1
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	testing.expect(t, len(tracker.allocation_map) > 0)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	mem.tracking_allocator_destroy(&tracker)
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
		{"1+", .Unexpected_End, .Expression, 2, 2},
		{"1/", .Unexpected_End, .Expression, 2, 2},
		{"1++2", .Unexpected_Token, .Expression, 2, 3},
		{"1+*2", .Unexpected_Token, .Expression, 2, 3},
		{"1*/2", .Unexpected_Token, .Expression, 2, 3},
		{"+1", .Unexpected_Token, .Expression, 0, 1},
		{"(1+)", .Unexpected_Token, .Expression, 3, 4},
		{"(1+2", .Unexpected_End, .Close_Paren, 4, 4},
		{"1+)", .Lexical_Error, .Expression, 2, 3},
		{"1 2", .Unexpected_Token, .End_Of_Input, 2, 3},
		{"1% %2", .Unexpected_Token, .Expression, 3, 4},
		{"1 ==", .Unexpected_End, .Expression, 4, 4},
		{"== 1", .Unexpected_Token, .Expression, 0, 2},
		{"1 < = 2", .Unexpected_Token, .Expression, 4, 5},
		{"1 <== 2", .Unexpected_Token, .Expression, 4, 5},
		{"1 !== 2", .Unexpected_Token, .Expression, 4, 5},
		{"1 <> 2", .Unexpected_Token, .Expression, 3, 4},
		{"1 <= >= 2", .Unexpected_Token, .Expression, 5, 7},
		{"1 ! 2", .Lexical_Error, .End_Of_Input, 2, 3},
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
		"..",
		".a",
		"(.)",
		".?",
		".a.b",
		".a?.b?",
		"(.a?).b",
		"., .a | .b",
		".a | .b, .c",
		". // .",
	}
	rejected := [?]string{
		"",
		"(",
		".a.",
		"(.a).?",
		".a..b",
		".a?name",
		"{a:}",
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
	testing.expect_value(t, filter_count, 1919)
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
pipe_filter :: proc(pipe_count: int, term := ".") -> string {
	segment, segment_error := strings.concatenate([]string{term, "|"})
	assert(segment_error == nil)
	prefix, prefix_error := strings.repeat(segment, pipe_count)
	assert(prefix_error == nil)
	result, result_error := strings.concatenate([]string{prefix, term})
	assert(result_error == nil)
	delete(segment)
	delete(prefix)
	return result
}

@(private="package")
grouped_pipe_filter :: proc(group_count, pipe_count: int, postfix := false) -> string {
	opens, opens_error := strings.repeat("(", group_count)
	assert(opens_error == nil)
	chain := pipe_filter(pipe_count)
	closes, closes_error := strings.repeat(")", group_count)
	assert(closes_error == nil)
	suffix := "?" if postfix else ""
	result, result_error := strings.concatenate([]string{opens, chain, closes, suffix})
	assert(result_error == nil)
	delete(opens)
	delete(chain)
	delete(closes)
	return result
}

@(private="package")
pipe_rhs_minus_filter :: proc(pipe_count, minus_count, postfix_count: int) -> string {
	prefix, prefix_error := strings.repeat(".|", pipe_count)
	assert(prefix_error == nil)
	minuses, minuses_error := strings.repeat("-", minus_count)
	assert(minuses_error == nil)
	postfixes, postfixes_error := strings.repeat("?", postfix_count)
	assert(postfixes_error == nil)
	result, result_error := strings.concatenate([]string{prefix, minuses, "1", postfixes})
	assert(result_error == nil)
	delete(prefix)
	delete(minuses)
	delete(postfixes)
	return result
}

@(private="package")
nested_pipe_filter :: proc(inner_pipe_count, inner_postfixes, outer_postfixes: int) -> string {
	inner := pipe_filter(inner_pipe_count)
	inner_suffix, inner_suffix_error := strings.repeat("?", inner_postfixes)
	assert(inner_suffix_error == nil)
	outer_suffix, outer_suffix_error := strings.repeat("?", outer_postfixes)
	assert(outer_suffix_error == nil)
	result, result_error := strings.concatenate(
		[]string{".|(", inner, inner_suffix, ")", outer_suffix},
	)
	assert(result_error == nil)
	delete(inner)
	delete(inner_suffix)
	delete(outer_suffix)
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
test_parser_exact_oracle_pipe_boundaries_for_supported_terms :: proc(t: ^testing.T) {
	Case :: struct { term: string, pipe_count: int, succeeds: bool }
	cases := [?]Case{
		{".", 4_997, true},
		{".", 4_998, false},
		{"1", 4_997, true},
		{"1", 4_998, false},
		{".field?", 4_997, true},
		{".field?", 4_998, false},
	}
	for test_case in cases {
		text := pipe_filter(test_case.pipe_count, test_case.term)
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, text)
		if test_case.succeeds {
			expect_parse_success(t, &parser, outcome)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(text)
	}
}

@(test)
test_parser_stack_budget_uses_simultaneously_live_grammar_states :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		succeeds: bool,
	}
	cases := [?]Case{
		{grouped_pipe_filter(9_994, 0, true), true},
		{grouped_pipe_filter(9_995, 0, true), false},
		{grouped_pipe_filter(9_795, 100), true},
		{grouped_pipe_filter(9_796, 100), false},
		{grouped_pipe_filter(9_795, 100, true), true},
		{grouped_pipe_filter(9_796, 100, true), false},
		{pipe_rhs_minus_filter(100, 9_795, 0), true},
		{pipe_rhs_minus_filter(100, 9_796, 0), false},
		{pipe_rhs_minus_filter(100, 9_794, 1), true},
		{pipe_rhs_minus_filter(100, 9_795, 1), false},
		{nested_pipe_filter(4_996, 0, 0), true},
		{nested_pipe_filter(4_997, 0, 0), false},
		{nested_pipe_filter(4_995, 1, 0), true},
		{nested_pipe_filter(4_996, 1, 0), false},
		{nested_pipe_filter(4_996, 0, 1), true},
		{nested_pipe_filter(4_997, 0, 1), false},
	}
	for test_case in cases {
		parser: Parser
		_, outcome := parse_test_filter(t, &parser, test_case.text)
		if test_case.succeeds {
			expect_parse_success(t, &parser, outcome)
		} else {
			testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
			testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
		}
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
		delete(test_case.text)
	}
}

@(test)
test_parser_pipe_stack_limit_failure_cleanup_is_retryable :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	text := pipe_filter(4_998, "1")
	defer delete(text)
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, text, test_allocator(&allocator_data))
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect(t, len(tracker.allocation_map) > 0)
	allocator_data.free_failures_remaining = 1
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	testing.expect(t, len(tracker.allocation_map) > 0)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	mem.tracking_allocator_destroy(&tracker)
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
	text :: "((((.root + .first?.second < 9 and true)))) // false or .fallback | ((.x?.y * .z??.last), (. - . / . % . >= 0))"
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
test_group_frame_growth_free_failure_preserves_retryable_owner :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
		free_fail_at = 3,
		resize_unsupported = true,
	}
	parser: Parser
	_, outcome := parse_test_filter(
		t,
		&parser,
		"(((((((((.",
		test_allocator(&allocator_data),
	)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.frames.count, 8)
	testing.expect_value(t, parser.frames.state, Fallible_Buffer_State.Transfer_Pending)
	testing.expect(t, parser.frames.storage != nil)
	testing.expect(t, parser.frames.replacement != nil)
	testing.expect_value(t, len(tracker.allocation_map), 4)

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
test_numeric_text_allocation_failures_and_cleanup_are_complete :: proc(t: ^testing.T) {
	text :: "1, - 2 | (3.0e+4)?"
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
	testing.expect(t, allocation_points >= 4)
	testing.expect_value(t, destroy_parser(&baseline), runtime.Allocator_Error.None)

	for fail_at in 1..=allocation_points {
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
		testing.expect_value(t, len(tracker.allocation_map), 0)
		mem.tracking_allocator_destroy(&tracker)
	}
}

@(test)
test_numeric_text_free_failure_preserves_owner_for_retry :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "123", test_allocator(&allocator_data))
	expect_parse_success(t, &parser, outcome)
	node := &parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, node.number_text, "123")
	allocator_data.free_failures_remaining = 1
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	testing.expect(t, node.has_number_text)
	testing.expect_value(t, node.number_text, "123")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_mutable_scalar_payload_cannot_redirect_private_allocation_cleanup :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	parser: Parser
	_, outcome := parse_test_filter(
		t,
		&parser,
		"1|22|333|4444|55555|666666",
		test_allocator(&allocator_data),
	)
	expect_parse_success(t, &parser, outcome)
	public_nodes := parser_nodes(&parser)
	numbers: [6]^Node
	number_count := 0
	non_scalar: ^Node
	for &node in public_nodes {
		if node.kind == .Number {
			numbers[number_count] = &node
			number_count += 1
		} else if non_scalar == nil {
			non_scalar = &node
		}
	}
	testing.expect_value(t, number_count, len(numbers))
	testing.expect(t, non_scalar != nil)
	testing.expect_value(t, parser.number_allocations.count, len(numbers))

	stack_text := [4]byte{'s', 't', 'a', 'k'}
	embedded_nul := [3]byte{'x', 0, 'y'}
	numbers[0].number_text = "static-unowned"
	numbers[0].has_number_text = false
	numbers[1].number_text = transmute(string)stack_text[:]
	numbers[1].has_number_text = true
	numbers[2].number_text = transmute(string)embedded_nul[:]
	numbers[2].has_number_text = false
	zero_length := transmute(runtime.Raw_String)numbers[3].number_text
	zero_length.len = 0
	numbers[3].number_text = transmute(string)zero_length
	numbers[4].number_text = numbers[5].number_text
	numbers[4].has_number_text = true
	pointer_only := transmute(runtime.Raw_String)numbers[5].number_text
	static_header := transmute(runtime.Raw_String)string("q")
	pointer_only.data = static_header.data
	numbers[5].number_text = transmute(string)pointer_only
	numbers[5].has_number_text = false
	// Odin strings expose pointer and length but no capacity. Corrupt a
	// non-scalar too, proving registry iteration is not selected through nodes.
	non_scalar.number_text = transmute(string)embedded_nul[:]
	non_scalar.has_number_text = true

	live_before := len(tracker.allocation_map)
	free_before := allocator_data.free_count
	testing.expect(t, live_before >= len(numbers)+2)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.free_count-free_before, live_before)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	allocator_data.alive = false
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.calls_after_retirement, 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_corrupted_scalar_aliases_preserve_cleanup_failure_retry_cursor :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "1|22|333", test_allocator(&allocator_data))
	expect_parse_success(t, &parser, outcome)
	public_nodes := parser_nodes(&parser)
	numbers: [3]^Node
	number_count := 0
	for &node in public_nodes {
		if node.kind == .Number {
			numbers[number_count] = &node
			number_count += 1
		}
	}
	testing.expect_value(t, number_count, len(numbers))
	numbers[0].number_text = numbers[1].number_text
	numbers[0].has_number_text = false
	stack_bytes := [2]byte{'z', 0}
	numbers[1].number_text = transmute(string)stack_bytes[:]
	numbers[1].has_number_text = true
	numbers[2].number_text = ""
	numbers[2].has_number_text = false

	live_before := len(tracker.allocation_map)
	free_before := allocator_data.free_count
	allocator_data.free_fail_at = free_before+2
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	testing.expect(t, parser.number_allocations.storage[0].memory == nil)
	testing.expect(t, parser.number_allocations.storage[1].memory != nil)
	testing.expect_value(t, len(tracker.allocation_map), live_before-1)
	testing.expect_value(t, len(tracker.bad_free_array), 0)

	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.free_count-free_before, live_before+1)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	allocator_data.alive = false
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.calls_after_retirement, 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_short_allocator_result_cannot_escape_numeric_parser :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
		short_success = true,
	}
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "123", test_allocator(&allocator_data))
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_exact_length_nil_backing_numeric_allocation_is_retryably_cleaned :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
		exact_nil_at = 2,
		free_failures_remaining = 1,
	}
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "123", test_allocator(&allocator_data))
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, allocator_data.request_count, 2)
	testing.expect_value(t, parser.nodes.count, 1)
	testing.expect(t, !parser.nodes.storage[0].has_number_text)
	testing.expect(t, parser.pending_number_text == nil)
	testing.expect_value(t, len(tracker.allocation_map), 1)

	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	testing.expect_value(t, len(tracker.allocation_map), 1)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	allocator_data.alive = false
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.calls_after_retirement, 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_short_numeric_allocation_failed_retirement_is_retryable :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	parser: Parser
	testing.expect(t, init_parser(
		&parser,
		diagnostic.borrow_source("<short-number>", "123"),
		test_allocator(&allocator_data),
	))
	// Let the node arena allocate normally, then make the second request (the
	// numeric text) short and fail its first retirement.
	allocator_data.short_at = 2
	allocator_data.free_failures_remaining = 1
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect_value(t, outcome.resource_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect(t, parser.pending_number_text != nil)
	testing.expect_value(t, len(tracker.allocation_map), 2)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(private="package")
expect_invalid_parser_copy :: proc(t: ^testing.T, parser: ^Parser) {
	testing.expect_value(t, parse_filter(parser).kind, Parse_Outcome_Kind.Misuse)
	testing.expect(t, parser_nodes(parser) == nil)
	testing.expect_value(t, parser_source(parser), diagnostic.Source{})
	testing.expect_value(t, destroy_parser(parser), runtime.Allocator_Error.Invalid_Argument)
}

@(test)
test_parser_shallow_copy_runtime_guards_preserve_ready_original :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<copy-ready>", "123")
	parser: Parser
	testing.expect(t, init_parser(&parser, source, context.allocator))
	copied := parser
	copy_of_copy := copied

	expect_invalid_parser_copy(t, &copied)
	expect_invalid_parser_copy(t, &copy_of_copy)
	testing.expect(t, !init_parser(&copied, source, context.allocator))

	outcome := parse_filter(&parser)
	expect_parse_success(t, &parser, outcome)
	testing.expect_value(t, parser_nodes(&parser)[int(outcome.root)].number_text, "123")
	testing.expect_value(t, parser_source(&parser), source)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)

	// Copies made while live remain invalid after the canonical owner retires.
	expect_invalid_parser_copy(t, &copied)
	expect_invalid_parser_copy(t, &copy_of_copy)
}

@(test)
test_parser_shallow_copy_cannot_touch_pending_numeric_owner :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	parser: Parser
	testing.expect(t, init_parser(
		&parser,
		diagnostic.borrow_source("<copy-pending>", "123"),
		test_allocator(&allocator_data),
	))
	allocator_data.short_at = 2
	allocator_data.free_failures_remaining = 1
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Resource_Failure)
	testing.expect(t, parser.pending_number_text != nil)
	live_before := len(tracker.allocation_map)
	copied := parser
	copy_of_copy := copied

	expect_invalid_parser_copy(t, &copied)
	expect_invalid_parser_copy(t, &copy_of_copy)
	testing.expect_value(t, len(tracker.allocation_map), live_before)
	testing.expect(t, parser.pending_number_text != nil)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	expect_invalid_parser_copy(t, &copied)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_parser_shallow_copy_cannot_interfere_with_cleanup_retry :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	allocator_data := Test_Allocator{
		backing = mem.tracking_allocator(&tracker),
		alive = true,
	}
	parser: Parser
	_, outcome := parse_test_filter(t, &parser, "123", test_allocator(&allocator_data))
	expect_parse_success(t, &parser, outcome)
	copied_before_cleanup := parser
	allocator_data.free_failures_remaining = 1
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, parser.state, Parser_State.Cleanup_Failed)
	copied_after_failure := parser
	live_before := len(tracker.allocation_map)

	expect_invalid_parser_copy(t, &copied_before_cleanup)
	expect_invalid_parser_copy(t, &copied_after_failure)
	testing.expect_value(t, len(tracker.allocation_map), live_before)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	expect_invalid_parser_copy(t, &copied_before_cleanup)
	expect_invalid_parser_copy(t, &copied_after_failure)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
test_parser_canonical_heap_address_and_preinit_move_are_supported :: proc(t: ^testing.T) {
	zero: Parser
	moved_before_init := zero
	source := diagnostic.borrow_source("<preinit-move>", "true")
	testing.expect(t, init_parser(&moved_before_init, source, context.allocator))
	outcome := parse_filter(&moved_before_init)
	expect_parse_success(t, &moved_before_init, outcome)
	testing.expect_value(t, destroy_parser(&moved_before_init), runtime.Allocator_Error.None)

	heap_parser, allocation_error := new(Parser)
	testing.expect_value(t, allocation_error, runtime.Allocator_Error.None)
	if allocation_error != nil {
		return
	}
	heap_source := diagnostic.borrow_source("<heap-parser>", "456")
	testing.expect(t, init_parser(heap_parser, heap_source, context.allocator))
	heap_copy := heap_parser^
	expect_invalid_parser_copy(t, &heap_copy)
	heap_outcome := parse_filter(heap_parser)
	expect_parse_success(t, heap_parser, heap_outcome)
	testing.expect_value(t, parser_nodes(heap_parser)[int(heap_outcome.root)].number_text, "456")
	testing.expect_value(t, destroy_parser(heap_parser), runtime.Allocator_Error.None)
	testing.expect_value(t, free(heap_parser), runtime.Allocator_Error.None)
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
	_, outcome := parse_test_filter(t, &parser, "(1)", test_allocator(&allocator_data))
	expect_parse_success(t, &parser, outcome)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.free_count, 5)

	allocator_data.alive = false
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, allocator_data.calls_after_retirement, 0)
	runtime.arena_destroy(&arena)
}

@(test)
test_atan_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<atan>", "atan")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Atan)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_tonumber_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<tonumber>", "tonumber")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Tonumber)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_toboolean_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<toboolean>", "toboolean")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Toboolean)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_min_max_parse_as_zero_argument_builtins :: proc(t: ^testing.T) {
	cases := [?]struct {text: string, expected: Node_Kind}{{"min", .Min}, {"max", .Max}}
	for test_case in cases {
		parser: Parser
		source := diagnostic.borrow_source("<min-max>", test_case.text)
		testing.expect(t, init_parser(&parser, source, context.allocator))
		outcome := parse_filter(&parser)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, root.kind, test_case.expected)
		testing.expect(t, !root.has_child && !root.has_value)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_ascii_case_parses_as_zero_argument_builtins :: proc(t: ^testing.T) {
	Case :: struct { text: string, expected: Node_Kind }
	cases := [?]Case{{"ascii_downcase", .Ascii_Downcase}, {"ascii_upcase", .Ascii_Upcase}}
	for test_case in cases {
		parser: Parser
		source := diagnostic.borrow_source("<ascii-case>", test_case.text)
		testing.expect(t, init_parser(&parser, source, context.allocator))
		outcome := parse_filter(&parser)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, root.kind, test_case.expected)
		testing.expect(t, !root.has_child && !root.has_value)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_reverse_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<reverse>", "reverse")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Reverse)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_implode_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<implode>", "implode")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Implode)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_explode_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<explode>", "explode")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Explode)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_keys_unsorted_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<keys_unsorted>", "keys_unsorted")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Keys_Unsorted)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_tostring_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<tostring>", "tostring")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Tostring)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_from_entries_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<from_entries>", "from_entries")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.From_Entries)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_to_entries_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<to_entries>", "to_entries")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.To_Entries)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_isnan_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<isnan>", "isnan")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Isnan)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_utf8bytelength_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<utf8bytelength>", "utf8bytelength")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Utf8bytelength)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_not_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<not>", "not")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Not_Builtin)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_empty_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<empty>", "empty")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Empty)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_values_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<values>", "values")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Values)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_arrays_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<arrays>", "arrays")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Arrays)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_objects_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<objects>", "objects")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Objects)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_iterables_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<iterables>", "iterables")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Iterables)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_scalars_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<scalars>", "scalars")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Scalars)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_booleans_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<booleans>", "booleans")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Booleans)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_nulls_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<nulls>", "nulls")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Nulls)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_numbers_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<numbers>", "numbers")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Numbers)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_strings_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<strings>", "strings")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Strings)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_finites_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<finites>", "finites")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Finites)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_normals_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<normals>", "normals")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Normals)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_floor_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<floor>", "floor")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Floor)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_round_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<round>", "round")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Round)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_transpose_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<transpose>", "transpose")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Transpose)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_unique_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<unique>", "unique")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Unique)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_sort_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<sort>", "sort")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Sort)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_nan_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<nan>", "nan")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Nan)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_infinite_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<infinite>", "infinite")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Infinite)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_ceil_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<ceil>", "ceil")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Ceil)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_isfinite_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<isfinite>", "isfinite")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Isfinite)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_flatten_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<flatten>", "flatten")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Flatten)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_any_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<any>", "any")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Any)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_all_parses_as_zero_argument_builtin :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<all>", "all")
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.All)
	testing.expect(t, !root.has_child && !root.has_value)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_join_literal_separator_parses_as_bounded_call :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<join>", `join("a")`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Join)
	testing.expect(t, root.has_child)
	argument := parser.nodes.storage[int(root.child)]
	testing.expect_value(t, argument.kind, Node_Kind.String)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_contains_literal_parses_as_bounded_call :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<contains>", `contains("a")`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Contains)
	testing.expect(t, root.has_child)
	argument := parser.nodes.storage[int(root.child)]
	testing.expect_value(t, argument.kind, Node_Kind.String)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_in_inside_scalar_literals_parse_as_bounded_calls :: proc(t: ^testing.T) {
	cases := [?]string{`inside("abc")`, `inside(null)`, `inside(true)`}
	for source_text in cases {
		parser: Parser
		source := diagnostic.borrow_source("<containment-scalar>", source_text)
		testing.expect(t, init_parser(&parser, source, context.allocator))
		outcome := parse_filter(&parser)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect(t, root.kind == Node_Kind.In || root.kind == Node_Kind.Inside)
		testing.expect(t, root.has_child)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
range_accepts_negative_one_argument_literal :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<range-negative>", `range(-2)`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_contains_scalar_literals_parse_as_bounded_calls :: proc(t: ^testing.T) {
	cases := [?]string{`contains(1)`, `contains(true)`, `contains(null)`}
	for source_text in cases {
		parser: Parser
		source := diagnostic.borrow_source("<contains-invalid>", source_text)
		testing.expect(t, init_parser(&parser, source, context.allocator))
		outcome := parse_filter(&parser)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
		testing.expect_value(t, parser.nodes.storage[int(outcome.root)].kind, Node_Kind.Contains)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_contains_array_literal_parses_as_bounded_call :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<contains-array>", `contains([2])`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Contains)
	testing.expect(t, root.has_child)
	argument := parser.nodes.storage[int(root.child)]
	testing.expect_value(t, argument.kind, Node_Kind.Identity)
	testing.expect_value(t, argument.container_kind, Container_Kind.Array)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_contains_object_literal_parses_as_bounded_call :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<contains-object>", `contains({"a":1})`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Contains)
	testing.expect(t, root.has_child)
	argument := parser.nodes.storage[int(root.child)]
	testing.expect_value(t, argument.kind, Node_Kind.Identity)
	testing.expect_value(t, argument.container_kind, Container_Kind.Object)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_prefix_suffix_literals_parse_as_bounded_calls :: proc(t: ^testing.T) {
	cases := [?]struct {source: string, kind: Node_Kind}{
		{`startswith("a")`, .Startswith},
		{`endswith("a")`, .Endswith},
	}
	for test_case in cases {
		parser: Parser
		source := diagnostic.borrow_source("<prefix-suffix>", test_case.source)
		testing.expect(t, init_parser(&parser, source, context.allocator))
		outcome := parse_filter(&parser)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, root.kind, test_case.kind)
		testing.expect(t, root.has_child)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_trimstr_literals_parse_as_bounded_calls :: proc(t: ^testing.T) {
	cases := [?]struct {source: string, kind: Node_Kind}{
		{`ltrimstr("a")`, .Ltrimstr},
		{`rtrimstr("a")`, .Rtrimstr},
		{`trimstr("a")`, .Trimstr},
	}
	for test_case in cases {
		parser: Parser
		source := diagnostic.borrow_source("<trimstr>", test_case.source)
		testing.expect(t, init_parser(&parser, source, context.allocator))
		outcome := parse_filter(&parser)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, root.kind, test_case.kind)
		testing.expect(t, root.has_child)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
test_split_literal_parses_as_bounded_call :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<split>", `split(", ")`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Split)
	testing.expect(t, root.has_child)
	argument := parser.nodes.storage[int(root.child)]
	testing.expect_value(t, argument.kind, Node_Kind.String)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
test_index_family_literal_parses_as_bounded_calls :: proc(t: ^testing.T) {
	cases := [?]struct {source: string, kind: Node_Kind}{
		{`index("a")`, .Index_Builtin},
		{`rindex("a")`, .Rindex_Builtin},
		{`indices("a")`, .Indices_Builtin},
	}
	for test_case in cases {
		parser: Parser
		source := diagnostic.borrow_source("<index-family>", test_case.source)
		testing.expect(t, init_parser(&parser, source, context.allocator))
		outcome := parse_filter(&parser)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, root.kind, test_case.kind)
		testing.expect(t, root.has_child)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
pipe_binds_only_the_right_hand_filter :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<binding-pipe>", `.[] | .[] as $x | [$x == .[]]`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Pipe)
	right := parser.nodes.storage[int(root.right)]
	testing.expect_value(t, right.kind, Node_Kind.Binding)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
iterator_fed_destructuring_patterns_parse :: proc(t: ^testing.T) {
	cases := [?]string{
		`.[] as [$a, $b] | [$a, $b]`,
		`.[] as {a:$a} | $a`,
	}
	for source_text in cases {
		parser: Parser
		source := diagnostic.borrow_source("<iterator-destructure>", source_text)
		testing.expect(t, init_parser(&parser, source, context.allocator))
		outcome := parse_filter(&parser)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
try_catch_stops_before_surrounding_binary :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<try-precedence>", `1 + try 2 catch 3 + 4`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.form, Node_Form.Binary)
	left := parser.nodes.storage[int(root.left)]
	testing.expect_value(t, left.form, Node_Form.Binary)
	try_node := parser.nodes.storage[int(left.right)]
	testing.expect_value(t, try_node.kind, Node_Kind.Try)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
try_catch_stops_before_surrounding_pipe :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<try-pipe-precedence>", `try ltrimstr("x") catch "x", try rtrimstr("x") catch "x" | "ok"`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Pipe)
	left := parser.nodes.storage[int(root.left)]
	testing.expect_value(t, left.kind, Node_Kind.Comma)
	first_try := parser.nodes.storage[int(left.left)]
	second_try := parser.nodes.storage[int(left.right)]
	testing.expect_value(t, first_try.kind, Node_Kind.Try)
	testing.expect_value(t, second_try.kind, Node_Kind.Try)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
map_argument_retains_try_and_optional_postfix_comma_stream :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source(
		"<optional-postfix-map>",
		`map(try .a[] catch ., try .a.[] catch ., .a[]?, .a.[]?)`,
	)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Map)
	testing.expect(t, root.has_child)
	testing.expect_value(t, parser.nodes.storage[int(root.child)].kind, Node_Kind.Comma)

	try_count, optional_count := 0, 0
	for node in parser.nodes.storage[:parser.nodes.count] {
		if node.kind == .Try do try_count += 1
		if node.kind == .Optional do optional_count += 1
	}
	testing.expect_value(t, try_count, 2)
	testing.expect_value(t, optional_count, 2)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
static_field_numeric_update_has_a_bounded_ast_node :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<static-field-update>", `.foo |= .+1`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Static_Field_Add_Number)
	testing.expect(t, root.has_name_span)
	start, end, span_ok := diagnostic.span_offsets(source, root.name_span)
	testing.expect(t, span_ok)
	testing.expect_value(t, string(diagnostic.source_bytes(source)[start:end]), "foo")
	number := parser.nodes.storage[int(root.right)]
	testing.expect_value(t, number.kind, Node_Kind.Number)
	testing.expect_value(t, number.number_text, "1")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
static_field_numeric_set_has_a_bounded_ast_node :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<static-field-set>", `.foo = 9`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Static_Field_Set_Number)
	number := parser.nodes.storage[int(root.right)]
	testing.expect_value(t, number.kind, Node_Kind.Number)
	testing.expect_value(t, number.number_text, "9")
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
error_accepts_scalar_literals :: proc(t: ^testing.T) {
	sources := [?]string{`error(0)`, `error(false)`, `error(null)`}
	for source_text in sources {
		parser: Parser
		source := diagnostic.borrow_source("<error-scalar>", source_text)
		testing.expect(t, init_parser(&parser, source, context.allocator))
		outcome := parse_filter(&parser)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
		root := parser.nodes.storage[int(outcome.root)]
		testing.expect_value(t, root.kind, Node_Kind.Error)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
isempty_accepts_literal_objects :: proc(t: ^testing.T) {
	sources := [?]string{`isempty({})`, `isempty({a:1})`}
	for source_text in sources {
		parser: Parser
		source := diagnostic.borrow_source("<isempty-object>", source_text)
		testing.expect(t, init_parser(&parser, source, context.allocator))
		outcome := parse_filter(&parser)
		testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
		testing.expect_value(t, parser.nodes.storage[int(outcome.root)].kind, Node_Kind.IsEmpty)
		testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
isempty_accepts_static_sequence :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<isempty-sequence>", `isempty(1,error("foo"))`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	testing.expect_value(t, parser.nodes.storage[int(outcome.root)].kind, Node_Kind.IsEmpty)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
foreach_parses_with_reduce_shape :: proc(t: ^testing.T) {
	parser: Parser
	source := diagnostic.borrow_source("<foreach>", `foreach .[] as $x (0; . + $x)`)
	testing.expect(t, init_parser(&parser, source, context.allocator))
	outcome := parse_filter(&parser)
	testing.expect_value(t, outcome.kind, Parse_Outcome_Kind.Success)
	root := parser.nodes.storage[int(outcome.root)]
	testing.expect_value(t, root.kind, Node_Kind.Foreach)
	testing.expect(t, root.has_reduce_update && root.has_name_span)
	testing.expect_value(t, destroy_parser(&parser), runtime.Allocator_Error.None)
}
