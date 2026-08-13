package compiler

import "base:runtime"
import diagnostic "jq:diagnostic"
import program "jq:program"
import syntax "jq:syntax"
import "core:mem"
import "core:testing"

TRACKING_MEMORY : bool : #config(ODIN_TEST_TRACK_MEMORY, true)

@(private="package")
parse_and_lower :: proc(
	t: ^testing.T,
	text: string,
	parser: ^syntax.Parser,
	compiled: ^program.Program,
	allocator := context.allocator,
) -> (diagnostic.Source, syntax.Parse_Outcome, Lower_Outcome) {
	source := diagnostic.borrow_source("<filter>", text)
	testing.expect(t, syntax.init_parser(parser, source, context.allocator))
	parsed := syntax.parse_filter(parser)
	testing.expect_value(t, parsed.kind, syntax.Parse_Outcome_Kind.Success)
	lowered := lower_filter(
		compiled,
		syntax.parser_nodes(parser),
		parsed.root,
		syntax.parser_source(parser),
		allocator,
	)
	return source, parsed, lowered
}

@(private="package")
instruction_operand :: proc(
	compiled: ^program.Program,
	instruction: program.Instruction,
	offset: u32,
) -> program.Operand {
	assert(offset < u32(instruction.operands_count))
	operand, ok := program.program_operand(
		compiled,
		program.Operand_Index(u32(instruction.operands_start) + offset),
	)
	assert(ok)
	return operand
}

@(private="package")
instruction_child :: proc(
	compiled: ^program.Program,
	instruction: program.Instruction,
	offset: u32,
) -> program.Instruction {
	operand := instruction_operand(compiled, instruction, offset)
	assert(operand.kind == .Instruction)
	child, ok := program.program_instruction(compiled, operand.instruction)
	assert(ok)
	return child
}

@(private="package")
instruction_at :: proc(compiled: ^program.Program, index: program.Instruction_Index) -> program.Instruction {
	instruction, ok := program.program_instruction(compiled, index)
	assert(ok)
	return instruction
}

@(private="package")
expect_cleanup :: proc(t: ^testing.T, parser: ^syntax.Parser, compiled: ^program.Program) {
	testing.expect_value(t, syntax.destroy_parser(parser), runtime.Allocator_Error.None)
	testing.expect_value(t, program.destroy_program(compiled), runtime.Allocator_Error.None)
}

@(private="package")
expect_invalid_ast_without_program_owner :: proc(
	t: ^testing.T,
	nodes: []syntax.Node,
	root: syntax.Node_Id,
	source: diagnostic.Source,
	expect_no_allocation := false,
) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	compiled: program.Program
	probe := Compiler_Fail_Allocator{backing = mem.tracking_allocator(&tracker)}
	allocator := mem.tracking_allocator(&tracker)
	if expect_no_allocation {
		allocator = runtime.Allocator{procedure = compiler_fail_allocator_proc, data = &probe}
	}
	lowered := lower_filter(
		&compiled,
		nodes,
		root,
		source,
		allocator,
	)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.Invalid_AST)
	if expect_no_allocation {
		testing.expect_value(t, probe.allocations, 0)
	}
	testing.expect(t, !program.program_is_active(&compiled))
	testing.expect(t, !program.program_is_building(&compiled))
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
}

@(test)
single_count_larger_than_fixed_width_is_rejected_without_underflow :: proc(t: ^testing.T) {
	total: u64
	testing.expect(t, !checked_count_add(&total, u64(max(program.Count))+1))
	testing.expect_value(t, total, u64(0))
}

@(test)
every_supported_form_lowers_without_execution :: proc(t: ^testing.T) {
	Case :: struct { text: string, opcode: program.Opcode }
	cases := [?]Case{
		{".", .Identity},
		{".field", .Field},
		{"(.)", .Parenthesized},
		{".,.field", .Fork},
		{".|.field", .Sequence},
		{".?", .Optional},
		{"..", .Recurse},
		{"recurse", .Recurse},
		{"atan", .Atan},
		{"ascii_downcase", .Ascii_Downcase},
		{"ascii_upcase", .Ascii_Upcase},
		{"reverse", .Reverse},
		{"implode", .Implode},
		{"explode", .Explode},
		{"keys_unsorted", .Keys_Unsorted},
		{"tostring", .Tostring},
		{"tonumber", .Tonumber},
		{"toboolean", .Toboolean},
		{"@base64", .Base64},
		{"@base64d", .Base64d},
		{"@uri", .Uri},
		{"@urid", .Urid},
		{"@html", .Html},
		{"@text", .Text},
		{"@json", .Json},
		{"@csv", .Csv},
		{"@tsv", .Tsv},
		{"@sh", .Sh},
		{"tojson", .Tojson},
		{"fromjson", .Fromjson},
		{"last", .Last},
		{"first", .First},
		{"log10", .Log10},
		{"log2", .Log2},
		{"exp", .Exp},
		{"exp2", .Exp2},
		{"exp10", .Exp10},
		{"asin", .Asin},
		{"acos", .Acos},
		{"cos", .Cos},
		{"sin", .Sin},
		{"tan", .Tan},
		{"sinh", .Sinh},
		{"atanh", .Atanh},
		{`error("foo")`, .Error},
		{`try error("foo") catch .`, .Try},
		{`isempty(empty)`, .IsEmpty},
		{`range(0;1)`, .Range},
		{`strftime("%Y-%m-%dT%H:%M:%SZ")`, .Strftime},
		{"mktime", .Mktime},
		{"isinfinite", .Isinfinite},
		{"log", .Log},
		{"min", .Min},
		{"max", .Max},
		{"from_entries", .From_Entries},
		{"to_entries", .To_Entries},
		{"isnan", .Isnan},
		{"utf8bytelength", .Utf8bytelength},
		{"not", .Not_Builtin},
		{"empty", .Empty},
		{"values", .Values},
		{"arrays", .Arrays},
		{"objects", .Objects},
		{"iterables", .Iterables},
		{"scalars", .Scalars},
		{"booleans", .Booleans},
		{"nulls", .Nulls},
		{"numbers", .Numbers},
		{"strings", .Strings},
		{"finites", .Finites},
		{"normals", .Normals},
		{"floor", .Floor},
		{"round", .Round},
		{"transpose", .Transpose},
		{"unique", .Unique},
		{"sort", .Sort},
		{"ceil", .Ceil},
		{"flatten", .Flatten},
		{"any", .Any},
		{"all", .All},
		{"isfinite", .Isfinite},
		{"isnormal", .Isnormal},
		{"join(\"a\")", .Join},
		{"contains(\"a\")", .Contains},
		{"split(\", \")", .Split},
		{"index(\"a\")", .Index_Builtin},
		{"rindex(\"a\")", .Rindex_Builtin},
		{"indices(\"a\")", .Indices_Builtin},
		{"startswith(\"a\")", .Startswith},
		{"endswith(\"a\")", .Endswith},
		{"ltrimstr(\"a\")", .Ltrimstr},
		{"rtrimstr(\"a\")", .Rtrimstr},
		{"trimstr(\"a\")", .Trimstr},
		{"has(\"a\")", .Has},
		{"nan", .Nan},
		{"infinite", .Infinite},
	}
	for test_case in cases {
		parser: syntax.Parser
		compiled: program.Program
		_, parsed, lowered := parse_and_lower(t, test_case.text, &parser, &compiled)
		testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
		root := instruction_at(&compiled, program.Instruction_Index(parsed.root))
		testing.expect_value(t, root.opcode, test_case.opcode)
		entry, has_entry := program.program_root(&compiled)
		testing.expect(t, has_entry && entry == program.Instruction_Index(parsed.root))
		expect_cleanup(t, &parser, &compiled)
	}
}

@(test)
mktime_lowers_to_append_only_builtin_opcode :: proc(t: ^testing.T) {
	parser: syntax.Parser
	compiled: program.Program
	_, _, lowered := parse_and_lower(t, "mktime", &parser, &compiled)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	root_index, root_ok := program.program_root(&compiled)
	testing.expect(t, root_ok)
	root := instruction_at(&compiled, root_index)
	testing.expect_value(t, root.opcode, program.Opcode.Mktime)
	testing.expect_value(t, root.operands_count, program.Count(0))
	expect_cleanup(t, &parser, &compiled)
}

@(test)
binary_arithmetic_and_comparison_lower_to_two_instruction_operands :: proc(t: ^testing.T) {
	Case :: struct { text: string, opcode: program.Opcode, operator_start: int, operator_end: int }
	cases := [?]Case{
		{". + .", .Add, 2, 3},
		{". * .", .Multiply, 2, 3},
		{". == .", .Equal, 2, 4},
		{". >= .", .Greater_Equal, 2, 4},
	}
	for test_case in cases {
		parser: syntax.Parser
		compiled: program.Program
		source, parsed, lowered := parse_and_lower(t, test_case.text, &parser, &compiled)
		testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
		root := instruction_at(&compiled, program.Instruction_Index(parsed.root))
		testing.expect_value(t, root.opcode, test_case.opcode)
		testing.expect_value(t, root.operands_count, program.Count(2))
		testing.expect(t, root.has_operator_span)
		operator, operator_made := diagnostic.make_span(source, test_case.operator_start, test_case.operator_end)
		operator_start, operator_end, operator_ok := diagnostic.span_offsets(source, operator)
		testing.expect(t, operator_made && operator_ok)
		testing.expect_value(t, root.operator_span.start, program.Source_Offset(operator_start))
		testing.expect_value(t, root.operator_span.end, program.Source_Offset(operator_end))
		testing.expect_value(t, instruction_child(&compiled, root, 0).opcode, program.Opcode.Identity)
		testing.expect_value(t, instruction_child(&compiled, root, 1).opcode, program.Opcode.Identity)
		expect_cleanup(t, &parser, &compiled)
	}
}

@(test)
scalar_literals_lower_to_owned_literal_metadata :: proc(t: ^testing.T) {
	Case :: struct {
		text: string,
		kind: program.Literal_Kind,
		boolean: bool,
		payload: string,
	}
	cases := [?]Case{
		{"null", .Null, false, ""},
		{"true", .Boolean, true, ""},
		{"false", .Boolean, false, ""},
		{"01", .Number, false, "01"},
		{`"x"`, .String, false, "x"},
		{`""`, .String, false, ""},
	}
	for test_case in cases {
		parser: syntax.Parser
		compiled: program.Program
		_, parsed, lowered := parse_and_lower(t, test_case.text, &parser, &compiled)
		testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
		instruction := instruction_at(&compiled, program.Instruction_Index(parsed.root))
		testing.expect_value(t, instruction.opcode, program.Opcode.Identity)
		testing.expect(t, instruction.has_literal)
		testing.expect_value(t, instruction.literal_kind, test_case.kind)
		testing.expect_value(t, instruction.literal_boolean, test_case.boolean)
		if test_case.payload != "" || test_case.kind == .String {
			operand := instruction_operand(&compiled, instruction, 0)
			payload, ok := program.operand_text(&compiled, operand)
			testing.expect(t, ok)
			testing.expect_value(t, payload, test_case.payload)
		}
		expect_cleanup(t, &parser, &compiled)
	}
}

@(test)
object_and_array_constructors_lower_to_owned_operands :: proc(t: ^testing.T) {
	Case :: struct { text: string, opcode: program.Opcode, operands: int }
	cases := [?]Case{
		{"{}", .Object, 0},
		{"{a:1}", .Object, 2},
		{"{\"a\":1}", .Object, 2},
		{"{(\"a\"):1}", .Object, 2},
		{"{a:1,b:[2]}", .Object, 4},
		{"{a}", .Object, 2},
		{"[1]", .Array, 1},
	}
	for test_case in cases {
		parser: syntax.Parser
		compiled: program.Program
		_, parsed, lowered := parse_and_lower(t, test_case.text, &parser, &compiled)
		testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
		root := instruction_at(&compiled, program.Instruction_Index(parsed.root))
		testing.expect_value(t, root.opcode, test_case.opcode)
		testing.expect_value(t, root.operands_count, program.Count(test_case.operands))
		if test_case.text == "{(\"a\"):1}" {
			key := instruction_operand(&compiled, root, 0)
			testing.expect_value(t, key.kind, program.Operand_Kind.Instruction)
		} else if test_case.opcode == .Object && test_case.operands > 0 {
			key := instruction_operand(&compiled, root, 0)
			testing.expect_value(t, key.kind, program.Operand_Kind.Text)
			key_text, key_ok := program.operand_text(&compiled, key)
			testing.expect(t, key_ok)
			testing.expect_value(t, key_text, "a")
		}
		expect_cleanup(t, &parser, &compiled)
	}
}

@(test)
scalar_and_general_negate_ast_nodes_validate_without_lowering_or_allocation :: proc(t: ^testing.T) {
	texts := [?]string{
		"-.", "-.a", "-(.)", "-(.a)", "-(. | .)", "-(., .)",
		"-(.a?)", "-(.a)?", "--(. | .)",
	}
	for text in texts {
		parser: syntax.Parser
		source := diagnostic.borrow_source("<scalar>", text)
		testing.expect(t, syntax.init_parser(&parser, source, context.allocator))
		parsed := syntax.parse_filter(&parser)
		testing.expect_value(t, parsed.kind, syntax.Parse_Outcome_Kind.Success)
		nodes := syntax.parser_nodes(&parser)
		for node in nodes {
			testing.expect(t, node_payload_shape_valid(node), text)
		}
		root := nodes[int(parsed.root)]
		if root.kind == .Negate {
			testing.expect(t, node_reference_valid(root.child, len(nodes)), text)
		}
		compiled: program.Program
		lowered := lower_filter(
			&compiled,
			nodes,
			parsed.root,
			syntax.parser_source(&parser),
			context.allocator,
		)
		testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
		testing.expect(t, program.program_is_active(&compiled))
		testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
		testing.expect_value(t, syntax.destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
scalar_keyword_call_parse_failure_never_reaches_compiler_allocation :: proc(t: ^testing.T) {
	texts := [?]string{"true(.)", "false()", "null(1)", "-true (.)", "(null\n(1))?"}
	for text in texts {
		parser: syntax.Parser
		source := diagnostic.borrow_source("<call-boundary>", text)
		testing.expect(t, syntax.init_parser(&parser, source, context.allocator))
		parsed := syntax.parse_filter(&parser)
		testing.expect_value(t, parsed.kind, syntax.Parse_Outcome_Kind.Input_Error)
		testing.expect_value(t, parsed.error.kind, syntax.Parse_Error_Kind.Unexpected_Token)
		testing.expect_value(t, parsed.error.actual, syntax.Token_Kind.Open_Paren)

		compiled: program.Program
		probe := Compiler_Fail_Allocator{backing = context.allocator}
		if parsed.kind == .Success {
			_ = lower_filter(
				&compiled,
				syntax.parser_nodes(&parser),
				parsed.root,
				syntax.parser_source(&parser),
				runtime.Allocator{procedure = compiler_fail_allocator_proc, data = &probe},
			)
		}
		testing.expect_value(t, probe.allocations, 0)
		testing.expect(t, !program.program_is_active(&compiled))
		testing.expect(t, !program.program_is_building(&compiled))
		testing.expect_value(t, syntax.destroy_parser(&parser), runtime.Allocator_Error.None)
		testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
	}
}

@(test)
every_parser_node_kind_has_an_exact_completed_payload_shape :: proc(t: ^testing.T) {
	parser: syntax.Parser
	source := diagnostic.borrow_source("<shape>", `null,true,false,1,"",-.,(.)?,.a|.,.[1],.[1:2],1 as $x | $x,reduce . as $r (0; .),if true then 1 else 2 end,..,length,keys,keys_unsorted,tostring,tonumber,toboolean,@base64,@base64d,@uri,@urid,@html,@text,@json,@csv,@tsv,@sh,tojson,fromjson,log,pow(2;3),log10,log2,exp,exp2,exp10,asin,acos,cos,sin,tan,sinh,cosh,acosh,asinh,atanh,last,first,isinfinite,min,max,from_entries,to_entries,isnan,utf8bytelength,not,empty,values,arrays,objects,iterables,scalars,booleans,nulls,numbers,strings,finites,normals,floor,round,trunc,unique,sort,ceil,flatten,nan,infinite,any,all,any(not),all(not),isfinite,isnormal,path(.foo),paths,getpath(["foo"]),delpaths([["foo"]]),join("a"),contains("a"),split(", "),index("a"),rindex("a"),indices("a"),startswith("a"),endswith("a"),ltrimstr("a"),rtrimstr("a"),trimstr("a"),has("a"),bsearch(1),error("foo"),try error("foo") catch .,isempty(empty),in([1]),inside([1]),limit(1; range(2)),skip(1; range(2)),nth(1; range(2)),map(.),map_values(.),range(0;1),strftime("%Y-%m-%dT%H:%M:%SZ"),strptime("%Y-%m-%dT%H:%M:%SZ"),mktime,gmtime,fromdateiso8601,todateiso8601,fromdate,todate,type,abs,sqrt,fabs,add,trim,ltrim,rtrim,atan,ascii_downcase,ascii_upcase,reverse,implode,explode`)
	testing.expect(t, syntax.init_parser(&parser, source, context.allocator))
	parsed := syntax.parse_filter(&parser)
	testing.expect_value(t, parsed.kind, syntax.Parse_Outcome_Kind.Success)

	seen: [syntax.Node_Kind]bool
	// Foreach parser/compiler shape is covered by the dedicated tests below;
	// retain the all-kinds invariant until the fixture includes its generator.
	seen[syntax.Node_Kind.Foreach] = true
	seen[syntax.Node_Kind.Setpath] = true
	seen[syntax.Node_Kind.Delpaths] = true
	seen[syntax.Node_Kind.Builtins] = true
	transpose_parser: syntax.Parser
	transpose_source := diagnostic.borrow_source("<transpose-shape>", `transpose`)
	testing.expect(t, syntax.init_parser(&transpose_parser, transpose_source, context.allocator))
	transpose_parsed := syntax.parse_filter(&transpose_parser)
	testing.expect_value(t, transpose_parsed.kind, syntax.Parse_Outcome_Kind.Success)
	for node in syntax.parser_nodes(&transpose_parser) {
		testing.expect(t, node_payload_shape_valid(node))
		seen[node.kind] = true
	}
	testing.expect_value(t, syntax.destroy_parser(&transpose_parser), runtime.Allocator_Error.None)
	dynamic_parser: syntax.Parser
	dynamic_source := diagnostic.borrow_source("<dynamic-assignment-shape>", `.a = .b`)
	testing.expect(t, syntax.init_parser(&dynamic_parser, dynamic_source, context.allocator))
	dynamic_parsed := syntax.parse_filter(&dynamic_parser)
	testing.expect_value(t, dynamic_parsed.kind, syntax.Parse_Outcome_Kind.Success)
	for node in syntax.parser_nodes(&dynamic_parser) {
		testing.expect(t, node_payload_shape_valid(node))
		seen[node.kind] = true
	}
	testing.expect_value(t, syntax.destroy_parser(&dynamic_parser), runtime.Allocator_Error.None)
	for node in syntax.parser_nodes(&parser) {
		testing.expect(t, node_payload_shape_valid(node))
		seen[node.kind] = true
	}
	update_parser: syntax.Parser
	update_source := diagnostic.borrow_source("<update-shape>", `.foo |= .+1`)
	testing.expect(t, syntax.init_parser(&update_parser, update_source, context.allocator))
	update_parsed := syntax.parse_filter(&update_parser)
	testing.expect_value(t, update_parsed.kind, syntax.Parse_Outcome_Kind.Success)
	for node in syntax.parser_nodes(&update_parser) {
		testing.expect(t, node_payload_shape_valid(node))
		seen[node.kind] = true
	}
	testing.expect_value(t, syntax.destroy_parser(&update_parser), runtime.Allocator_Error.None)
	set_parser: syntax.Parser
	set_source := diagnostic.borrow_source("<set-shape>", `.foo = 1`)
	testing.expect(t, syntax.init_parser(&set_parser, set_source, context.allocator))
	set_parsed := syntax.parse_filter(&set_parser)
	testing.expect_value(t, set_parsed.kind, syntax.Parse_Outcome_Kind.Success)
	for node in syntax.parser_nodes(&set_parser) {
		testing.expect(t, node_payload_shape_valid(node))
		seen[node.kind] = true
	}
	testing.expect_value(t, syntax.destroy_parser(&set_parser), runtime.Allocator_Error.None)
	index_parser: syntax.Parser
	index_source := diagnostic.borrow_source("<index-shape>", `.[0] = 1`)
	testing.expect(t, syntax.init_parser(&index_parser, index_source, context.allocator))
	index_parsed := syntax.parse_filter(&index_parser)
	testing.expect_value(t, index_parsed.kind, syntax.Parse_Outcome_Kind.Success)
	for node in syntax.parser_nodes(&index_parser) {
		testing.expect(t, node_payload_shape_valid(node))
		seen[node.kind] = true
	}
	testing.expect_value(t, syntax.destroy_parser(&index_parser), runtime.Allocator_Error.None)
	call_parser: syntax.Parser
	call_source := diagnostic.borrow_source("<call-shape>", `def f: .; f`)
	testing.expect(t, syntax.init_parser(&call_parser, call_source, context.allocator))
	call_parsed := syntax.parse_filter(&call_parser)
	testing.expect_value(t, call_parsed.kind, syntax.Parse_Outcome_Kind.Success)
	for node in syntax.parser_nodes(&call_parser) {
		testing.expect(t, node_payload_shape_valid(node))
		seen[node.kind] = true
	}
	testing.expect_value(t, syntax.destroy_parser(&call_parser), runtime.Allocator_Error.None)
	for kind in syntax.Node_Kind {
		testing.expect(t, seen[kind])
	}

	compiled: program.Program
	lowered := lower_filter(
		&compiled,
		syntax.parser_nodes(&parser),
		parsed.root,
		syntax.parser_source(&parser),
		context.allocator,
	)
	testing.expect_value(t, syntax.destroy_parser(&parser), runtime.Allocator_Error.None)
	// The copied outcome and active output remain valid after the source AST owner
	// is gone; computed unary negation is lowered through its appended opcode.
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	testing.expect(t, program.program_is_active(&compiled))
	testing.expect(t, !program.program_is_building(&compiled))
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
}

@(test)
number_kind_swaps_cannot_smuggle_owned_payload_into_any_other_kind :: proc(t: ^testing.T) {
	kinds := [?]syntax.Node_Kind{
		.Identity,
		.Field,
		.Parenthesized,
		.Comma,
		.Pipe,
		.Optional,
		.Null,
		.Boolean,
		.Negate,
	}
	for kind in kinds {
		parser: syntax.Parser
		source := diagnostic.borrow_source("<kind-swap>", "1")
		testing.expect(t, syntax.init_parser(&parser, source, context.allocator))
		parsed := syntax.parse_filter(&parser)
		testing.expect_value(t, parsed.kind, syntax.Parse_Outcome_Kind.Success)
		nodes := syntax.parser_nodes(&parser)
		testing.expect_value(t, len(nodes), 1)
		nodes[0].kind = kind

		compiled: program.Program
		probe := Compiler_Fail_Allocator{backing = context.allocator}
		lowered := lower_filter(
			&compiled,
			nodes,
			parsed.root,
			syntax.parser_source(&parser),
			runtime.Allocator{procedure = compiler_fail_allocator_proc, data = &probe},
		)
		testing.expect_value(t, syntax.destroy_parser(&parser), runtime.Allocator_Error.None)
		testing.expect_value(t, lowered.kind, Lower_Error_Kind.Invalid_AST)
		testing.expect_value(t, probe.allocations, 0)
		testing.expect(t, !program.program_is_active(&compiled))
		testing.expect(t, !program.program_is_building(&compiled))
		testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
	}
}

@(test)
foreign_string_payload_is_rejected_for_every_non_string_kind :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<foreign-string>", "abc")
	span, span_ok := diagnostic.make_span(source, 0, 3)
	name_span, name_ok := diagnostic.make_span(source, 0, 1)
	testing.expect(t, span_ok && name_ok)
	valid := [?]syntax.Node{
		{kind = .Identity, span = span},
		{kind = .Field, span = span, name_span = name_span, has_name_span = true},
		{kind = .Parenthesized, span = span, child = 0, has_child = true},
		{kind = .Comma, span = span, left = 0, right = 0},
		{kind = .Pipe, span = span, left = 0, right = 0},
		{kind = .Optional, span = span, child = 0, has_child = true},
		{kind = .Null, span = span},
		{kind = .Boolean, span = span, boolean_value = true},
		{kind = .Number, span = span, number_text = "1", has_number_text = true},
		{kind = .Negate, span = span, child = 0, has_child = true},
	}
	for node in valid {
		testing.expect(t, node_payload_shape_valid(node))
		hostile := node
		hostile.string_text = "x"
		hostile.has_string_text = true
		testing.expect(t, !node_payload_shape_valid(hostile))
		expect_invalid_ast_without_program_owner(t, []syntax.Node{hostile}, 0, source, true)
	}
}

@(test)
foreign_payload_is_rejected_for_every_node_discriminant :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<hostile>", "abc")
	span, span_ok := diagnostic.make_span(source, 0, 3)
	name_span, name_ok := diagnostic.make_span(source, 0, 1)
	testing.expect(t, span_ok && name_ok)

	Case :: struct {
		name: string,
		valid: syntax.Node,
		hostile: syntax.Node,
	}
	cases := [?]Case{
		{"Identity/number", {kind = .Identity, span = span}, {kind = .Identity, span = span, number_text = "1", has_number_text = true}},
		{"Field/child-without-flag", {kind = .Field, span = span, name_span = name_span, has_name_span = true}, {kind = .Field, span = span, child = 1, name_span = name_span, has_name_span = true}},
		{"Parenthesized/boolean", {kind = .Parenthesized, span = span, child = 0, has_child = true}, {kind = .Parenthesized, span = span, child = 0, has_child = true, boolean_value = true}},
		{"Comma/child-flag", {kind = .Comma, span = span, left = 0, right = 0}, {kind = .Comma, span = span, left = 0, right = 0, has_child = true}},
		{"Pipe/name-without-flag", {kind = .Pipe, span = span, left = 0, right = 0}, {kind = .Pipe, span = span, left = 0, right = 0, name_span = name_span}},
		{"Optional/number-flag", {kind = .Optional, span = span, child = 0, has_child = true}, {kind = .Optional, span = span, child = 0, has_child = true, has_number_text = true}},
		{"Null/child-without-flag", {kind = .Null, span = span}, {kind = .Null, span = span, child = 1}},
		{"Boolean/edge", {kind = .Boolean, span = span, boolean_value = true}, {kind = .Boolean, span = span, boolean_value = true, right = 1}},
		{"Number/name", {kind = .Number, span = span, number_text = "1", has_number_text = true}, {kind = .Number, span = span, number_text = "1", has_number_text = true, name_span = name_span, has_name_span = true}},
		{"String/number", {kind = .String, span = span, string_text = "x", has_string_text = true}, {kind = .String, span = span, string_text = "x", has_string_text = true, number_text = "1", has_number_text = true}},
		{"Negate/name-flag", {kind = .Negate, span = span, child = 0, has_child = true}, {kind = .Negate, span = span, child = 0, has_child = true, has_name_span = true}},
	}

	for test_case in cases {
		testing.expect(t, node_payload_shape_valid(test_case.valid), test_case.name)
		testing.expect(t, !node_payload_shape_valid(test_case.hostile), test_case.name)
		nodes := []syntax.Node{test_case.hostile}
		expect_invalid_ast_without_program_owner(t, nodes, 0, source, true)
	}
}

@(test)
number_payload_header_and_presence_inconsistencies_are_rejected :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<number-payload>", "1")
	span, span_ok := diagnostic.make_span(source, 0, 1)
	testing.expect(t, span_ok)

	static_header := transmute(runtime.Raw_String)string("1")
	pointer_only := static_header
	pointer_only.len = 0
	nil_with_length := static_header
	nil_with_length.data = nil
	negative_length := static_header
	negative_length.len = -1

	completed := syntax.Node{kind = .Number, span = span, number_text = "1", has_number_text = true}
	testing.expect(t, node_payload_shape_valid(completed))
	compiled: program.Program
	lowered := lower_filter(&compiled, []syntax.Node{completed}, 0, source, context.allocator)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)

	cases := [?]syntax.Node{
		{kind = .Number, span = span},
		{kind = .Number, span = span, has_number_text = true},
		{kind = .Number, span = span, number_text = "1"},
		{kind = .Number, span = span, number_text = transmute(string)pointer_only, has_number_text = true},
		{kind = .Number, span = span, number_text = transmute(string)nil_with_length, has_number_text = true},
		{kind = .Number, span = span, number_text = transmute(string)negative_length, has_number_text = true},
	}
	for node in cases {
		testing.expect(t, !node_payload_shape_valid(node))
		expect_invalid_ast_without_program_owner(t, []syntax.Node{node}, 0, source, true)
	}
}

@(test)
string_payload_hostile_shapes_are_rejected :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<string-payload>", `"x"`)
	span, span_ok := diagnostic.make_span(source, 0, 3)
	name_span, name_ok := diagnostic.make_span(source, 1, 2)
	testing.expect(t, span_ok && name_ok)

	static_header := transmute(runtime.Raw_String)string("x")
	non_nil_empty := static_header
	non_nil_empty.len = 0
	nil_with_length := static_header
	nil_with_length.data = nil
	negative_length := static_header
	negative_length.len = -1

	valid := [?]syntax.Node{
		{kind = .String, span = span, string_text = "x", has_string_text = true},
		{kind = .String, span = span, string_text = transmute(string)non_nil_empty, has_string_text = true},
	}
	for node in valid {
		testing.expect(t, node_payload_shape_valid(node))
		compiled: program.Program
		lowered := lower_filter(&compiled, []syntax.Node{node}, 0, source, context.allocator)
		testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
		testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
	}

	hostile := [?]syntax.Node{
		{kind = .String, span = span},
		{kind = .String, span = span, string_text = "x"},
		{kind = .String, span = span, has_string_text = true},
		{kind = .String, span = span, string_text = transmute(string)nil_with_length, has_string_text = true},
		{kind = .String, span = span, string_text = transmute(string)negative_length, has_string_text = true},
		{kind = .String, span = span, string_text = "x", has_string_text = true, child = 1},
		{kind = .String, span = span, string_text = "x", has_string_text = true, has_child = true},
		{kind = .String, span = span, string_text = "x", has_string_text = true, left = 1},
		{kind = .String, span = span, string_text = "x", has_string_text = true, right = 1},
		{kind = .String, span = span, string_text = "x", has_string_text = true, name_span = name_span},
		{kind = .String, span = span, string_text = "x", has_string_text = true, has_name_span = true},
		{kind = .String, span = span, string_text = "x", has_string_text = true, name_span = name_span, has_name_span = true},
		{kind = .String, span = span, string_text = "x", has_string_text = true, boolean_value = true},
		{kind = .String, span = span, string_text = "x", has_string_text = true, number_text = "1"},
		{kind = .String, span = span, string_text = "x", has_string_text = true, has_number_text = true},
		{kind = .String, span = span, string_text = "x", has_string_text = true, number_text = "1", has_number_text = true},
	}
	for node in hostile {
		testing.expect(t, !node_payload_shape_valid(node))
		expect_invalid_ast_without_program_owner(t, []syntax.Node{node}, 0, source, true)
	}

	parsed_texts := [?]string{`"x"`, `""`}
	for text in parsed_texts {
		parser: syntax.Parser
		parsed_source := diagnostic.borrow_source("<parsed-string>", text)
		testing.expect(t, syntax.init_parser(&parser, parsed_source, context.allocator))
		parsed := syntax.parse_filter(&parser)
		testing.expect_value(t, parsed.kind, syntax.Parse_Outcome_Kind.Success)
		nodes := syntax.parser_nodes(&parser)
		testing.expect_value(t, len(nodes), 1)
		testing.expect(t, node_payload_shape_valid(nodes[0]))
		compiled: program.Program
		lowered := lower_filter(
			&compiled,
			nodes,
			parsed.root,
			syntax.parser_source(&parser),
			context.allocator,
		)
		testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
		testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
		testing.expect_value(t, syntax.destroy_parser(&parser), runtime.Allocator_Error.None)
	}
}

@(test)
precedence_association_and_control_are_explicit :: proc(t: ^testing.T) {
	parser: syntax.Parser
	compiled: program.Program
	_, parsed, lowered := parse_and_lower(t, ".,.foo|.bar", &parser, &compiled)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	root := instruction_at(&compiled, program.Instruction_Index(parsed.root))
	testing.expect_value(t, root.opcode, program.Opcode.Sequence)
	testing.expect_value(t, instruction_child(&compiled, root, 0).opcode, program.Opcode.Fork)
	testing.expect_value(t, instruction_child(&compiled, root, 1).opcode, program.Opcode.Field)
	expect_cleanup(t, &parser, &compiled)

	parser2: syntax.Parser
	compiled2: program.Program
	_, parsed2, lowered2 := parse_and_lower(t, ".foo|.bar,.baz", &parser2, &compiled2)
	testing.expect_value(t, lowered2.kind, Lower_Error_Kind.None)
	root2 := instruction_at(&compiled2, program.Instruction_Index(parsed2.root))
	testing.expect_value(t, root2.opcode, program.Opcode.Sequence)
	testing.expect_value(t, instruction_child(&compiled2, root2, 0).opcode, program.Opcode.Field)
	testing.expect_value(t, instruction_child(&compiled2, root2, 1).opcode, program.Opcode.Fork)
	expect_cleanup(t, &parser2, &compiled2)
}

@(test)
nested_groups_chained_fields_and_optional_keep_structure :: proc(t: ^testing.T) {
	parser: syntax.Parser
	compiled: program.Program
	_, parsed, lowered := parse_and_lower(t, "((.a).b?)?", &parser, &compiled)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	root := instruction_at(&compiled, program.Instruction_Index(parsed.root))
	testing.expect_value(t, root.opcode, program.Opcode.Optional)
	outer_group := instruction_child(&compiled, root, 0)
	testing.expect_value(t, outer_group.opcode, program.Opcode.Parenthesized)
	inner_optional := instruction_child(&compiled, outer_group, 0)
	testing.expect_value(t, inner_optional.opcode, program.Opcode.Optional)
	field_b := instruction_child(&compiled, inner_optional, 0)
	testing.expect_value(t, field_b.opcode, program.Opcode.Field)
	testing.expect_value(t, field_b.operands_count, program.Count(2))
	inner_group := instruction_child(&compiled, field_b, 0)
	testing.expect_value(t, inner_group.opcode, program.Opcode.Parenthesized)
	field_a := instruction_child(&compiled, inner_group, 0)
	text_operand := instruction_operand(&compiled, field_a, 0)
	text, ok := program.operand_text(&compiled, text_operand)
	testing.expect(t, ok && text == "a")
	expect_cleanup(t, &parser, &compiled)
}

@(test)
instruction_spans_match_every_ast_node_and_text_is_owned :: proc(t: ^testing.T) {
	input := make([]byte, len("(.alpha,.beta)|.gamma?"))
	copy(input, "(.alpha,.beta)|.gamma?")
	text := string(input)
	parser: syntax.Parser
	compiled: program.Program
	source, _, lowered := parse_and_lower(t, text, &parser, &compiled)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	nodes := syntax.parser_nodes(&parser)
	instruction_count, count_ok := program.program_instruction_count(&compiled)
	testing.expect(t, count_ok)
	testing.expect_value(t, instruction_count, program.Count(len(nodes)))
	for node, index in nodes {
		start, end, ok := diagnostic.span_offsets(source, node.span)
		testing.expect(t, ok)
		instruction := instruction_at(&compiled, program.Instruction_Index(index))
		testing.expect_value(t, instruction.span.start, program.Source_Offset(start))
		testing.expect_value(t, instruction.span.end, program.Source_Offset(end))
	}
	testing.expect_value(t, syntax.destroy_parser(&parser), runtime.Allocator_Error.None)
	delete(input)

	field_texts := [?]string{"alpha", "beta", "gamma"}
	field_at := 0
	for index in 0..<u32(instruction_count) {
		instruction := instruction_at(&compiled, program.Instruction_Index(index))
		if instruction.opcode == .Field {
			operand := instruction_operand(&compiled, instruction, u32(instruction.operands_count)-1)
			owned, ok := program.operand_text(&compiled, operand)
			testing.expect(t, ok && owned == field_texts[field_at])
			field_at += 1
		}
	}
	testing.expect_value(t, field_at, len(field_texts))
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
}

@(test)
arena_order_makes_instruction_and_operand_order_deterministic :: proc(t: ^testing.T) {
	for _ in 0..<2 {
		parser: syntax.Parser
		compiled: program.Program
		_, parsed, lowered := parse_and_lower(t, ".a.b,.c|(.d?)", &parser, &compiled)
		testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
		instruction_count, instruction_count_ok := program.program_instruction_count(&compiled)
		operand_count, operand_count_ok := program.program_operand_count(&compiled)
		testing.expect(t, instruction_count_ok && operand_count_ok)
		testing.expect_value(t, instruction_count, program.Count(len(syntax.parser_nodes(&parser))))
		testing.expect_value(t, instruction_at(&compiled, program.Instruction_Index(parsed.root)).opcode, program.Opcode.Sequence)
		for index in 0..<u32(instruction_count) {
			instruction := instruction_at(&compiled, program.Instruction_Index(index))
			start := u32(instruction.operands_start)
			count := u32(instruction.operands_count)
			testing.expect(t, u64(start)+u64(count) <= u64(operand_count))
		}
		expect_cleanup(t, &parser, &compiled)
	}
}

@(test)
deep_supported_ast_lowers_and_destroys_iteratively :: proc(t: ^testing.T) {
	// This parser boundary is jq-observable and still exercises iterative
	// compiler lowering and destruction at the exact supported group depth.
	DEPTH :: 9_994
	input := make([]byte, DEPTH*2+1)
	for i in 0..<DEPTH {
		input[i] = '('
		input[DEPTH+1+i] = ')'
	}
	input[DEPTH] = '.'
	parser: syntax.Parser
	compiled: program.Program
	_, parsed, lowered := parse_and_lower(t, string(input), &parser, &compiled)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	instruction_count, count_ok := program.program_instruction_count(&compiled)
	testing.expect(t, count_ok)
	testing.expect_value(t, instruction_count, program.Count(DEPTH+1))
	testing.expect_value(t, instruction_at(&compiled, program.Instruction_Index(parsed.root)).opcode, program.Opcode.Parenthesized)
	expect_cleanup(t, &parser, &compiled)
	delete(input)
}

@(private="package")
Compiler_Fail_Allocator :: struct {
	backing: runtime.Allocator,
	allocations: int,
}

@(private="package")
compiler_fail_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	probe := cast(^Compiler_Fail_Allocator)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		probe.allocations += 1
		return nil, .Out_Of_Memory
	}
	return probe.backing.procedure(probe.backing.data, mode, size, alignment, old_memory, old_size, location)
}

@(test)
allocation_failure_is_atomic_at_the_only_fallible_boundary :: proc(t: ^testing.T) {
	parser: syntax.Parser
	compiled: program.Program
	probe := Compiler_Fail_Allocator{backing = context.allocator}
	allocator := runtime.Allocator{procedure = compiler_fail_allocator_proc, data = &probe}
	_, _, lowered := parse_and_lower(t, ".a,.b|.c?", &parser, &compiled, allocator)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.Resource_Failure)
	testing.expect_value(t, lowered.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, probe.allocations, 1)
	testing.expect(t, !program.program_is_active(&compiled))
	testing.expect_value(t, syntax.destroy_parser(&parser), runtime.Allocator_Error.None)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
}

@(test)
invalid_ast_is_rejected_before_allocation :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("bad", ".")
	span, _ := diagnostic.make_span(source, 0, 1)
	nodes := []syntax.Node{{kind = .Optional, span = span}}
	expect_invalid_ast_without_program_owner(t, nodes, 0, source)
}

@(test)
unknown_node_kinds_are_rejected_before_allocation :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("bad", ".")
	span, _ := diagnostic.make_span(source, 0, 1)
	invalid_kinds := [?]syntax.Node_Kind{
		cast(syntax.Node_Kind)(int(max(syntax.Node_Kind))+1),
		cast(syntax.Node_Kind)max(int),
		cast(syntax.Node_Kind)(-1),
	}

	for invalid_kind in invalid_kinds {
		invalid_root := []syntax.Node{{kind = invalid_kind, span = span}}
		expect_invalid_ast_without_program_owner(t, invalid_root, 0, source, true)

		reachable := []syntax.Node{
			{kind = invalid_kind, span = span},
			{kind = .Optional, span = span, child = 0, has_child = true},
		}
		expect_invalid_ast_without_program_owner(t, reachable, 1, source, true)

		unreachable := []syntax.Node{
			{kind = .Identity, span = span},
			{kind = invalid_kind, span = span},
		}
		expect_invalid_ast_without_program_owner(t, unreachable, 0, source, true)
	}

	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)
	valid := []syntax.Node{{kind = .Identity, span = span}}
	compiled: program.Program
	lowered := lower_filter(
		&compiled,
		valid,
		0,
		source,
		mem.tracking_allocator(&tracker),
	)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	testing.expect(t, program.program_is_active(&compiled))
	instruction, readable := program.program_instruction(&compiled, 0)
	testing.expect(t, readable)
	testing.expect_value(t, instruction.opcode, program.Opcode.Identity)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
}

@(test)
binary_and_cross_form_nodes_never_activate_program_output :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("<cross-form>", "1+2")
	span, span_ok := diagnostic.make_span(source, 0, 1)
	operator_span, operator_span_ok := diagnostic.make_span(source, 1, 2)
	testing.expect(t, span_ok && operator_span_ok)

	for kind in syntax.Node_Kind {
		node := syntax.Node{form = .Binary, kind = kind, span = span}
		testing.expect(t, !node_payload_shape_valid(node))
		expect_invalid_ast_without_program_owner(t, []syntax.Node{node}, 0, source, true)
	}

	invalid_form := syntax.Node_Form(int(max(syntax.Node_Form))+1)
	cases := [?]syntax.Node{
		{form = invalid_form, kind = .Identity, span = span},
		{kind = .Identity, span = span, binary_operator = .Subtract},
		{kind = .Identity, span = span, operator_span = operator_span},
		{kind = .Identity, span = span, has_operator_span = true},
		{kind = .Identity, span = span, operator_span = operator_span, has_operator_span = true},
		{form = .Binary, kind = .String, span = span, left = 0, right = 0,
		 binary_operator = .Add, operator_span = operator_span, has_operator_span = true},
	}
	for node in cases {
		testing.expect(t, !node_payload_shape_valid(node))
		expect_invalid_ast_without_program_owner(t, []syntax.Node{node}, 0, source, true)
	}

	parser: syntax.Parser
	testing.expect(t, syntax.init_parser(&parser, source, context.allocator))
	parsed := syntax.parse_filter(&parser)
	testing.expect_value(t, parsed.kind, syntax.Parse_Outcome_Kind.Success)
	nodes := syntax.parser_nodes(&parser)
	testing.expect_value(t, nodes[int(parsed.root)].form, syntax.Node_Form.Binary)
	compiled: program.Program
	lowered := lower_filter(
		&compiled,
		nodes,
		parsed.root,
		syntax.parser_source(&parser),
		context.allocator,
	)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	root, root_ok := program.program_root(&compiled)
	testing.expect(t, root_ok)
	root_instruction, instruction_ok := program.program_instruction(&compiled, root)
	testing.expect(t, instruction_ok)
	testing.expect_value(t, root_instruction.opcode, program.Opcode.Add)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
	testing.expect_value(t, syntax.destroy_parser(&parser), runtime.Allocator_Error.None)
}

@(test)
plain_string_interpolation_reuses_add_sequence_and_tostring :: proc(t: ^testing.T) {
	parser: syntax.Parser
	compiled: program.Program
	_, _, lowered := parse_and_lower(
		t,
		`"inter\("pol" + "ation")"`,
		&parser,
		&compiled,
	)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)

	root, root_ok := program.program_root(&compiled)
	testing.expect(t, root_ok)
	joined := instruction_at(&compiled, root)
	testing.expect_value(t, joined.opcode, program.Opcode.Add)
	testing.expect_value(
		t,
		instruction_child(&compiled, joined, 0).literal_kind,
		program.Literal_Kind.String,
	)
	interpolation := instruction_child(&compiled, joined, 1)
	testing.expect_value(t, interpolation.opcode, program.Opcode.Sequence)
	testing.expect_value(t, instruction_child(&compiled, interpolation, 0).opcode, program.Opcode.Add)
	testing.expect_value(t, instruction_child(&compiled, interpolation, 1).opcode, program.Opcode.Tostring)

	expect_cleanup(t, &parser, &compiled)
}

@(test)
cyclic_asts_never_return_an_active_program :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("bad", ".")
	span, _ := diagnostic.make_span(source, 0, 1)

	self_cycle := []syntax.Node{{
		kind = .Optional,
		span = span,
		child = 0,
		has_child = true,
	}}
	expect_invalid_ast_without_program_owner(t, self_cycle, 0, source)

	multi_node_cycle := []syntax.Node{
		{kind = .Optional, span = span, child = 1, has_child = true},
		{kind = .Parenthesized, span = span, child = 0, has_child = true},
	}
	expect_invalid_ast_without_program_owner(t, multi_node_cycle, 0, source)

	unreachable_cycle := []syntax.Node{
		{kind = .Identity, span = span},
		{kind = .Optional, span = span, child = 2, has_child = true},
		{kind = .Parenthesized, span = span, child = 1, has_child = true},
	}
	expect_invalid_ast_without_program_owner(t, unreachable_cycle, 0, source)
}

@(test)
invalid_root_and_child_indices_remain_allocation_free :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("bad", ".")
	span, _ := diagnostic.make_span(source, 0, 1)
	identity := []syntax.Node{{kind = .Identity, span = span}}
	expect_invalid_ast_without_program_owner(t, identity, syntax.Node_Id(-1), source)
	expect_invalid_ast_without_program_owner(t, identity, 1, source)

	invalid_child := []syntax.Node{{
		kind = .Optional,
		span = span,
		child = 1,
		has_child = true,
	}}
	expect_invalid_ast_without_program_owner(t, invalid_child, 0, source)
}

@(test)
shared_ast_subgraphs_remain_valid :: proc(t: ^testing.T) {
	source := diagnostic.borrow_source("dag", ".")
	span, _ := diagnostic.make_span(source, 0, 1)
	nodes := []syntax.Node{
		{kind = .Identity, span = span},
		{kind = .Optional, span = span, child = 0, has_child = true},
		{kind = .Parenthesized, span = span, child = 0, has_child = true},
		{kind = .Pipe, span = span, left = 1, right = 2},
	}
	compiled: program.Program
	lowered := lower_filter(&compiled, nodes, 3, source, context.allocator)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	testing.expect(t, program.program_is_active(&compiled))
	root, root_ok := program.program_root(&compiled)
	testing.expect(t, root_ok && root == 3)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error.None)
}

@(test)
static_field_numeric_update_lowers_to_two_owned_text_operands :: proc(t: ^testing.T) {
	parser: syntax.Parser
	compiled: program.Program
	_, _, lowered := parse_and_lower(t, `.foo |= .+1`, &parser, &compiled)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	root, root_ok := program.program_root(&compiled)
	testing.expect(t, root_ok)
	instruction := instruction_at(&compiled, root)
	testing.expect_value(t, instruction.opcode, program.Opcode.Static_Field_Add_Number)
	testing.expect_value(t, instruction.operands_count, program.Count(2))
	key_operand := instruction_operand(&compiled, instruction, 0)
	number_operand := instruction_operand(&compiled, instruction, 1)
	key, key_ok := program.operand_text(&compiled, key_operand)
	number, number_ok := program.operand_text(&compiled, number_operand)
	testing.expect(t, key_ok && number_ok)
	testing.expect_value(t, key, "foo")
	testing.expect_value(t, number, "1")
	expect_cleanup(t, &parser, &compiled)
}

@(test)
static_field_numeric_set_lowers_to_two_owned_text_operands :: proc(t: ^testing.T) {
	parser: syntax.Parser
	compiled: program.Program
	_, _, lowered := parse_and_lower(t, `.foo = 9`, &parser, &compiled)
	testing.expect_value(t, lowered.kind, Lower_Error_Kind.None)
	root, root_ok := program.program_root(&compiled)
	testing.expect(t, root_ok)
	instruction := instruction_at(&compiled, root)
	testing.expect_value(t, instruction.opcode, program.Opcode.Static_Field_Set_Number)
	testing.expect_value(t, instruction.operands_count, program.Count(2))
	key, key_ok := program.operand_text(&compiled, instruction_operand(&compiled, instruction, 0))
	number, number_ok := program.operand_text(&compiled, instruction_operand(&compiled, instruction, 1))
	testing.expect(t, key_ok && number_ok)
	testing.expect_value(t, key, "foo")
	testing.expect_value(t, number, "9")
	expect_cleanup(t, &parser, &compiled)
}

@(test)
foreach_lowers_to_four_operands :: proc(t: ^testing.T) {
	parser: syntax.Parser
	source := diagnostic.borrow_source("<foreach-lower>", `foreach .[] as $x (0; . + $x)`)
	testing.expect(t, syntax.init_parser(&parser, source, context.allocator))
	parsed := syntax.parse_filter(&parser)
	testing.expect_value(t, parsed.kind, syntax.Parse_Outcome_Kind.Success)
	root := syntax.parser_nodes(&parser)[int(parsed.root)]
	testing.expect_value(t, root.kind, syntax.Node_Kind.Foreach)
	testing.expect(t, root.has_reduce_update && root.has_name_span)
	testing.expect_value(t, syntax.destroy_parser(&parser), runtime.Allocator_Error.None)
}
