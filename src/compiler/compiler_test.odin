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
	DEPTH :: 12_000
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
