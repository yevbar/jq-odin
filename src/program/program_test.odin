package program

import "base:runtime"
import "core:mem"
import "core:testing"

TRACKING_MEMORY : bool : #config(ODIN_TEST_TRACK_MEMORY, true)

@(private="package")
Fail_Allocator :: struct {
	backing: runtime.Allocator,
	fail_alloc: bool,
	short_alloc: bool,
	free_failures: int,
	allocations: int,
}

@(private="package")
fail_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	probe := cast(^Fail_Allocator)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		probe.allocations += 1
		if probe.fail_alloc {
			return nil, .Out_Of_Memory
		}
		if probe.short_alloc {
			return probe.backing.procedure(
				probe.backing.data, mode, size-1, alignment,
				old_memory, old_size, location,
			)
		}
	}
	if mode == .Free && probe.free_failures > 0 {
		probe.free_failures -= 1
		return nil, .Invalid_Pointer
	}
	return probe.backing.procedure(
		probe.backing.data, mode, size, alignment,
		old_memory, old_size, location,
	)
}

@(private="package")
fail_allocator :: proc(probe: ^Fail_Allocator) -> runtime.Allocator {
	return runtime.Allocator{procedure = fail_allocator_proc, data = probe}
}

@(test)
empty_allocation_is_building_but_cannot_be_finalized :: proc(t: ^testing.T) {
	p: Program
	err := init_program(&p, 0, 0, 0, context.allocator)
	testing.expect_value(t, err.kind, Init_Error_Kind.None)
	testing.expect(t, program_is_building(&p))
	testing.expect(t, set_root(&p, 0))
	testing.expect(t, !finalize_program(&p))
	_, instruction_count_ok := program_instruction_count(&p)
	_, operand_count_ok := program_operand_count(&p)
	testing.expect(t, !instruction_count_ok && !operand_count_ok)
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
sealed_access_is_by_value_and_text_is_an_immutable_borrow :: proc(t: ^testing.T) {
	p: Program
	err := init_program(&p, 1, 1, 3, context.allocator)
	testing.expect_value(t, err.kind, Init_Error_Kind.None)
	_, building_instruction_ok := program_instruction(&p, 0)
	_, building_operand_ok := program_operand(&p, 0)
	_, building_root_ok := program_root(&p)
	testing.expect(t, !building_instruction_ok && !building_operand_ok && !building_root_ok)
	testing.expect(t, set_text(&p, 0, "a\x00b"))
	operand := Operand{kind = .Text, text_start = 0, text_count = 3}
	testing.expect(t, set_operand(&p, 0, operand))
	testing.expect(t, set_instruction(&p, 0, Instruction{
		opcode = .Field,
		operands_count = 1,
		span = {start = 2, end = 6},
	}))
	testing.expect(t, set_root(&p, 0))
	testing.expect(t, finalize_program(&p))
	stored_operand, operand_ok := program_operand(&p, 0)
	view, ok := operand_text(&p, stored_operand)
	testing.expect(t, ok && view == "a\x00b")
	instruction, instruction_ok := program_instruction(&p, 0)
	testing.expect(t, instruction_ok && operand_ok)
	testing.expect_value(t, instruction.span.start, Source_Offset(2))
	instruction.span.start = 99
	stored_again, stored_again_ok := program_instruction(&p, 0)
	testing.expect(t, stored_again_ok)
	testing.expect_value(t, stored_again.span.start, Source_Offset(2))
	stored_operand.text_count = 0
	operand_again, operand_again_ok := program_operand(&p, 0)
	testing.expect(t, operand_again_ok)
	testing.expect_value(t, operand_again.text_count, Count(3))
	instruction_count, instruction_count_ok := program_instruction_count(&p)
	operand_count, operand_count_ok := program_operand_count(&p)
	testing.expect(t, instruction_count_ok && operand_count_ok)
	testing.expect_value(t, instruction_count, Count(1))
	testing.expect_value(t, operand_count, Count(1))

	// Every supported construction mutation, including finalization, rejects
	// after the Program has sealed.
	testing.expect(t, !set_instruction(&p, 0, {}))
	testing.expect(t, !set_operand(&p, 0, {}))
	testing.expect(t, !set_text(&p, 0, "x"))
	testing.expect(t, !set_root(&p, 0))
	testing.expect(t, !finalize_program(&p))
	testing.expect(t, !set_text(&p, 2, "xx"))
	testing.expect(t, !set_operand(&p, 2, {}))
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
out_of_range_text_writes_preserve_building_owner :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	p: Program
	allocator := mem.tracking_allocator(&tracker)
	testing.expect_value(t, init_program(&p, 1, 1, 1, allocator).kind, Init_Error_Kind.None)
	testing.expect_value(t, p.text[0], u8(0))

	starts := [?]Byte_Offset{2, max(Byte_Offset)}
	values := [?]string{"", "x"}
	for start in starts {
		for value in values {
			testing.expect(t, !set_text(&p, start, value))
			testing.expect_value(t, p.text[0], u8(0))
			testing.expect_value(t, p.instructions_written, Count(0))
			testing.expect_value(t, p.operands_written, Count(0))
			testing.expect_value(t, p.text_written, Count(0))
		}
	}

	testing.expect(t, program_is_building(&p))
	testing.expect(t, set_text(&p, 0, "q"))
	testing.expect(t, set_operand(&p, 0, {
		kind = .Text,
		text_count = 1,
	}))
	testing.expect(t, set_instruction(&p, 0, {
		opcode = .Field,
		operands_count = 1,
	}))
	testing.expect(t, set_root(&p, 0))
	testing.expect(t, finalize_program(&p))
	operand, operand_ok := program_operand(&p, 0)
	text, text_ok := operand_text(&p, operand)
	testing.expect(t, operand_ok && text_ok && text == "q")
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
}

@(test)
finalization_rejects_incomplete_invalid_and_out_of_range_construction :: proc(t: ^testing.T) {
	incomplete: Program
	testing.expect_value(t, init_program(&incomplete, 1, 0, 0, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_root(&incomplete, 0))
	testing.expect(t, !finalize_program(&incomplete))
	testing.expect(t, program_is_building(&incomplete))
	testing.expect_value(t, destroy_program(&incomplete), runtime.Allocator_Error.None)

	missing_root: Program
	testing.expect_value(t, init_program(&missing_root, 1, 0, 0, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_instruction(&missing_root, 0, {opcode = .Identity}))
	testing.expect(t, !finalize_program(&missing_root))
	_, missing_root_readable := program_instruction_count(&missing_root)
	testing.expect(t, !missing_root_readable)
	testing.expect_value(t, destroy_program(&missing_root), runtime.Allocator_Error.None)

	out_of_range_root: Program
	testing.expect_value(t, init_program(&out_of_range_root, 1, 0, 0, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_instruction(&out_of_range_root, 0, {opcode = .Identity}))
	testing.expect(t, set_root(&out_of_range_root, 1))
	testing.expect(t, !finalize_program(&out_of_range_root))
	_, out_of_range_readable := program_instruction_count(&out_of_range_root)
	testing.expect(t, !out_of_range_readable)
	testing.expect_value(t, destroy_program(&out_of_range_root), runtime.Allocator_Error.None)

	invalid: Program
	testing.expect_value(t, init_program(&invalid, 1, 0, 0, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_instruction(&invalid, 0, {
		opcode = .Identity,
		span = {start = 4, end = 3},
	}))
	testing.expect(t, set_root(&invalid, 0))
	testing.expect(t, !finalize_program(&invalid))
	_, invalid_readable := program_root(&invalid)
	testing.expect(t, !invalid_readable)
	testing.expect_value(t, destroy_program(&invalid), runtime.Allocator_Error.None)
}

@(test)
finalization_rejects_empty_binary_operator_span :: proc(t: ^testing.T) {
	p: Program
	testing.expect_value(t, init_program(&p, 3, 2, 0, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_operand(&p, 0, {kind = .Instruction, instruction = 1}))
	testing.expect(t, set_operand(&p, 1, {kind = .Instruction, instruction = 2}))
	testing.expect(t, set_instruction(&p, 0, {
		opcode = .Add,
		operands_count = 2,
		span = {start = 4, end = 6},
		operator_span = {start = 5, end = 5},
		has_operator_span = true,
	}))
	testing.expect(t, set_instruction(&p, 1, {opcode = .Identity, span = {start = 0, end = 1}}))
	testing.expect(t, set_instruction(&p, 2, {opcode = .Identity, span = {start = 1, end = 2}}))
	testing.expect(t, set_root(&p, 0))
	testing.expect(t, !finalize_program(&p))
	testing.expect(t, program_is_building(&p))
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
finalization_rejects_operator_span_on_nonbinary_instruction :: proc(t: ^testing.T) {
	p: Program
	testing.expect_value(t, init_program(&p, 1, 0, 0, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_instruction(&p, 0, {
		opcode = .Identity,
		span = {start = 0, end = 1},
		operator_span = {start = 0, end = 1},
	}))
	testing.expect(t, set_root(&p, 0))
	testing.expect(t, !finalize_program(&p))
	testing.expect(t, program_is_building(&p))
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
finalization_rejects_unknown_opcodes_and_operand_kinds :: proc(t: ^testing.T) {
	invalid_opcode: Program
	testing.expect_value(t, init_program(&invalid_opcode, 1, 0, 0, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_instruction(&invalid_opcode, 0, {
		opcode = cast(Opcode)(int(max(Opcode))+1),
	}))
	testing.expect(t, set_root(&invalid_opcode, 0))
	testing.expect(t, !finalize_program(&invalid_opcode))
	testing.expect(t, program_is_building(&invalid_opcode))
	testing.expect(t, !program_is_active(&invalid_opcode))
	testing.expect_value(t, destroy_program(&invalid_opcode), runtime.Allocator_Error.None)

	invalid_operand: Program
	testing.expect_value(t, init_program(&invalid_operand, 1, 1, 1, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_text(&invalid_operand, 0, "x"))
	testing.expect(t, set_operand(&invalid_operand, 0, {
		kind = cast(Operand_Kind)(int(max(Operand_Kind))+1),
		text_count = 1,
	}))
	testing.expect(t, set_instruction(&invalid_operand, 0, {
		opcode = .Field,
		operands_count = 1,
	}))
	testing.expect(t, set_root(&invalid_operand, 0))
	testing.expect(t, !finalize_program(&invalid_operand))
	testing.expect(t, program_is_building(&invalid_operand))
	testing.expect(t, !program_is_active(&invalid_operand))
	testing.expect_value(t, destroy_program(&invalid_operand), runtime.Allocator_Error.None)
}

@(test)
literal_payloads_are_sealed_with_their_text_ranges :: proc(t: ^testing.T) {
	valid: Program
	testing.expect_value(t, init_program(&valid, 1, 1, 2, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_text(&valid, 0, "01"))
	testing.expect(t, set_operand(&valid, 0, {kind = .Text, text_count = 2}))
	testing.expect(t, set_instruction(&valid, 0, {
		opcode = .Identity,
		has_literal = true,
		literal_kind = .Number,
		operands_count = 1,
	}))
	testing.expect(t, set_root(&valid, 0))
	testing.expect(t, finalize_program(&valid))
	testing.expect_value(t, destroy_program(&valid), runtime.Allocator_Error.None)

	invalid: Program
	testing.expect_value(t, init_program(&invalid, 1, 0, 0, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_instruction(&invalid, 0, {
		opcode = .Identity,
		has_literal = true,
		literal_kind = cast(Literal_Kind)(int(max(Literal_Kind))+1),
	}))
	testing.expect(t, set_root(&invalid, 0))
	testing.expect(t, !finalize_program(&invalid))
	testing.expect_value(t, destroy_program(&invalid), runtime.Allocator_Error.None)
}

@(test)
literal_metadata_is_rejected_on_non_identity_instructions :: proc(t: ^testing.T) {
	forged: Program
	testing.expect_value(t, init_program(&forged, 1, 1, 1, context.allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_text(&forged, 0, "x"))
	testing.expect(t, set_operand(&forged, 0, {kind = .Text, text_count = 1}))
	testing.expect(t, set_instruction(&forged, 0, {
		opcode = .Field,
		has_literal = true,
		literal_kind = .Number,
		operands_count = 1,
	}))
	testing.expect(t, set_root(&forged, 0))
	testing.expect(t, !finalize_program(&forged))
	testing.expect(t, program_is_building(&forged))
	testing.expect(t, !program_is_active(&forged))
	testing.expect_value(t, destroy_program(&forged), runtime.Allocator_Error.None)
}

@(test)
selected_root_survives_multiple_and_unreachable_nodes :: proc(t: ^testing.T) {
	for _ in 0..<2 {
		p: Program
		testing.expect_value(t, init_program(&p, 3, 0, 0, context.allocator).kind, Init_Error_Kind.None)
		for index in 0..<3 {
		testing.expect(t, set_instruction(&p, Instruction_Index(index), {
				opcode = .Identity,
				span = {start = Source_Offset(index), end = Source_Offset(index+1)},
			}))
		}
		// Nodes 0 and 2 are unreachable; allocation/arena order must not choose
		// the last node in place of the caller-selected entry.
		testing.expect(t, set_root(&p, 1))
		testing.expect(t, !set_root(&p, 2))
		testing.expect(t, finalize_program(&p))
		root, root_ok := program_root(&p)
		testing.expect(t, root_ok)
		testing.expect_value(t, root, Instruction_Index(1))
		testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
	}
}

@(private="package")
expect_cycle_rejected_and_released :: proc(
	t: ^testing.T,
	instructions: []Instruction,
	operands: []Operand,
	root: Instruction_Index,
) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	p: Program
	allocator := mem.tracking_allocator(&tracker)
	init_error := init_program(&p, Count(len(instructions)), Count(len(operands)), 0, allocator)
	testing.expect_value(t, init_error.kind, Init_Error_Kind.None)
	for operand, index in operands {
		testing.expect(t, set_operand(&p, Operand_Index(index), operand))
	}
	for instruction, index in instructions {
		testing.expect(t, set_instruction(&p, Instruction_Index(index), instruction))
	}
	testing.expect(t, set_root(&p, root))
	testing.expect(t, !finalize_program(&p))
	testing.expect(t, program_is_building(&p))
	testing.expect(t, !program_is_active(&p))
	_, readable := program_instruction_count(&p)
	testing.expect(t, !readable)
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
}

@(test)
finalization_rejects_self_and_multi_node_cycles :: proc(t: ^testing.T) {
	self_instructions := []Instruction{{opcode = .Optional, operands_count = 1}}
	self_operands := []Operand{{kind = .Instruction, instruction = 0}}
	expect_cycle_rejected_and_released(t, self_instructions, self_operands, 0)

	multi_instructions := []Instruction{
		{opcode = .Optional, operands_start = 0, operands_count = 1},
		{opcode = .Parenthesized, operands_start = 1, operands_count = 1},
	}
	multi_operands := []Operand{
		{kind = .Instruction, instruction = 1},
		{kind = .Instruction, instruction = 0},
	}
	expect_cycle_rejected_and_released(t, multi_instructions, multi_operands, 0)
}

@(test)
graph_validation_uses_only_the_single_program_allocation :: proc(t: ^testing.T) {
	probe := Fail_Allocator{backing = context.allocator}
	p: Program
	testing.expect_value(t, init_program(&p, 1, 1, 0, fail_allocator(&probe)).kind, Init_Error_Kind.None)
	testing.expect_value(t, probe.allocations, 1)
	testing.expect_value(t, len(p.validation_records), 1)
	testing.expect(t, set_operand(&p, 0, {kind = .Instruction, instruction = 0}))
	testing.expect(t, set_instruction(&p, 0, {opcode = .Optional, operands_count = 1}))
	testing.expect(t, set_root(&p, 0))
	testing.expect(t, !finalize_program(&p))
	testing.expect_value(t, probe.allocations, 1)
	testing.expect(t, program_is_building(&p))
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
finalization_validates_unreachable_nodes_and_preserves_forward_shared_dags :: proc(t: ^testing.T) {
	unreachable_cycle_instructions := []Instruction{
		{opcode = .Identity},
		{opcode = .Optional, operands_start = 0, operands_count = 1},
		{opcode = .Parenthesized, operands_start = 1, operands_count = 1},
	}
	unreachable_cycle_operands := []Operand{
		{kind = .Instruction, instruction = 2},
		{kind = .Instruction, instruction = 1},
	}
	expect_cycle_rejected_and_released(
		t,
		unreachable_cycle_instructions,
		unreachable_cycle_operands,
		0,
	)

	p: Program
	testing.expect_value(t, init_program(&p, 4, 4, 0, context.allocator).kind, Init_Error_Kind.None)
	shared_operands := []Operand{
		{kind = .Instruction, instruction = 0},
		{kind = .Instruction, instruction = 2}, // valid forward edge
		{kind = .Instruction, instruction = 0}, // shared child
		{kind = .Instruction, instruction = 0},
	}
	for operand, index in shared_operands {
		testing.expect(t, set_operand(&p, Operand_Index(index), operand))
	}
	shared_instructions := []Instruction{
		{opcode = .Identity},
		{opcode = .Sequence, operands_start = 0, operands_count = 2},
		{opcode = .Fork, operands_start = 2, operands_count = 2},
		{opcode = .Identity, operands_start = 4}, // unreachable from selected root
	}
	for instruction, index in shared_instructions {
		testing.expect(t, set_instruction(&p, Instruction_Index(index), instruction))
	}
	testing.expect(t, set_root(&p, 1))
	testing.expect(t, finalize_program(&p))
	root, root_ok := program_root(&p)
	testing.expect(t, root_ok && root == 1)
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
fixed_width_layout_overflow_is_atomic :: proc(t: ^testing.T) {
	probe := Fail_Allocator{backing = context.allocator}
	p: Program
	err := init_program(
		&p,
		Count(max(u32)),
		Count(max(u32)),
		Count(max(u32)),
		fail_allocator(&probe),
	)
	testing.expect_value(t, err.kind, Init_Error_Kind.Size_Overflow)
	testing.expect_value(t, probe.allocations, 0)
	testing.expect(t, !program_is_active(&p))
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
graph_record_layout_overflow_is_rejected_before_allocation :: proc(t: ^testing.T) {
	probe := Fail_Allocator{backing = context.allocator}
	p: Program
	instruction_only_limit := Count(
		u64(max(Storage_Count)) / u64(size_of(Instruction)),
	)
	err := init_program(&p, instruction_only_limit, 0, 0, fail_allocator(&probe))
	testing.expect_value(t, err.kind, Init_Error_Kind.Size_Overflow)
	testing.expect_value(t, probe.allocations, 0)
	testing.expect(t, !program_is_building(&p))
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
allocation_failure_leaves_no_partial_owner :: proc(t: ^testing.T) {
	probe := Fail_Allocator{backing = context.allocator, fail_alloc = true}
	p: Program
	err := init_program(&p, 2, 2, 8, fail_allocator(&probe))
	testing.expect_value(t, err.kind, Init_Error_Kind.Resource_Failure)
	testing.expect_value(t, err.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, probe.allocations, 1)
	testing.expect(t, !program_is_active(&p))
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
short_allocator_result_is_retired_without_escape :: proc(t: ^testing.T) {
	probe := Fail_Allocator{backing = context.allocator, short_alloc = true}
	p: Program
	err := init_program(&p, 2, 2, 8, fail_allocator(&probe))
	testing.expect_value(t, err.kind, Init_Error_Kind.Resource_Failure)
	testing.expect(t, !program_is_active(&p))
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
destroy_preserves_owner_for_retry_then_becomes_idempotent :: proc(t: ^testing.T) {
	probe := Fail_Allocator{backing = context.allocator}
	p: Program
	err := init_program(&p, 2, 2, 8, fail_allocator(&probe))
	testing.expect_value(t, err.kind, Init_Error_Kind.None)
	testing.expect(t, program_is_building(&p))
	probe.free_failures = 1
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, p.state, Program_State.Cleanup_Failed)
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
}

@(test)
destroy_rejects_shallow_copied_building_owner_without_touching_backing :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	original: Program
	allocator := mem.tracking_allocator(&tracker)
	testing.expect_value(t, init_program(&original, 1, 1, 3, allocator).kind, Init_Error_Kind.None)
	copied := original
	testing.expect_value(t, destroy_program(&copied), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, copied.state, Program_State.Building)
	testing.expect_value(t, copied.self, &original)
	testing.expect_value(t, original.state, Program_State.Building)
	testing.expect(t, program_is_building(&original) && !program_is_building(&copied))
	testing.expect_value(t, original.instructions_written, Count(0))
	testing.expect_value(t, original.operands_written, Count(0))
	testing.expect_value(t, original.text_written, Count(0))
	testing.expect_value(t, len(tracker.allocation_map), 1)
	testing.expect_value(t, len(tracker.bad_free_array), 0)

	testing.expect(t, set_text(&original, 0, "abc"))
	testing.expect(t, set_operand(&original, 0, {
		kind = .Text,
		text_count = 3,
	}))
	testing.expect(t, set_instruction(&original, 0, {
		opcode = .Field,
		operands_count = 1,
	}))
	testing.expect(t, set_root(&original, 0))
	testing.expect(t, finalize_program(&original))
	operand, operand_ok := program_operand(&original, 0)
	text, text_ok := operand_text(&original, operand)
	testing.expect(t, operand_ok && text_ok && text == "abc")
	testing.expect_value(t, destroy_program(&original), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
}

@(test)
destroy_rejects_shallow_copied_active_owner_without_affecting_reads :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	original: Program
	allocator := mem.tracking_allocator(&tracker)
	testing.expect_value(t, init_program(&original, 1, 0, 0, allocator).kind, Init_Error_Kind.None)
	testing.expect(t, set_instruction(&original, 0, {opcode = .Identity}))
	testing.expect(t, set_root(&original, 0))
	testing.expect(t, finalize_program(&original))
	copied := original
	testing.expect_value(t, destroy_program(&copied), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, copied.state, Program_State.Active)
	testing.expect_value(t, copied.self, &original)
	testing.expect(t, program_is_active(&original) && !program_is_active(&copied))
	instruction, readable := program_instruction(&original, 0)
	testing.expect(t, readable)
	testing.expect_value(t, instruction.opcode, Opcode.Identity)
	testing.expect_value(t, len(tracker.allocation_map), 1)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	testing.expect_value(t, destroy_program(&original), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
}

@(test)
destroy_rejects_shallow_copied_cleanup_owner_without_consuming_retry :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	probe := Fail_Allocator{
		backing = mem.tracking_allocator(&tracker),
		free_failures = 1,
	}
	original: Program
	testing.expect_value(t, init_program(&original, 1, 0, 0, fail_allocator(&probe)).kind, Init_Error_Kind.None)
	testing.expect_value(t, destroy_program(&original), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, original.state, Program_State.Cleanup_Failed)
	testing.expect_value(t, probe.free_failures, 0)
	copied := original
	testing.expect_value(t, destroy_program(&copied), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, copied.state, Program_State.Cleanup_Failed)
	testing.expect_value(t, copied.self, &original)
	testing.expect_value(t, original.state, Program_State.Cleanup_Failed)
	testing.expect_value(t, probe.free_failures, 0)
	testing.expect_value(t, len(tracker.allocation_map), 1)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	testing.expect_value(t, destroy_program(&original), runtime.Allocator_Error.None)
	testing.expect_value(t, original.state, Program_State.Destroyed)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
}

@(test)
destroy_keeps_uninitialized_and_destroyed_values_idempotent :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	uninitialized: Program
	uninitialized_copy := uninitialized
	testing.expect_value(t, destroy_program(&uninitialized), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_program(&uninitialized_copy), runtime.Allocator_Error.None)
	testing.expect_value(t, uninitialized.state, Program_State.Uninitialized)
	testing.expect_value(t, uninitialized_copy.state, Program_State.Uninitialized)

	destroyed: Program
	testing.expect_value(t, init_program(&destroyed, 1, 0, 0, mem.tracking_allocator(&tracker)).kind, Init_Error_Kind.None)
	testing.expect_value(t, destroy_program(&destroyed), runtime.Allocator_Error.None)
	destroyed_copy := destroyed
	testing.expect_value(t, destroy_program(&destroyed), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_program(&destroyed_copy), runtime.Allocator_Error.None)
	testing.expect_value(t, destroyed.state, Program_State.Destroyed)
	testing.expect_value(t, destroyed_copy.state, Program_State.Destroyed)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
}

@(test)
program_allocation_has_no_bad_memory :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&tracker)

	p: Program
	err := init_program(&p, 16, 32, 64, mem.tracking_allocator(&tracker))
	testing.expect_value(t, err.kind, Init_Error_Kind.None)
	testing.expect(t, program_is_building(&p))
	testing.expect_value(t, destroy_program(&p), runtime.Allocator_Error.None)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
}
