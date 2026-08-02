// Package compiler lowers source syntax into a compiled program.
package compiler

import "base:runtime"
import diagnostic "jq:diagnostic"
import program "jq:program"
import syntax "jq:syntax"

Lower_Error_Kind :: enum u8 {
	None,
	Invalid_AST,
	Size_Overflow,
	Resource_Failure,
}

Lower_Outcome :: struct {
	kind:           Lower_Error_Kind,
	resource_error: runtime.Allocator_Error,
}

@(private="package")
checked_count_add :: proc(total: ^u64, amount: u64) -> bool {
	if amount > u64(max(program.Count)) || total^ > u64(max(program.Count)) - amount {
		return false
	}
	total^ += amount
	return true
}

@(private="package")
node_reference_valid :: proc(id: syntax.Node_Id, node_count: int) -> bool {
	return int(id) >= 0 && int(id) < node_count
}

@(private="package")
span_to_program :: proc(
	source: diagnostic.Source,
	span: diagnostic.Span,
) -> (program.Source_Span, Lower_Error_Kind) {
	start, end, ok := diagnostic.span_offsets(source, span)
	if !ok {
		return {}, .Invalid_AST
	}
	if u64(start) > u64(max(program.Source_Offset)) ||
	   u64(end) > u64(max(program.Source_Offset)) {
		return {}, .Size_Overflow
	}
	return program.Source_Span{
		start = program.Source_Offset(start),
		end = program.Source_Offset(end),
	}, .None
}

// lower_filter translates a complete borrowed syntax arena into one owned,
// source-independent Program. It performs a non-allocating validation/counting
// pass before Program's single exact allocation, then fills storage in arena
// order. On ordinary failure output remains inert. If retiring a malformed
// allocator result itself fails, output is Cleanup_Failed and must be passed to
// program.destroy_program until cleanup succeeds.
lower_filter :: proc(
	output: ^program.Program,
	nodes: []syntax.Node,
	root: syntax.Node_Id,
	source: diagnostic.Source,
	allocator: runtime.Allocator,
) -> Lower_Outcome {
	if output == nil || program.program_is_active(output) || program.program_is_building(output) ||
	   len(nodes) == 0 ||
	   !node_reference_valid(root, len(nodes)) {
		return Lower_Outcome{kind = .Invalid_AST}
	}
	if u64(len(nodes)) > u64(max(program.Count)) {
		return Lower_Outcome{kind = .Size_Overflow}
	}

	operand_count: u64
	text_count: u64
	for node in nodes {
		_, span_error := span_to_program(source, node.span)
		if span_error != .None {
			return Lower_Outcome{kind = span_error}
		}

		switch node.kind {
		case .Identity:
			if node.has_child || node.has_name_span {
				return Lower_Outcome{kind = .Invalid_AST}
			}
		case .Field:
			if !node.has_name_span || node.has_child && !node_reference_valid(node.child, len(nodes)) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
			name_start, name_end, name_ok := diagnostic.span_offsets(source, node.name_span)
			if !name_ok || name_end < name_start {
				return Lower_Outcome{kind = .Invalid_AST}
			}
			if !checked_count_add(&operand_count, 1 + u64(node.has_child)) ||
			   !checked_count_add(&text_count, u64(name_end-name_start)) {
				return Lower_Outcome{kind = .Size_Overflow}
			}
		case .Parenthesized, .Optional:
			if !node.has_child || node.has_name_span ||
			   !node_reference_valid(node.child, len(nodes)) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
			if !checked_count_add(&operand_count, 1) {
				return Lower_Outcome{kind = .Size_Overflow}
			}
		case .Comma, .Pipe:
			if node.has_child || node.has_name_span ||
			   !node_reference_valid(node.left, len(nodes)) ||
			   !node_reference_valid(node.right, len(nodes)) {
				return Lower_Outcome{kind = .Invalid_AST}
			}
			if !checked_count_add(&operand_count, 2) {
				return Lower_Outcome{kind = .Size_Overflow}
			}
		case:
			return Lower_Outcome{kind = .Invalid_AST}
		}
	}

	init_error := program.init_program(
		output,
		program.Count(len(nodes)),
		program.Count(operand_count),
		program.Count(text_count),
		allocator,
	)
	if init_error.kind != .None {
		kind := Lower_Error_Kind.Resource_Failure
		if init_error.kind == .Size_Overflow {
			kind = .Size_Overflow
		}
		return Lower_Outcome{kind = kind, resource_error = init_error.resource_error}
	}

	operand_at: u32
	text_at: u32
	bytes := diagnostic.source_bytes(source)
	for node, node_at in nodes {
		span, span_error := span_to_program(source, node.span)
		assert(span_error == .None)
		instruction := program.Instruction{
			operands_start = program.Operand_Index(operand_at),
			span = span,
		}

		switch node.kind {
		case .Identity:
			instruction.opcode = .Identity
		case .Field:
			instruction.opcode = .Field
			if node.has_child {
				write_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
					kind = .Instruction,
					instruction = program.Instruction_Index(node.child),
				})
				assert(write_ok)
				operand_at += 1
			}
			name_start, name_end, _ := diagnostic.span_offsets(source, node.name_span)
			name := bytes[name_start:name_end]
			text_ok := program.set_text(output, program.Byte_Offset(text_at), name)
			assert(text_ok)
			operand_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Text,
				text_start = program.Byte_Offset(text_at),
				text_count = program.Count(len(name)),
			})
			assert(operand_ok)
			operand_at += 1
			text_at += u32(len(name))
			instruction.operands_count = program.Count(1 + u32(node.has_child))
		case .Parenthesized, .Optional:
			instruction.opcode = .Parenthesized if node.kind == .Parenthesized else .Optional
			instruction.operands_count = 1
			write_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Instruction,
				instruction = program.Instruction_Index(node.child),
			})
			assert(write_ok)
			operand_at += 1
		case .Comma, .Pipe:
			instruction.opcode = .Fork if node.kind == .Comma else .Sequence
			instruction.operands_count = 2
			left_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Instruction,
				instruction = program.Instruction_Index(node.left),
			})
			assert(left_ok)
			operand_at += 1
			right_ok := program.set_operand(output, program.Operand_Index(operand_at), program.Operand{
				kind = .Instruction,
				instruction = program.Instruction_Index(node.right),
			})
			assert(right_ok)
			operand_at += 1
		case:
			cleanup_error := program.destroy_program(output)
			if cleanup_error != nil {
				return Lower_Outcome{kind = .Resource_Failure, resource_error = cleanup_error}
			}
			return Lower_Outcome{kind = .Invalid_AST}
		}
		instruction_ok := program.set_instruction(output, program.Instruction_Index(node_at), instruction)
		assert(instruction_ok)
	}
	assert(operand_at == u32(operand_count) && text_at == u32(text_count))
	root_ok := program.set_root(output, program.Instruction_Index(root))
	sealed := program.finalize_program(output)
	if !root_ok || !sealed {
		cleanup_error := program.destroy_program(output)
		if cleanup_error != nil {
			return Lower_Outcome{kind = .Resource_Failure, resource_error = cleanup_error}
		}
		return Lower_Outcome{kind = .Invalid_AST}
	}
	return {}
}
