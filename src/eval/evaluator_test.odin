package eval

import "base:runtime"
import "core:testing"
import program "jq:program"
import value "jq:value"

@(test)
evaluator_internal_layout_matches_public_handle :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(evaluator_storage), 248)
	testing.expect_value(t, align_of(evaluator_storage), 8)
	testing.expect_value(t, size_of(Evaluator_Handle), size_of(evaluator_storage))
	testing.expect_value(t, align_of(Evaluator_Handle), align_of(evaluator_storage))
	testing.expect_value(t, size_of(Evaluator), 256)
	testing.expect_value(t, align_of(Evaluator), 8)
}

@(private)
build_program :: proc(
	t: ^testing.T,
	output: ^program.Program,
	instructions: []program.Instruction,
	operands: []program.Operand,
	text: string,
	root: int,
	allocator := context.allocator,
) {
	init_error := program.init_program(
		output,
		program.Count(len(instructions)),
		program.Count(len(operands)),
		program.Count(len(text)),
		allocator,
	)
	testing.expect_value(t, init_error.kind, program.Init_Error_Kind.None)
	for instruction, index in instructions {
		testing.expect(t, program.set_instruction(output, program.Instruction_Index(index), instruction))
	}
	for operand, index in operands {
		testing.expect(t, program.set_operand(output, program.Operand_Index(index), operand))
	}
	if len(text) > 0 do testing.expect(t, program.set_text(output, 0, text))
	testing.expect(t, program.set_root(output, program.Instruction_Index(root)))
	testing.expect(t, program.finalize_program(output))
}

@(private)
destroy_program_test :: proc(t: ^testing.T, compiled: ^program.Program) {
	testing.expect_value(t, program.destroy_program(compiled), runtime.Allocator_Error(nil))
}

@(private)
step_take :: proc(t: ^testing.T, evaluator: ^Evaluator) -> value.Value {
	result := step_evaluator(evaluator)
	testing.expect_value(t, result.kind, Step_Kind.Output)
	return take_step_output(&result)
}

@(private)
expect_number :: proc(t: ^testing.T, owned: ^value.Value, expected: f64) {
	actual, ok := value.number_value_get(owned)
	testing.expect(t, ok)
	testing.expect_value(t, actual, expected)
	testing.expect_value(t, value.destroy_value(owned), runtime.Allocator_Error(nil))
}

@(private)
expect_null :: proc(t: ^testing.T, owned: ^value.Value) {
	testing.expect_value(t, value.kind_of(owned), value.Kind.Null)
	testing.expect_value(t, value.destroy_value(owned), runtime.Allocator_Error(nil))
}

@(private)
object_put :: proc(t: ^testing.T, object: ^value.Value, key_text: string, incoming: value.Value) {
	key, key_error := value.string_value(key_text, context.allocator)
	testing.expect_value(t, value.constructor_error_kind(&key_error), value.Error.None)
	owned := incoming
	duplicate, displaced, set_error := value.object_set_take(object, &key, &owned)
	testing.expect_value(t, value.object_error_kind(&set_error), value.Object_Error.None)
	testing.expect_value(t, value.destroy_value(&duplicate), runtime.Allocator_Error(nil))
	testing.expect_value(t, value.destroy_value(&displaced), runtime.Allocator_Error(nil))
}

@(private)
sample_object :: proc(t: ^testing.T) -> value.Value {
	inner, inner_error := value.object_value(context.allocator)
	testing.expect_value(t, value.object_error_kind(&inner_error), value.Object_Error.None)
	object_put(t, &inner, "b", value.number_value(7))
	outer, outer_error := value.object_value(context.allocator)
	testing.expect_value(t, value.object_error_kind(&outer_error), value.Object_Error.None)
	object_put(t, &outer, "a", value.take_value(&inner))
	return outer
}

@(private)
nested_heap_value :: proc(
	t: ^testing.T,
	allocator: runtime.Allocator,
	wrap_in_object: bool,
) -> value.Value {
	leaf, leaf_error := value.string_value("heap-backed-leaf", allocator)
	testing.expect_value(t, value.constructor_error_kind(&leaf_error), value.Error.None)
	array, array_error := value.array_value(allocator)
	testing.expect_value(t, value.array_error_kind(&array_error), value.Array_Error.None)
	displaced, append_error := value.array_append_take(&array, &leaf)
	testing.expect_value(t, value.array_error_kind(&append_error), value.Array_Error.None)
	testing.expect_value(t, value.destroy_value(&displaced), runtime.Allocator_Error(nil))
	if !wrap_in_object do return array

	object, object_error := value.object_value(allocator)
	testing.expect_value(t, value.object_error_kind(&object_error), value.Object_Error.None)
	key, key_error := value.string_value("key", allocator)
	testing.expect_value(t, value.constructor_error_kind(&key_error), value.Error.None)
	duplicate, replaced, set_error := value.object_set_take(&object, &key, &array)
	testing.expect_value(t, value.object_error_kind(&set_error), value.Object_Error.None)
	testing.expect_value(t, value.destroy_value(&duplicate), runtime.Allocator_Error(nil))
	testing.expect_value(t, value.destroy_value(&replaced), runtime.Allocator_Error(nil))
	return object
}

@(private)
text_operand :: proc(start, count: u32) -> program.Operand {
	return {
		kind = .Text,
		text_start = program.Byte_Offset(start),
		text_count = program.Count(count),
	}
}

@(private)
instruction_operand :: proc(index: int) -> program.Operand {
	return {kind = .Instruction, instruction = program.Instruction_Index(index)}
}

@(private)
init_program_failure_case :: enum u8 {
	Missing_Root,
	Root_Out_Of_Range,
	Memory_Slice,
	Instruction_Slice,
	Operand_Slice,
	Text_Slice,
	Validation_Slice,
	Instruction_Opcode,
	Instruction_Span,
	Instruction_Operand_Start,
	Instruction_Operand_Count,
	Operand_Kind,
	Operand_Instruction_Target,
	Operand_Text_Start,
	Operand_Text_Count,
	Instruction_Cycle,
	Instruction_Written_Count,
	Operand_Written_Count,
	Text_Written_Count,
}

@(private)
apply_init_program_failure :: proc(
	compiled: ^program.Program,
	failure: init_program_failure_case,
) {
	switch failure {
	case .Missing_Root:
		compiled.has_root = false
	case .Root_Out_Of_Range:
		compiled.root = program.Instruction_Index(len(compiled.instructions))
	case .Memory_Slice:
		compiled.memory = compiled.memory[:len(compiled.memory)-1]
	case .Instruction_Slice:
		compiled.instructions = compiled.instructions[:len(compiled.instructions)-1]
	case .Operand_Slice:
		compiled.operands = compiled.operands[:len(compiled.operands)-1]
	case .Text_Slice:
		compiled.text = compiled.text[:len(compiled.text)-1]
	case .Validation_Slice:
		compiled.validation_records = compiled.validation_records[
			:len(compiled.validation_records)-1
		]
	case .Instruction_Opcode:
		compiled.instructions[0].opcode = program.Opcode(255)
	case .Instruction_Span:
		compiled.instructions[0].span = {start = 2, end = 1}
	case .Instruction_Operand_Start:
		compiled.instructions[2].operands_start = 2
	case .Instruction_Operand_Count:
		compiled.instructions[2].operands_count = 1
	case .Operand_Kind:
		compiled.operands[0].kind = .Instruction
	case .Operand_Instruction_Target:
		compiled.operands[1].instruction = program.Instruction_Index(
			len(compiled.instructions),
		)
	case .Operand_Text_Start:
		compiled.operands[0].text_start = 1
	case .Operand_Text_Count:
		compiled.operands[0].text_count = program.Count(len(compiled.text)+1)
	case .Instruction_Cycle:
		compiled.operands[1].instruction = 2
	case .Instruction_Written_Count:
		compiled.instructions_written -= 1
	case .Operand_Written_Count:
		compiled.operands_written -= 1
	case .Text_Written_Count:
		compiled.text_written -= 1
	}
}

@(private)
expect_preserved_nested_input :: proc(t: ^testing.T, input: ^value.Value) {
	testing.expect_value(t, value.kind_of(input), value.Kind.Array)
	length, length_ok := value.array_length(input)
	if !testing.expect(t, length_ok) do return
	testing.expect_value(t, length, 1)
	leaf, leaf_ok := value.array_element_copy(input, 0)
	if !testing.expect(t, leaf_ok) do return
	text, text_ok := value.string_borrowed(&leaf)
	testing.expect(t, text_ok)
	testing.expect_value(t, text, "heap-backed-leaf")
	testing.expect_value(t, value.destroy_value(&leaf), runtime.Allocator_Error(nil))
}

@(test)
init_rejects_every_constructible_program_failure_before_allocation_or_input_take :: proc(
	t: ^testing.T,
) {
	failures := [19]init_program_failure_case{
		.Missing_Root,
		.Root_Out_Of_Range,
		.Memory_Slice,
		.Instruction_Slice,
		.Operand_Slice,
		.Text_Slice,
		.Validation_Slice,
		.Instruction_Opcode,
		.Instruction_Span,
		.Instruction_Operand_Start,
		.Instruction_Operand_Count,
		.Operand_Kind,
		.Operand_Instruction_Target,
		.Operand_Text_Start,
		.Operand_Text_Count,
		.Instruction_Cycle,
		.Instruction_Written_Count,
		.Operand_Written_Count,
		.Text_Written_Count,
	}
	for failure in failures {
		scope: allocation_scope
		allocation_scope_begin(&scope)

		instructions := [3]program.Instruction{
			{opcode = .Identity, span = {start = 0, end = 1}},
			{opcode = .Field, operands_count = 1, span = {start = 1, end = 2}},
			{
				opcode = .Fork,
				operands_start = 1,
				operands_count = 2,
				span = {start = 2, end = 3},
			},
		}
		operands := [3]program.Operand{
			text_operand(0, 3), instruction_operand(0), instruction_operand(1),
		}
		compiled: program.Program
		build_program(t, &compiled, instructions[:], operands[:], "key", 2)
		original_instructions := compiled.instructions
		original_operands := compiled.operands
		original_text := compiled.text
		original_validation_records := compiled.validation_records
		original_memory := compiled.memory
		apply_init_program_failure(&compiled, failure)

		input := nested_heap_value(t, context.allocator, false)
		allocator_state := fail_allocator_state{
			backing = context.allocator,
			fail_at = 1,
		}
		evaluator: Evaluator
		result := init_evaluator(
			&evaluator,
			&compiled,
			&input,
			{procedure = fail_allocator_proc, data = &allocator_state},
		)
		testing.expect_value(t, result.kind, Init_Error_Kind.Invalid_Program)
		testing.expect_value(t, allocator_state.call, 0)
		testing.expect_value(t, evaluator == nil, true)
		expect_preserved_nested_input(t, &input)
		testing.expect_value(t, value.destroy_value(&input), runtime.Allocator_Error(nil))

		// Restore only safe descriptors and logical fields before destruction.
		compiled.instructions = original_instructions
		compiled.operands = original_operands
		compiled.text = original_text
		compiled.validation_records = original_validation_records
		compiled.memory = original_memory
		compiled.has_root = true
		compiled.root = 2
		compiled.instructions_written = 3
		compiled.operands_written = 3
		compiled.text_written = 3
		copy(compiled.instructions, instructions[:])
		copy(compiled.operands, operands[:])
		destroy_program_test(t, &compiled)
		allocation_scope_end(t, &scope)
	}
}

@(test)
init_rejects_inactive_and_destroyed_program_without_allocator_or_input_activity :: proc(
	t: ^testing.T,
) {
	scope: allocation_scope
	allocation_scope_begin(&scope)
	compiled: program.Program
	testing.expect_value(
		t,
		program.init_program(&compiled, 1, 0, 0, context.allocator).kind,
		program.Init_Error_Kind.None,
	)
	input := nested_heap_value(t, context.allocator, false)
	allocator_state := fail_allocator_state{backing = context.allocator, fail_at = 1}
	evaluator: Evaluator
	result := init_evaluator(
		&evaluator,
		&compiled,
		&input,
		{procedure = fail_allocator_proc, data = &allocator_state},
	)
	testing.expect_value(t, result.kind, Init_Error_Kind.Invalid_Program)
	testing.expect_value(t, allocator_state.call, 0)
	testing.expect_value(t, evaluator == nil, true)
	expect_preserved_nested_input(t, &input)
	testing.expect_value(t, value.destroy_value(&input), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)

	instructions := [1]program.Instruction{{opcode = .Identity}}
	build_program(t, &compiled, instructions[:], nil, "", 0)
	destroy_program_test(t, &compiled)

	input = nested_heap_value(t, context.allocator, false)
	allocator_state = {backing = context.allocator, fail_at = 1}
	result = init_evaluator(
		&evaluator,
		&compiled,
		&input,
		{procedure = fail_allocator_proc, data = &allocator_state},
	)
	testing.expect_value(t, result.kind, Init_Error_Kind.Invalid_Program)
	testing.expect_value(t, allocator_state.call, 0)
	testing.expect_value(t, evaluator == nil, true)
	expect_preserved_nested_input(t, &input)
	testing.expect_value(t, value.destroy_value(&input), runtime.Allocator_Error(nil))
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error(nil))
	allocation_scope_end(t, &scope)
}

@(test)
core_identity_parentheses_and_fields_are_resumable :: proc(t: ^testing.T) {
	// root Field("b", Field("a", Parenthesized(Identity)))
	instructions := [4]program.Instruction{
		{opcode = .Identity},
		{opcode = .Parenthesized, operands_start = 0, operands_count = 1},
		{opcode = .Field, operands_start = 1, operands_count = 2},
		{opcode = .Field, operands_start = 3, operands_count = 2},
	}
	operands := [5]program.Operand{
		instruction_operand(0),
		instruction_operand(1), text_operand(0, 1),
		instruction_operand(2), text_operand(1, 1),
	}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], operands[:], "ab", 3)
	input := sample_object(t)
	evaluator: Evaluator
	testing.expect_value(
		t,
		init_evaluator(&evaluator, &compiled, &input, context.allocator).kind,
		Init_Error_Kind.None,
	)
	testing.expect_value(t, value.kind_of(&input), value.Kind.Invalid)
	output := step_take(t, &evaluator)
	expect_number(t, &output, 7)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)
}

@(test)
identity_parenthesized_and_optional_identity_each_yield_once :: proc(t: ^testing.T) {
	instructions := [3]program.Instruction{
		{opcode = .Identity},
		{opcode = .Parenthesized, operands_start = 0, operands_count = 1},
		{opcode = .Optional, operands_start = 1, operands_count = 1},
	}
	operands := [2]program.Operand{instruction_operand(0), instruction_operand(0)}
	for root in 0..<3 {
		compiled: program.Program
		build_program(t, &compiled, instructions[:], operands[:], "", root)
		input := value.number_value(3)
		evaluator: Evaluator
		testing.expect_value(t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind, Init_Error_Kind.None)
		output := step_take(t, &evaluator)
		expect_number(t, &output, 3)
		testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
		testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
		destroy_program_test(t, &compiled)
	}
}

@(test)
field_present_missing_null_and_invalid_kinds_match_jq_classes :: proc(t: ^testing.T) {
	instructions := [1]program.Instruction{{opcode = .Field, operands_count = 1}}
	operands := [1]program.Operand{text_operand(0, 1)}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], operands[:], "a", 0)

	present := sample_object(t)
	evaluator: Evaluator
	testing.expect_value(t, init_evaluator(&evaluator, &compiled, &present, context.allocator).kind, Init_Error_Kind.None)
	present_output := step_take(t, &evaluator)
	testing.expect_value(t, value.kind_of(&present_output), value.Kind.Object)
	testing.expect_value(t, value.destroy_value(&present_output), runtime.Allocator_Error(nil))
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))

	missing, missing_error := value.object_value(context.allocator)
	testing.expect_value(t, value.object_error_kind(&missing_error), value.Object_Error.None)
	testing.expect_value(t, init_evaluator(&evaluator, &compiled, &missing, context.allocator).kind, Init_Error_Kind.None)
	missing_output := step_take(t, &evaluator)
	expect_null(t, &missing_output)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))

	null_input := value.null_value()
	testing.expect_value(t, init_evaluator(&evaluator, &compiled, &null_input, context.allocator).kind, Init_Error_Kind.None)
	null_output := step_take(t, &evaluator)
	expect_null(t, &null_output)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))

	invalid_inputs := [4]value.Value{
		value.boolean_value(true),
		value.number_value(1),
		{},
		{},
	}
	invalid_inputs[2], _ = value.string_value("x", context.allocator)
	invalid_inputs[3], _ = value.array_value(context.allocator)
	expected_kinds := [4]value.Kind{.Boolean, .Number, .String, .Array}
	for &invalid_input, index in invalid_inputs {
		testing.expect_value(t, init_evaluator(&evaluator, &compiled, &invalid_input, context.allocator).kind, Init_Error_Kind.None)
		result := step_evaluator(&evaluator)
		testing.expect_value(t, result.kind, Step_Kind.Runtime_Error)
		testing.expect_value(t, result.runtime_error.kind, Runtime_Error_Kind.Cannot_Index_With_String)
		testing.expect_value(t, result.runtime_error.input_kind, expected_kinds[index])
		testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Runtime_Error)
		testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	}
	destroy_program_test(t, &compiled)
}

@(test)
runtime_error_owns_exact_length_delimited_key_through_replay :: proc(t: ^testing.T) {
	keys := [3]string{"a", "b", "a\x00b"}
	for key in keys {
		instructions := [1]program.Instruction{{opcode = .Field, operands_count = 1}}
		operands := [1]program.Operand{text_operand(0, u32(len(key)))}
		compiled: program.Program
		build_program(t, &compiled, instructions[:], operands[:], key, 0)
		input := value.number_value(1)
		evaluator: Evaluator
		testing.expect_value(
			t,
			init_evaluator(&evaluator, &compiled, &input, context.allocator).kind,
			Init_Error_Kind.None,
		)
		result := step_evaluator(&evaluator)
		testing.expect_value(t, result.kind, Step_Kind.Runtime_Error)
		testing.expect_value(t, result.runtime_error.key, key)
		// Terminal cleanup ended the Program borrow. The error key remains
		// independently evaluator-owned after the Program is destroyed.
		destroy_program_test(t, &compiled)
		testing.expect_value(t, result.runtime_error.key, key)
		replayed := step_evaluator(&evaluator)
		testing.expect_value(t, replayed.kind, Step_Kind.Runtime_Error)
		testing.expect_value(t, replayed.runtime_error.key, key)
		testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	}
}

@(private)
terminal_cleanup_failure_state :: proc(rejections: int) -> fail_allocator_state {
	return {
		backing = context.allocator,
		fail_at = -1,
		fail_free_at = 1,
		reject_free_count = rejections,
		free_error = .Invalid_Pointer,
	}
}

@(private)
expect_runtime_payload :: proc(
	t: ^testing.T,
	result: Step_Result,
	key: string,
	span: program.Source_Span,
) {
	testing.expect_value(t, result.kind, Step_Kind.Runtime_Error)
	testing.expect_value(
		t, result.runtime_error.kind, Runtime_Error_Kind.Cannot_Index_With_String,
	)
	testing.expect_value(t, result.runtime_error.input_kind, value.Kind.Number)
	testing.expect_value(t, result.runtime_error.span, span)
	testing.expect_value(t, result.runtime_error.key, key)
}

@(private)
runtime_terminal_survives_repeated_cleanup_failures :: proc(
	t: ^testing.T,
	key: string,
) {
	scope: allocation_scope
	allocation_scope_begin(&scope)
	span := program.Source_Span{start = 17, end = 29}
	instructions := [1]program.Instruction{{
		opcode = .Field,
		operands_count = 1,
		span = span,
	}}
	operands := [1]program.Operand{text_operand(0, u32(len(key)))}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], operands[:], key, 0)

	free_state := terminal_cleanup_failure_state(3)
	input := value.number_value(73)
	evaluator: Evaluator
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			{procedure = fail_allocator_proc, data = &free_state},
		).kind,
		Init_Error_Kind.None,
	)

	// The terminal step and two destroy attempts all reject the same arena free.
	// None may retire or zero the separately stored terminal diagnostic.
	first := step_evaluator(&evaluator)
	testing.expect_value(t, first.kind, Step_Kind.Resource_Error)
	testing.expect_value(t, first.resource_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(
		t, destroy_evaluator(&evaluator), runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(
		t, destroy_evaluator(&evaluator), runtime.Allocator_Error.Invalid_Pointer,
	)

	terminal := step_evaluator(&evaluator)
	expect_runtime_payload(t, terminal, key, span)
	testing.expect_value(t, free_state.reject_free_count, 0)
	testing.expect_value(t, free_state.free_calls, 4)

	// Successful arena retirement ended the Program borrow. The exact key bytes,
	// including zero length or embedded NUL, remain evaluator-owned for replay.
	destroy_program_test(t, &compiled)
	expect_runtime_payload(t, step_evaluator(&evaluator), key, span)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	testing.expect_value(t, free_state.free_calls, 4+(1 if len(key) > 0 else 0))
	allocation_scope_end(t, &scope)
}

@(test)
runtime_terminal_payload_survives_repeated_step_and_destroy_cleanup_failures :: proc(
	t: ^testing.T,
) {
	runtime_terminal_survives_repeated_cleanup_failures(t, "")
	runtime_terminal_survives_repeated_cleanup_failures(t, "a\x00b")
}

@(test)
done_misuse_and_early_destroy_survive_repeated_storage_cleanup_failures :: proc(
	t: ^testing.T,
) {
	scope: allocation_scope
	allocation_scope_begin(&scope)
	instructions := [1]program.Instruction{{opcode = .Identity}}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], nil, "", 0)

	// Done remains pending while step and destroy alternate across three rejected
	// arena frees, then becomes a stable replay result.
	free_state := terminal_cleanup_failure_state(3)
	input := value.number_value(1)
	evaluator: Evaluator
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator, &compiled, &input,
			{procedure = fail_allocator_proc, data = &free_state},
		).kind,
		Init_Error_Kind.None,
	)
	output := step_take(t, &evaluator)
	expect_number(t, &output, 1)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Resource_Error)
	testing.expect_value(
		t, destroy_evaluator(&evaluator), runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Resource_Error)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))

	// A malformed-Program Misuse payload likewise survives storage failures and
	// repeated destruction without being reset to None.
	free_state = terminal_cleanup_failure_state(3)
	input = value.number_value(2)
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator, &compiled, &input,
			{procedure = fail_allocator_proc, data = &free_state},
		).kind,
		Init_Error_Kind.None,
	)
	compiled.instructions[0].opcode = program.Opcode(255)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Resource_Error)
	testing.expect_value(
		t, destroy_evaluator(&evaluator), runtime.Allocator_Error.Invalid_Pointer,
	)
	misuse_retry := step_evaluator(&evaluator)
	testing.expect_value(t, misuse_retry.kind, Step_Kind.Resource_Error)
	misuse := step_evaluator(&evaluator)
	testing.expect_value(t, misuse.kind, Step_Kind.Misuse)
	testing.expect_value(t, misuse.misuse, Misuse_Kind.Malformed_Program)
	testing.expect_value(t, step_evaluator(&evaluator).misuse, Misuse_Kind.Malformed_Program)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	compiled.instructions[0].opcode = .Identity

	// Early destroy has already retired its input before arena cleanup fails.
	// A later step deterministically continues from that cancellation as Done.
	free_state = terminal_cleanup_failure_state(3)
	input = nested_heap_value(t, context.allocator, false)
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator, &compiled, &input,
			{procedure = fail_allocator_proc, data = &free_state},
		).kind,
		Init_Error_Kind.None,
	)
	testing.expect_value(
		t, destroy_evaluator(&evaluator), runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Resource_Error)
	testing.expect_value(
		t, destroy_evaluator(&evaluator), runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))

	destroy_program_test(t, &compiled)
	allocation_scope_end(t, &scope)

	invalid: Evaluator
	testing.expect_value(t, step_evaluator(&invalid).misuse, Misuse_Kind.Invalid_Evaluator)
	testing.expect_value(t, destroy_evaluator(&invalid), runtime.Allocator_Error(nil))
}

@(test)
runtime_error_key_allocation_and_destroy_cleanup_retry_without_dangling :: proc(t: ^testing.T) {
	instructions := [1]program.Instruction{{opcode = .Field, operands_count = 1}}
	operands := [1]program.Operand{text_operand(0, 3)}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], operands[:], "key", 0)

	allocation_failure := fail_allocator_state{backing = context.allocator, fail_at = 2}
	input := value.number_value(1)
	evaluator: Evaluator
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			runtime.Allocator{procedure = fail_allocator_proc, data = &allocation_failure},
		).kind,
		Init_Error_Kind.None,
	)
	resource := step_evaluator(&evaluator)
	testing.expect_value(t, resource.kind, Step_Kind.Resource_Error)
	testing.expect_value(t, resource.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	runtime_result := step_evaluator(&evaluator)
	testing.expect_value(t, runtime_result.kind, Step_Kind.Runtime_Error)
	testing.expect_value(t, runtime_result.runtime_error.key, "key")
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))

	free_failure := fail_allocator_state{
		backing = context.allocator,
		fail_at = -1,
		fail_free_at = 2,
		reject_free_count = 1,
		free_error = .Invalid_Pointer,
	}
	input = value.number_value(2)
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			runtime.Allocator{procedure = fail_allocator_proc, data = &free_failure},
		).kind,
		Init_Error_Kind.None,
	)
	runtime_result = step_evaluator(&evaluator)
	testing.expect_value(t, runtime_result.kind, Step_Kind.Runtime_Error)
	testing.expect_value(t, runtime_result.runtime_error.key, "key")
	testing.expect_value(
		t, destroy_evaluator(&evaluator), runtime.Allocator_Error.Invalid_Pointer,
	)
	// Failed destruction preserves the exact error-key owner and terminal view.
	replayed := step_evaluator(&evaluator)
	testing.expect_value(t, replayed.kind, Step_Kind.Runtime_Error)
	testing.expect_value(t, replayed.runtime_error.key, "key")
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	testing.expect_value(t, free_failure.reject_free_count, 0)

	optional_instructions := [2]program.Instruction{
		{opcode = .Field, operands_count = 1},
		{opcode = .Optional, operands_start = 1, operands_count = 1},
	}
	optional_operands := [2]program.Operand{text_operand(0, 3), instruction_operand(0)}
	destroy_program_test(t, &compiled)
	build_program(
		t, &compiled, optional_instructions[:], optional_operands[:], "key", 1,
	)
	free_failure = {
		backing = context.allocator,
		fail_at = -1,
		fail_free_at = 1,
		reject_free_count = 1,
		free_error = .Invalid_Pointer,
	}
	input = value.number_value(3)
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			runtime.Allocator{procedure = fail_allocator_proc, data = &free_failure},
		).kind,
		Init_Error_Kind.None,
	)
	resource = step_evaluator(&evaluator)
	testing.expect_value(t, resource.kind, Step_Kind.Resource_Error)
	testing.expect_value(t, resource.resource_error, runtime.Allocator_Error.Invalid_Pointer)
	// Optional cannot discard a failed key cleanup; retry completes suppression.
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	testing.expect_value(t, free_failure.reject_free_count, 0)
	destroy_program_test(t, &compiled)
}

@(private)
malformed_propagation_case :: proc(
	t: ^testing.T,
	postfix_field: bool,
	inject_cleanup_failure: bool,
) {
	scope: allocation_scope
	allocation_scope_begin(&scope)
	value_allocator_state := fail_allocator_state{
		backing = context.allocator,
		fail_at = -1,
		fail_free_at = 1,
		reject_free_count = 0,
		free_error = .Invalid_Pointer,
	}
	if inject_cleanup_failure do value_allocator_state.reject_free_count = 1
	value_allocator := runtime.Allocator{
		procedure = fail_allocator_proc,
		data = &value_allocator_state,
	}

	compiled: program.Program
	input: value.Value
	evaluator: Evaluator
	if !postfix_field {
		instructions := [3]program.Instruction{
			{opcode = .Identity},
			{opcode = .Identity},
			{opcode = .Sequence, operands_count = 2},
		}
		operands := [2]program.Operand{instruction_operand(0), instruction_operand(1)}
		build_program(t, &compiled, instructions[:], operands[:], "", 2)
		input = nested_heap_value(t, value_allocator, false)
		testing.expect_value(
			t,
			init_evaluator(&evaluator, &compiled, &input, context.allocator).kind,
			Init_Error_Kind.None,
		)
		// Corrupt only the live Sequence right operand after initialization.
		compiled.operands[1].kind = .Text
	} else {
		instructions := [3]program.Instruction{
			{opcode = .Identity},
			{opcode = .Fork, operands_count = 2},
			{opcode = .Field, operands_start = 2, operands_count = 2},
		}
		operands := [4]program.Operand{
			instruction_operand(0), instruction_operand(0),
			instruction_operand(1), text_operand(0, 3),
		}
		build_program(t, &compiled, instructions[:], operands[:], "key", 2)
		input = nested_heap_value(t, value_allocator, true)
		testing.expect_value(
			t,
			init_evaluator(&evaluator, &compiled, &input, context.allocator).kind,
			Init_Error_Kind.None,
		)
		first := step_take(t, &evaluator)
		testing.expect_value(t, value.kind_of(&first), value.Kind.Array)
		testing.expect_value(t, value.destroy_value(&first), runtime.Allocator_Error(nil))
		// The second child result reaches Field_Child_Active after this live
		// mutation makes construction of its field-only frame invalid.
		compiled.operands[3].kind = .Instruction
	}

	first_terminal := step_evaluator(&evaluator)
	misuse := first_terminal
	if inject_cleanup_failure {
		testing.expect_value(t, first_terminal.kind, Step_Kind.Resource_Error)
		testing.expect_value(
			t, first_terminal.resource_error, runtime.Allocator_Error.Invalid_Pointer,
		)
		misuse = step_evaluator(&evaluator)
	}
	testing.expect_value(t, misuse.kind, Step_Kind.Misuse)
	testing.expect_value(t, misuse.misuse, Misuse_Kind.Malformed_Program)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Misuse)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	testing.expect_value(t, value_allocator_state.free_failed, inject_cleanup_failure)
	testing.expect_value(t, value_allocator_state.reject_free_count, 0)
	destroy_program_test(t, &compiled)
	allocation_scope_end(t, &scope)
}

@(test)
live_program_mutation_retires_sequence_and_field_outputs_before_misuse :: proc(t: ^testing.T) {
	cleanup_modes := [2]bool{false, true}
	for inject_cleanup_failure in cleanup_modes {
		malformed_propagation_case(t, false, inject_cleanup_failure)
		malformed_propagation_case(t, true, inject_cleanup_failure)
	}
}

@(private)
expect_malformed_terminal :: proc(t: ^testing.T, evaluator: ^Evaluator) {
	result := step_evaluator(evaluator)
	testing.expect_value(t, result.kind, Step_Kind.Misuse)
	testing.expect_value(t, result.misuse, Misuse_Kind.Malformed_Program)
	replayed := step_evaluator(evaluator)
	testing.expect_value(t, replayed.kind, Step_Kind.Misuse)
	testing.expect_value(t, replayed.misuse, Misuse_Kind.Malformed_Program)
	testing.expect_value(t, destroy_evaluator(evaluator), runtime.Allocator_Error(nil))
}

@(test)
suspended_composites_revalidate_saved_instruction_and_operands :: proc(t: ^testing.T) {
	identity_pair := [2]program.Instruction{{opcode = .Identity}, {opcode = .Identity}}
	fork_operands := [2]program.Operand{instruction_operand(0), instruction_operand(1)}

	// The left and right Fork continuations are independently resumable.
	for outputs_before_mutation in 1..=2 {
		instructions := [3]program.Instruction{
			identity_pair[0], identity_pair[1],
			{opcode = .Fork, operands_count = 2},
		}
		compiled: program.Program
		build_program(t, &compiled, instructions[:], fork_operands[:], "", 2)
		input := value.number_value(10)
		evaluator: Evaluator
		testing.expect_value(
			t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind,
			Init_Error_Kind.None,
		)
		for _ in 0..<outputs_before_mutation {
			output := step_take(t, &evaluator)
			expect_number(t, &output, 10)
		}
		storage := storage_of(&evaluator)
		expected_phase := frame_phase.Fork_Left_Active
		if outputs_before_mutation == 2 do expected_phase = .Fork_Right_Active
		testing.expect_value(t, storage.frames[0].phase, expected_phase)
		if outputs_before_mutation == 1 {
			compiled.instructions[2].opcode = program.Opcode(255)
		} else {
			// This remains a structurally valid Fork operand, but differs from the
			// sealed operand that established the suspended continuation.
			compiled.operands[0].instruction = program.Instruction_Index(1)
		}
		expect_malformed_terminal(t, &evaluator)
		destroy_program_test(t, &compiled)
	}

	// Sequence has consumed the left result and suspended while its right
	// activation owns that result. A valid replacement right operand is misuse.
	sequence_instructions := [4]program.Instruction{
		identity_pair[0], identity_pair[1],
		{opcode = .Fork, operands_count = 2},
		{opcode = .Sequence, operands_start = 2, operands_count = 2},
	}
	sequence_operands := [4]program.Operand{
		instruction_operand(0), instruction_operand(1),
		instruction_operand(2), instruction_operand(0),
	}
	sequence_program: program.Program
	build_program(
		t, &sequence_program, sequence_instructions[:], sequence_operands[:], "", 3,
	)
	sequence_input := value.number_value(11)
	sequence_evaluator: Evaluator
	testing.expect_value(
		t,
		init_evaluator(
			&sequence_evaluator, &sequence_program, &sequence_input, context.allocator,
		).kind,
		Init_Error_Kind.None,
	)
	sequence_output := step_take(t, &sequence_evaluator)
	expect_number(t, &sequence_output, 11)
	sequence_storage := storage_of(&sequence_evaluator)
	testing.expect_value(
		t, sequence_storage.frames[0].phase, frame_phase.Sequence_Right_Active,
	)
	sequence_program.operands[3].instruction = program.Instruction_Index(1)
	expect_malformed_terminal(t, &sequence_evaluator)
	destroy_program_test(t, &sequence_program)

	// Postfix Field suspends both its child generator and its field-only result.
	field_instructions := [3]program.Instruction{
		{opcode = .Identity},
		{opcode = .Fork, operands_count = 2},
		{opcode = .Field, operands_start = 2, operands_count = 2},
	}
	field_operands := [4]program.Operand{
		instruction_operand(0), instruction_operand(0),
		instruction_operand(1), text_operand(0, 1),
	}
	field_program: program.Program
	build_program(t, &field_program, field_instructions[:], field_operands[:], "a", 2)
	field_input := sample_object(t)
	field_evaluator: Evaluator
	testing.expect_value(
		t,
		init_evaluator(&field_evaluator, &field_program, &field_input, context.allocator).kind,
		Init_Error_Kind.None,
	)
	field_output := step_take(t, &field_evaluator)
	testing.expect_value(t, value.kind_of(&field_output), value.Kind.Object)
	testing.expect_value(t, value.destroy_value(&field_output), runtime.Allocator_Error(nil))
	field_storage := storage_of(&field_evaluator)
	testing.expect_value(
		t, field_storage.frames[0].phase, frame_phase.Field_Result_Active,
	)
	field_program.operands[2].instruction = program.Instruction_Index(0)
	expect_malformed_terminal(t, &field_evaluator)
	destroy_program_test(t, &field_program)
}

@(test)
complete_program_seal_catches_dormant_fork_child_and_postfix_field_text :: proc(
	t: ^testing.T,
) {
	// The right child has not been activated. Its opcode changes while both
	// immediate Fork operands and the Fork instruction remain byte-for-byte
	// unchanged.
	fork_instructions := [4]program.Instruction{
		{opcode = .Identity},
		{opcode = .Identity},
		{opcode = .Parenthesized, operands_start = 0, operands_count = 1},
		{opcode = .Fork, operands_start = 1, operands_count = 2},
	}
	fork_operands := [3]program.Operand{
		instruction_operand(1),
		instruction_operand(0), instruction_operand(2),
	}
	compiled: program.Program
	build_program(t, &compiled, fork_instructions[:], fork_operands[:], "", 3)
	input := value.number_value(31)
	evaluator: Evaluator
	testing.expect_value(
		t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind,
		Init_Error_Kind.None,
	)
	left := step_take(t, &evaluator)
	expect_number(t, &left, 31)
	compiled.instructions[2].opcode = .Optional
	expect_malformed_terminal(t, &evaluator)
	destroy_program_test(t, &compiled)

	// A postfix Field borrows its key bytes. Byte and logical-length mutations
	// are independently rejected before the suspended child can resume.
	text_mutations := [2]bool{false, true}
	for mutate_length in text_mutations {
		field_instructions := [3]program.Instruction{
			{opcode = .Identity},
			{opcode = .Fork, operands_start = 0, operands_count = 2},
			{opcode = .Field, operands_start = 2, operands_count = 2},
		}
		field_operands := [4]program.Operand{
			instruction_operand(0), instruction_operand(0),
			instruction_operand(1), text_operand(0, 2),
		}
		build_program(t, &compiled, field_instructions[:], field_operands[:], "ab", 2)
		field_input := sample_object(t)
		testing.expect_value(
			t,
			init_evaluator(&evaluator, &compiled, &field_input, context.allocator).kind,
			Init_Error_Kind.None,
		)
		first := step_take(t, &evaluator)
		expect_null(t, &first)
		if mutate_length {
			compiled.operands[3].text_count = 1
		} else {
			compiled.text[1] = 'c'
		}
		expect_malformed_terminal(t, &evaluator)
		destroy_program_test(t, &compiled)
	}
}

@(private)
seal_pending_state :: enum u8 {
	Output,
	Runtime_Error_Work,
	Terminal_Cleanup_Retry,
}

@(private)
seal_mutation :: enum u8 {
	Has_Root_True_To_False,
	Root,
	Memory_Length,
	Instruction_Length,
	Instruction_Opcode,
	Instruction_Operands_Start,
	Instruction_Operands_Count,
	Instruction_Span_Start,
	Instruction_Span_End,
	Operand_Length,
	Operand_Kind,
	Operand_Instruction_Value,
	Operand_Text_Start,
	Operand_Text_Count,
	Text_Byte,
	Text_Slice_Length,
}

@(private)
apply_seal_mutation :: proc(compiled: ^program.Program, mutation: seal_mutation) {
	switch mutation {
	case .Has_Root_True_To_False:
		compiled.has_root = false
	case .Root:
		compiled.root = 0
	case .Memory_Length:
		compiled.memory = compiled.memory[:len(compiled.memory)-1]
	case .Instruction_Length:
		compiled.instructions = compiled.instructions[:2]
	case .Instruction_Opcode:
		compiled.instructions[1].opcode = .Identity
	case .Instruction_Operands_Start:
		compiled.instructions[1].operands_start = 1
	case .Instruction_Operands_Count:
		compiled.instructions[1].operands_count = 0
	case .Instruction_Span_Start:
		compiled.instructions[1].span.start = 9
	case .Instruction_Span_End:
		compiled.instructions[1].span.end = 12
	case .Operand_Length:
		compiled.operands = compiled.operands[:2]
	case .Operand_Kind:
		compiled.operands[0].kind = .Instruction
	case .Operand_Instruction_Value:
		compiled.operands[2].instruction = 0
	case .Operand_Text_Start:
		compiled.operands[0].text_start = 1
	case .Operand_Text_Count:
		compiled.operands[0].text_count = 0
	case .Text_Byte:
		compiled.text[0] = 'b'
	case .Text_Slice_Length:
		compiled.text = compiled.text[:0]
	}
}

@(private)
restore_seal_mutation :: proc(compiled: ^program.Program, mutation: seal_mutation) {
	// Restore public views before destruction so allocator cleanup never consumes
	// a caller-corrupted descriptor.
	switch mutation {
	case .Has_Root_True_To_False:
		compiled.has_root = true
	case .Root:
		compiled.root = 2
	case .Memory_Length, .Instruction_Length, .Operand_Length, .Text_Slice_Length:
		return
	case .Instruction_Opcode:
		compiled.instructions[1].opcode = .Field
	case .Instruction_Operands_Start:
		compiled.instructions[1].operands_start = 0
	case .Instruction_Operands_Count:
		compiled.instructions[1].operands_count = 1
	case .Instruction_Span_Start:
		compiled.instructions[1].span.start = 10
	case .Instruction_Span_End:
		compiled.instructions[1].span.end = 11
	case .Operand_Kind:
		compiled.operands[0].kind = .Text
	case .Operand_Instruction_Value:
		compiled.operands[2].instruction = 1
	case .Operand_Text_Start:
		compiled.operands[0].text_start = 0
	case .Operand_Text_Count:
		compiled.operands[0].text_count = 1
	case .Text_Byte:
		compiled.text[0] = 'a'
	}
}

@(private)
program_seal_pending_case :: proc(
	t: ^testing.T,
	pending_state: seal_pending_state,
	mutation: seal_mutation,
) {
	instructions := [3]program.Instruction{
		{opcode = .Identity, span = {start = 1, end = 2}},
		{opcode = .Field, operands_start = 0, operands_count = 1, span = {start = 10, end = 11}},
		{opcode = .Fork, operands_start = 1, operands_count = 2, span = {start = 20, end = 21}},
	}
	operands := [3]program.Operand{
		text_operand(0, 1),
		instruction_operand(0), instruction_operand(1),
	}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], operands[:], "a", 2)
	original_instructions := compiled.instructions
	original_operands := compiled.operands
	original_text := compiled.text
	original_memory := compiled.memory

	evaluator: Evaluator
	allocator_state: fail_allocator_state
	allocator := context.allocator
	input: value.Value
	switch pending_state {
	case .Output:
		input = value.number_value(40)
	case .Runtime_Error_Work:
		allocator_state = {backing = context.allocator, fail_at = 2}
		allocator = {procedure = fail_allocator_proc, data = &allocator_state}
		input = value.number_value(41)
	case .Terminal_Cleanup_Retry:
		allocator_state = {
			backing = context.allocator,
			fail_at = -1,
			fail_free_at = 1,
			reject_free_count = 1,
			free_error = .Invalid_Argument,
		}
		allocator = {procedure = fail_allocator_proc, data = &allocator_state}
		input = sample_object(t)
	}
	testing.expect_value(
		t, init_evaluator(&evaluator, &compiled, &input, allocator).kind,
		Init_Error_Kind.None,
	)

	first := step_take(t, &evaluator)
	if pending_state == .Terminal_Cleanup_Retry {
		testing.expect_value(t, value.kind_of(&first), value.Kind.Object)
		testing.expect_value(t, value.destroy_value(&first), runtime.Allocator_Error(nil))
		second := step_take(t, &evaluator)
		testing.expect_value(t, value.kind_of(&second), value.Kind.Object)
		testing.expect_value(t, value.destroy_value(&second), runtime.Allocator_Error(nil))
		cleanup := step_evaluator(&evaluator)
		testing.expect_value(t, cleanup.kind, Step_Kind.Resource_Error)
		testing.expect_value(
			t, cleanup.resource_error, runtime.Allocator_Error.Invalid_Argument,
		)
		testing.expect_value(t, allocator_state.free_calls, 1)
		testing.expect_value(t, allocator_state.reject_free_count, 0)
	} else {
		expect_number(t, &first, 40 if pending_state == .Output else 41)
		if pending_state == .Runtime_Error_Work {
			resource := step_evaluator(&evaluator)
			testing.expect_value(t, resource.kind, Step_Kind.Resource_Error)
			testing.expect_value(
				t, resource.resource_error, runtime.Allocator_Error.Out_Of_Memory,
			)
			testing.expect_value(t, allocator_state.failed, true)
		}
	}

	apply_seal_mutation(&compiled, mutation)
	expect_malformed_terminal(t, &evaluator)
	if pending_state == .Terminal_Cleanup_Retry {
		testing.expect_value(t, allocator_state.free_calls, 2)
	}
	compiled.instructions = original_instructions
	compiled.operands = original_operands
	compiled.text = original_text
	compiled.memory = original_memory
	restore_seal_mutation(&compiled, mutation)
	destroy_program_test(t, &compiled)
}

@(test)
complete_program_seal_mutation_matrix_preserves_pending_order_and_ownership :: proc(
	t: ^testing.T,
) {
	pending_states := [3]seal_pending_state{
		.Output, .Runtime_Error_Work, .Terminal_Cleanup_Retry,
	}
	mutations := [16]seal_mutation{
		.Has_Root_True_To_False,
		.Root,
		.Memory_Length,
		.Instruction_Length,
		.Instruction_Opcode,
		.Instruction_Operands_Start,
		.Instruction_Operands_Count,
		.Instruction_Span_Start,
		.Instruction_Span_End,
		.Operand_Length,
		.Operand_Kind,
		.Operand_Instruction_Value,
		.Operand_Text_Start,
		.Operand_Text_Count,
		.Text_Byte,
		.Text_Slice_Length,
	}
	for pending_state in pending_states {
		for mutation in mutations {
			program_seal_pending_case(t, pending_state, mutation)
		}
	}
}

@(test)
complete_program_revalidation_is_allocation_free_per_step :: proc(t: ^testing.T) {
	depth := 255
	instructions := make([]program.Instruction, depth+1)
	operands := make([]program.Operand, depth*2)
	instructions[0] = {opcode = .Identity}
	for index in 1..=depth {
		start := (index-1)*2
		instructions[index] = {
			opcode = .Fork,
			operands_start = program.Operand_Index(start),
			operands_count = 2,
		}
		operands[start] = instruction_operand(index-1)
		operands[start+1] = instruction_operand(0)
	}
	compiled: program.Program
	build_program(t, &compiled, instructions, operands, "", depth)
	delete(instructions)
	delete(operands)

	allocation_state := fail_allocator_state{backing = context.allocator, fail_at = 2}
	input := value.number_value(51)
	evaluator: Evaluator
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			{procedure = fail_allocator_proc, data = &allocation_state},
		).kind,
		Init_Error_Kind.None,
	)
	for _ in 0..=depth {
		output := step_take(t, &evaluator)
		expect_number(t, &output, 51)
	}
	testing.expect_value(t, allocation_state.call, 1)
	testing.expect_value(t, allocation_state.failed, false)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)
}

@(test)
suspended_unary_revalidates_instruction_operand_and_runtime_boundary :: proc(t: ^testing.T) {
	// A structurally valid unary operand replacement is rejected while a later
	// child output is propagating through the suspended continuation.
	output_instructions := [4]program.Instruction{
		{opcode = .Identity},
		{opcode = .Identity},
		{opcode = .Fork, operands_count = 2},
		{opcode = .Parenthesized, operands_start = 2, operands_count = 1},
	}
	output_operands := [3]program.Operand{
		instruction_operand(0), instruction_operand(1), instruction_operand(2),
	}
	compiled: program.Program
	build_program(t, &compiled, output_instructions[:], output_operands[:], "", 3)
	input := value.number_value(20)
	evaluator: Evaluator
	testing.expect_value(
		t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind,
		Init_Error_Kind.None,
	)
	first := step_take(t, &evaluator)
	expect_number(t, &first, 20)
	compiled.operands[2].instruction = program.Instruction_Index(0)
	expect_malformed_terminal(t, &evaluator)
	destroy_program_test(t, &compiled)

	// Exhaustion must perform the same exact check after a unary child has
	// already yielded its only result.
	exhaustion_instructions := [3]program.Instruction{
		{opcode = .Identity},
		{opcode = .Identity},
		{opcode = .Optional, operands_count = 1},
	}
	exhaustion_operands := [1]program.Operand{instruction_operand(0)}
	build_program(
		t, &compiled, exhaustion_instructions[:], exhaustion_operands[:], "", 2,
	)
	input = value.number_value(21)
	testing.expect_value(
		t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind,
		Init_Error_Kind.None,
	)
	first = step_take(t, &evaluator)
	expect_number(t, &first, 21)
	compiled.operands[0].instruction = program.Instruction_Index(1)
	expect_malformed_terminal(t, &evaluator)
	destroy_program_test(t, &compiled)

	// The child emits once and then raises. Mutating Parenthesized to Optional
	// must not newly suppress that later error; the inverse mutation must not
	// newly expose it. Both opcode changes are malformed terminal state.
	runtime_instructions := [4]program.Instruction{
		{opcode = .Identity},
		{opcode = .Field, operands_count = 1},
		{opcode = .Fork, operands_start = 1, operands_count = 2},
		{opcode = .Parenthesized, operands_start = 3, operands_count = 1},
	}
	runtime_operands := [4]program.Operand{
		text_operand(0, 1),
		instruction_operand(0), instruction_operand(1),
		instruction_operand(2),
	}
	original_opcodes := [2]program.Opcode{.Parenthesized, .Optional}
	for original_opcode in original_opcodes {
		runtime_instructions[3].opcode = original_opcode
		build_program(
			t, &compiled, runtime_instructions[:], runtime_operands[:], "a", 3,
		)
		input = value.number_value(22)
		testing.expect_value(
			t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind,
			Init_Error_Kind.None,
		)
		first = step_take(t, &evaluator)
		expect_number(t, &first, 22)
		if original_opcode == .Parenthesized do compiled.instructions[3].opcode = .Optional
		else do compiled.instructions[3].opcode = .Parenthesized
		expect_malformed_terminal(t, &evaluator)
		destroy_program_test(t, &compiled)
	}

	// If Optional suppression first stops on resource cleanup, a mutation before
	// retry is still checked before suppression resumes. The retry retires both
	// the child Value and the evaluator-owned runtime-error key before Misuse.
	retry_instructions := [2]program.Instruction{
		{opcode = .Field, operands_count = 1},
		{opcode = .Optional, operands_start = 1, operands_count = 1},
	}
	retry_operands := [2]program.Operand{text_operand(0, 1), instruction_operand(0)}
	build_program(t, &compiled, retry_instructions[:], retry_operands[:], "a", 1)
	key_free_state := fail_allocator_state{
		backing = context.allocator,
		fail_at = -1,
		fail_free_at = 1,
		reject_free_count = 1,
		free_error = .Invalid_Argument,
	}
	input = value.number_value(23)
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			runtime.Allocator{procedure = fail_allocator_proc, data = &key_free_state},
		).kind,
		Init_Error_Kind.None,
	)
	resource := step_evaluator(&evaluator)
	testing.expect_value(t, resource.kind, Step_Kind.Resource_Error)
	testing.expect_value(
		t, resource.resource_error, runtime.Allocator_Error.Invalid_Argument,
	)
	compiled.instructions[1].opcode = .Parenthesized
	expect_malformed_terminal(t, &evaluator)
	testing.expect_value(t, key_free_state.reject_free_count, 0)
	destroy_program_test(t, &compiled)
}

@(test)
terminal_cleanup_retry_records_destroyed_program_lifetime :: proc(t: ^testing.T) {
	instructions := [1]program.Instruction{{opcode = .Identity}}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], nil, "", 0)
	free_state := fail_allocator_state{
		backing = context.allocator,
		fail_at = -1,
		fail_free_at = 1,
		reject_free_count = 2,
		free_error = .Invalid_Argument,
	}
	input := value.number_value(12)
	evaluator: Evaluator
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			runtime.Allocator{procedure = fail_allocator_proc, data = &free_state},
		).kind,
		Init_Error_Kind.None,
	)
	output := step_take(t, &evaluator)
	expect_number(t, &output, 12)

	first_cleanup := step_evaluator(&evaluator)
	testing.expect_value(t, first_cleanup.kind, Step_Kind.Resource_Error)
	testing.expect_value(
		t, first_cleanup.resource_error, runtime.Allocator_Error.Invalid_Argument,
	)
	destroy_program_test(t, &compiled)

	// The first retry records the lifetime violation before its second cleanup
	// failure. The next retry releases the arena exactly once and reveals Misuse.
	second_cleanup := step_evaluator(&evaluator)
	testing.expect_value(t, second_cleanup.kind, Step_Kind.Resource_Error)
	testing.expect_value(
		t, second_cleanup.resource_error, runtime.Allocator_Error.Invalid_Argument,
	)
	misuse := step_evaluator(&evaluator)
	testing.expect_value(t, misuse.kind, Step_Kind.Misuse)
	testing.expect_value(t, misuse.misuse, Misuse_Kind.Invalid_Program_Lifetime)
	testing.expect_value(t, free_state.free_calls, 3)
	testing.expect_value(t, free_state.reject_free_count, 0)

	free_state.retired = true
	replayed := step_evaluator(&evaluator)
	testing.expect_value(t, replayed.kind, Step_Kind.Misuse)
	testing.expect_value(t, replayed.misuse, Misuse_Kind.Invalid_Program_Lifetime)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	testing.expect(t, !free_state.called_while_retired)
}

@(test)
optional_suppresses_runtime_only_and_preserves_prior_outputs :: proc(t: ^testing.T) {
	// Optional(Field a) is .a? and Fork(Identity, Field a) is .,.a.
	instructions := [4]program.Instruction{
		{opcode = .Identity},
		{opcode = .Field, operands_start = 0, operands_count = 1},
		{opcode = .Optional, operands_start = 1, operands_count = 1},
		{opcode = .Fork, operands_start = 2, operands_count = 2},
	}
	operands := [4]program.Operand{
		text_operand(0, 1),
		instruction_operand(1),
		instruction_operand(0), instruction_operand(1),
	}

	optional_program: program.Program
	build_program(t, &optional_program, instructions[:3], operands[:2], "a", 2)
	bad := value.number_value(9)
	evaluator: Evaluator
	testing.expect_value(t, init_evaluator(&evaluator, &optional_program, &bad, context.allocator).kind, Init_Error_Kind.None)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &optional_program)

	fork_program: program.Program
	// Rebase operand starts because this Program includes all four instructions.
	build_program(t, &fork_program, instructions[:], operands[:], "a", 3)
	bad = value.number_value(9)
	testing.expect_value(t, init_evaluator(&evaluator, &fork_program, &bad, context.allocator).kind, Init_Error_Kind.None)
	first := step_take(t, &evaluator)
	expect_number(t, &first, 9)
	later := step_evaluator(&evaluator)
	testing.expect_value(t, later.kind, Step_Kind.Runtime_Error)
	testing.expect_value(t, later.runtime_error.input_kind, value.Kind.Number)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &fork_program)

	// Optional(Fork(Identity, Field a)) emits the first result and suppresses
	// only the later runtime error, preserving the already transferred output.
	optional_fork_instructions := [4]program.Instruction{
		{opcode = .Identity},
		{opcode = .Field, operands_start = 0, operands_count = 1},
		{opcode = .Fork, operands_start = 1, operands_count = 2},
		{opcode = .Optional, operands_start = 3, operands_count = 1},
	}
	optional_fork_operands := [4]program.Operand{
		text_operand(0, 1),
		instruction_operand(0), instruction_operand(1),
		instruction_operand(2),
	}
	build_program(t, &fork_program, optional_fork_instructions[:], optional_fork_operands[:], "a", 3)
	bad = value.number_value(11)
	testing.expect_value(t, init_evaluator(&evaluator, &fork_program, &bad, context.allocator).kind, Init_Error_Kind.None)
	prior := step_take(t, &evaluator)
	expect_number(t, &prior, 11)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &fork_program)

	// A Value cleanup Free failure remains visible through Optional and retries.
	build_program(t, &optional_program, instructions[:3], operands[:2], "a", 2)
	value_free_state := fail_allocator_state{
		backing = context.allocator,
		fail_at = -1,
		fail_free_at = 1,
		reject_free_count = 1,
		free_error = .Invalid_Argument,
	}
	bad, _ = value.string_value(
		"not-an-object",
		runtime.Allocator{procedure = fail_allocator_proc, data = &value_free_state},
	)
	testing.expect_value(t, init_evaluator(&evaluator, &optional_program, &bad, context.allocator).kind, Init_Error_Kind.None)
	resource := step_evaluator(&evaluator)
	testing.expect_value(t, resource.kind, Step_Kind.Resource_Error)
	testing.expect_value(t, resource.resource_error, runtime.Allocator_Error.Invalid_Argument)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &optional_program)

	// An error in the downstream right side is not a child of Optional and is
	// therefore not suppressed: (.?) | .a on a number still errors.
	downstream_instructions := [4]program.Instruction{
		{opcode = .Identity},
		{opcode = .Optional, operands_start = 0, operands_count = 1},
		{opcode = .Field, operands_start = 1, operands_count = 1},
		{opcode = .Sequence, operands_start = 2, operands_count = 2},
	}
	downstream_operands := [4]program.Operand{
		instruction_operand(0),
		text_operand(0, 1),
		instruction_operand(1), instruction_operand(2),
	}
	build_program(t, &optional_program, downstream_instructions[:], downstream_operands[:], "a", 3)
	bad = value.number_value(12)
	testing.expect_value(t, init_evaluator(&evaluator, &optional_program, &bad, context.allocator).kind, Init_Error_Kind.None)
	downstream_error := step_evaluator(&evaluator)
	testing.expect_value(t, downstream_error.kind, Step_Kind.Runtime_Error)
	testing.expect_value(t, downstream_error.runtime_error.input_kind, value.Kind.Number)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &optional_program)
}

@(test)
fork_and_sequence_preserve_order_cardinality_and_missing_fields :: proc(t: ^testing.T) {
	// Fork(Identity, Field a): two outputs. Sequence(that fork, Field b):
	// the complete first branch's right results precede the second branch's.
	instructions := [4]program.Instruction{
		{opcode = .Identity},
		{opcode = .Field, operands_start = 0, operands_count = 1},
		{opcode = .Fork, operands_start = 1, operands_count = 2},
		{opcode = .Sequence, operands_start = 3, operands_count = 2},
	}
	operands := [5]program.Operand{
		text_operand(0, 1),
		instruction_operand(0), instruction_operand(1),
		instruction_operand(2), instruction_operand(1),
	}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], operands[:], "a", 2)
	input := sample_object(t)
	evaluator: Evaluator
	testing.expect_value(t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind, Init_Error_Kind.None)
	first := step_take(t, &evaluator)
	testing.expect_value(t, value.kind_of(&first), value.Kind.Object)
	testing.expect_value(t, value.destroy_value(&first), runtime.Allocator_Error(nil))
	second := step_take(t, &evaluator)
	testing.expect_value(t, value.kind_of(&second), value.Kind.Object)
	testing.expect_value(t, value.destroy_value(&second), runtime.Allocator_Error(nil))
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)

	// Pipe: (., .a) | .b => null, 7 for the sample object.
	pipe_instructions := [5]program.Instruction{
		{opcode = .Identity},
		{opcode = .Field, operands_start = 0, operands_count = 1},
		{opcode = .Fork, operands_start = 1, operands_count = 2},
		{opcode = .Field, operands_start = 3, operands_count = 1},
		{opcode = .Sequence, operands_start = 4, operands_count = 2},
	}
	pipe_operands := [6]program.Operand{
		text_operand(0, 1),
		instruction_operand(0), instruction_operand(1),
		text_operand(1, 1),
		instruction_operand(2), instruction_operand(3),
	}
	build_program(t, &compiled, pipe_instructions[:], pipe_operands[:], "ab", 4)
	input = sample_object(t)
	testing.expect_value(t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind, Init_Error_Kind.None)
	missing_output := step_take(t, &evaluator)
	expect_null(t, &missing_output)
	nested_output := step_take(t, &evaluator)
	expect_number(t, &nested_output, 7)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)
}

@(test)
one_output_per_step_and_early_destroy_have_no_buffered_stream :: proc(t: ^testing.T) {
	// A 64-leaf left-deep Fork would have 64 outputs if eagerly evaluated.
	depth := 63
	instructions := make([]program.Instruction, depth+1)
	operands := make([]program.Operand, depth*2)
	instructions[0] = {opcode = .Identity}
	for i in 1..=depth {
		instructions[i] = {
			opcode = .Fork,
			operands_start = program.Operand_Index((i-1)*2),
			operands_count = 2,
		}
		operands[(i-1)*2] = instruction_operand(i-1)
		operands[(i-1)*2+1] = instruction_operand(0)
	}
	compiled: program.Program
	build_program(t, &compiled, instructions, operands, "", depth)
	delete(instructions)
	delete(operands)
	input := value.number_value(5)
	evaluator: Evaluator
	testing.expect_value(t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind, Init_Error_Kind.None)
	first := step_take(t, &evaluator)
	expect_number(t, &first, 5)
	// Cancellation releases suspended forks without producing the other 63.
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)
}

@(private)
deep_shape :: proc(t: ^testing.T, opcode: program.Opcode, depth: int) {
	instruction_count := depth+1
	operands_per := 1
	if opcode == .Sequence || opcode == .Fork do operands_per = 2
	instructions := make([]program.Instruction, instruction_count)
	operands := make([]program.Operand, depth*operands_per)
	instructions[0] = {opcode = .Identity}
	for i in 1..=depth {
		start := (i-1)*operands_per
		instructions[i] = {
			opcode = opcode,
			operands_start = program.Operand_Index(start),
			operands_count = program.Count(operands_per),
		}
		operands[start] = instruction_operand(i-1)
		if operands_per == 2 do operands[start+1] = instruction_operand(0)
	}
	compiled: program.Program
	build_program(t, &compiled, instructions, operands, "", depth)
	delete(instructions)
	delete(operands)
	input := value.number_value(1)
	evaluator: Evaluator
	testing.expect_value(t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind, Init_Error_Kind.None)
	first := step_take(t, &evaluator)
	expect_number(t, &first, 1)
	if opcode == .Fork {
		// Prove resumption through the 10,000 suspended left branches, then stop.
		for _ in 0..<depth {
			output := step_take(t, &evaluator)
			expect_number(t, &output, 1)
		}
	}
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)
}

@(test)
ten_thousand_deep_shapes_use_explicit_state :: proc(t: ^testing.T) {
	deep_shape(t, .Parenthesized, 10_000)
	deep_shape(t, .Optional, 10_000)
	deep_shape(t, .Sequence, 10_000)
	deep_shape(t, .Fork, 10_000)
}

@(private)
build_shared_sequence_program :: proc(t: ^testing.T, output: ^program.Program, width: int) {
	// One shared Parenthesized path is reactivated as the right child of every
	// left-deep Sequence. The first output suspends O(width^2) activations even
	// though the sealed Program contains only O(width) instructions.
	instruction_count := 1+width+width
	operand_count := width+width*2
	instructions := make([]program.Instruction, instruction_count)
	operands := make([]program.Operand, operand_count)
	instructions[0] = {opcode = .Identity}
	for i in 1..=width {
		instructions[i] = {
			opcode = .Parenthesized,
			operands_start = program.Operand_Index(i-1),
			operands_count = 1,
		}
		operands[i-1] = instruction_operand(i-1)
	}
	previous := width
	for i in 0..<width {
		index := width+1+i
		start := width+i*2
		instructions[index] = {
			opcode = .Sequence,
			operands_start = program.Operand_Index(start),
			operands_count = 2,
		}
		operands[start] = instruction_operand(previous)
		operands[start+1] = instruction_operand(width)
		previous = index
	}
	build_program(t, output, instructions, operands, "", previous)
	delete(instructions)
	delete(operands)
}

@(test)
shared_dag_growth_allocation_and_old_free_failures_retry_without_lost_state :: proc(t: ^testing.T) {
	compiled: program.Program
	build_shared_sequence_program(t, &compiled, 24)

	alloc_fail := fail_allocator_state{backing = context.allocator, fail_at = 2}
	input := value.number_value(2)
	evaluator: Evaluator
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			runtime.Allocator{procedure = fail_allocator_proc, data = &alloc_fail},
		).kind,
		Init_Error_Kind.None,
	)
	first_result := step_evaluator(&evaluator)
	testing.expect_value(t, first_result.kind, Step_Kind.Resource_Error)
	output := step_take(t, &evaluator)
	expect_number(t, &output, 2)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))

	old_free_fail := fail_allocator_state{
		backing = context.allocator,
		fail_at = -1,
		fail_free_at = 1,
		reject_free_count = 1,
		free_error = .Invalid_Argument,
	}
	input = value.number_value(3)
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			runtime.Allocator{procedure = fail_allocator_proc, data = &old_free_fail},
		).kind,
		Init_Error_Kind.None,
	)
	result := step_evaluator(&evaluator)
	testing.expect_value(t, result.kind, Step_Kind.Resource_Error)
	testing.expect_value(t, result.resource_error, runtime.Allocator_Error.Invalid_Argument)
	output = step_take(t, &evaluator)
	expect_number(t, &output, 3)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)
}

@(private)
short_allocator_state :: struct {
	backing:          runtime.Allocator,
	short_once:       bool,
	reject_free_once: bool,
	free_calls:       int,
}

@(private)
short_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^short_allocator_state)data
	if (mode == .Alloc || mode == .Alloc_Non_Zeroed) && state.short_once {
		state.short_once = false
		memory, err := state.backing.procedure(
			state.backing.data, mode, size, alignment, old_memory, old_size, loc,
		)
		if err != nil || len(memory) == 0 do return memory, err
		return memory[:len(memory)-1], nil
	}
	if mode == .Free {
		state.free_calls += 1
		if state.reject_free_once {
			state.reject_free_once = false
			return nil, .Invalid_Argument
		}
	}
	return state.backing.procedure(
		state.backing.data, mode, size, alignment, old_memory, old_size, loc,
	)
}

@(private)
short_allocator :: proc(state: ^short_allocator_state) -> runtime.Allocator {
	return {procedure = short_allocator_proc, data = state}
}

@(test)
init_allocation_failures_preserve_heap_input_and_cleanup_retry :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)
	instructions := [1]program.Instruction{{opcode = .Identity}}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], nil, "", 0)

	allocation_state := fail_allocator_state{backing = context.allocator, fail_at = 1}
	input := nested_heap_value(t, context.allocator, false)
	evaluator: Evaluator
	result := init_evaluator(
		&evaluator,
		&compiled,
		&input,
		{procedure = fail_allocator_proc, data = &allocation_state},
	)
	testing.expect_value(t, result.kind, Init_Error_Kind.Resource_Failure)
	testing.expect_value(t, result.resource_error, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, evaluator == nil, true)
	expect_preserved_nested_input(t, &input)
	testing.expect_value(t, value.destroy_value(&input), runtime.Allocator_Error(nil))

	short_state := short_allocator_state{
		backing = context.allocator,
		short_once = true,
		reject_free_once = true,
	}
	input = nested_heap_value(t, context.allocator, false)
	result = init_evaluator(&evaluator, &compiled, &input, short_allocator(&short_state))
	testing.expect_value(t, result.kind, Init_Error_Kind.Resource_Failure)
	testing.expect_value(t, result.resource_error, runtime.Allocator_Error.Invalid_Argument)
	// The evaluator owns only the short allocator result; input ownership never
	// moved and remains usable while cleanup is pending.
	expect_preserved_nested_input(t, &input)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	testing.expect_value(t, short_state.free_calls, 2)
	expect_preserved_nested_input(t, &input)
	testing.expect_value(t, value.destroy_value(&input), runtime.Allocator_Error(nil))

	destroy_program_test(t, &compiled)
	allocation_scope_end(t, &scope)
}

@(test)
allocator_failure_short_success_free_failure_and_retry_are_deterministic :: proc(t: ^testing.T) {
	instructions := [1]program.Instruction{{opcode = .Identity}}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], nil, "", 0)

	fail_state := fail_allocator_state{backing = context.allocator, fail_at = 1}
	input := value.number_value(1)
	evaluator: Evaluator
	init_result := init_evaluator(
		&evaluator,
		&compiled,
		&input,
		runtime.Allocator{procedure = fail_allocator_proc, data = &fail_state},
	)
	testing.expect_value(t, init_result.kind, Init_Error_Kind.Resource_Failure)
	testing.expect_value(t, value.kind_of(&input), value.Kind.Number)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))

	short_state := short_allocator_state{
		backing = context.allocator,
		short_once = true,
		reject_free_once = true,
	}
	init_result = init_evaluator(&evaluator, &compiled, &input, short_allocator(&short_state))
	testing.expect_value(t, init_result.kind, Init_Error_Kind.Resource_Failure)
	testing.expect_value(t, init_result.resource_error, runtime.Allocator_Error.Invalid_Argument)
	testing.expect_value(t, value.kind_of(&input), value.Kind.Number)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	testing.expect_value(t, short_state.free_calls, 2)

	free_state := fail_allocator_state{
		backing = context.allocator,
		fail_at = -1,
		fail_free_at = 1,
		reject_free_count = 1,
		free_error = .Invalid_Argument,
	}
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			runtime.Allocator{procedure = fail_allocator_proc, data = &free_state},
		).kind,
		Init_Error_Kind.None,
	)
	output := step_take(t, &evaluator)
	expect_number(t, &output, 1)
	cleanup_failure := step_evaluator(&evaluator)
	testing.expect_value(t, cleanup_failure.kind, Step_Kind.Resource_Error)
	testing.expect_value(t, cleanup_failure.resource_error, runtime.Allocator_Error.Invalid_Argument)
	testing.expect_value(t, step_evaluator(&evaluator).kind, Step_Kind.Done)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))

	early_free_state := fail_allocator_state{
		backing = context.allocator,
		fail_at = -1,
		fail_free_at = 1,
		reject_free_count = 1,
		free_error = .Invalid_Argument,
	}
	input = value.number_value(6)
	testing.expect_value(
		t,
		init_evaluator(
			&evaluator,
			&compiled,
			&input,
			runtime.Allocator{procedure = fail_allocator_proc, data = &early_free_state},
		).kind,
		Init_Error_Kind.None,
	)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error.Invalid_Argument)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)
}

@(test)
copied_owner_program_lifetime_and_unsealed_program_misuse_are_detected :: proc(t: ^testing.T) {
	instructions := [1]program.Instruction{{opcode = .Identity}}
	compiled: program.Program
	build_program(t, &compiled, instructions[:], nil, "", 0)
	input := value.number_value(4)
	evaluator: Evaluator
	testing.expect_value(t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind, Init_Error_Kind.None)
	copy := evaluator
	testing.expect_value(t, step_evaluator(&copy).misuse, Misuse_Kind.Copied_Evaluator)
	testing.expect_value(t, destroy_evaluator(&copy), runtime.Allocator_Error.Invalid_Pointer)
	first := step_take(t, &evaluator)
	expect_number(t, &first, 4)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)

	unsealed: program.Program
	init_error := program.init_program(&unsealed, 1, 0, 0, context.allocator)
	testing.expect_value(t, init_error.kind, program.Init_Error_Kind.None)
	input = value.number_value(1)
	testing.expect_value(
		t,
		init_evaluator(&evaluator, &unsealed, &input, context.allocator).kind,
		Init_Error_Kind.Invalid_Program,
	)
	testing.expect_value(t, value.kind_of(&input), value.Kind.Number)
	destroy_program_test(t, &unsealed)

	build_program(t, &compiled, instructions[:], nil, "", 0)
	compiled_copy := compiled
	input = value.number_value(1)
	testing.expect_value(
		t,
		init_evaluator(&evaluator, &compiled_copy, &input, context.allocator).kind,
		Init_Error_Kind.Invalid_Program,
	)
	testing.expect_value(t, value.kind_of(&input), value.Kind.Number)
	testing.expect_value(t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind, Init_Error_Kind.None)
	destroy_program_test(t, &compiled)
	result := step_evaluator(&evaluator)
	testing.expect_value(t, result.kind, Step_Kind.Misuse)
	testing.expect_value(t, result.misuse, Misuse_Kind.Invalid_Program_Lifetime)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))

	build_program(t, &compiled, instructions[:], nil, "", 0)
	input = value.number_value(1)
	testing.expect_value(t, init_evaluator(&evaluator, &compiled, &input, context.allocator).kind, Init_Error_Kind.None)
	compiled.instructions[0].opcode = program.Opcode(255)
	result = step_evaluator(&evaluator)
	testing.expect_value(t, result.kind, Step_Kind.Misuse)
	testing.expect_value(t, result.misuse, Misuse_Kind.Malformed_Program)
	testing.expect_value(t, destroy_evaluator(&evaluator), runtime.Allocator_Error(nil))
	destroy_program_test(t, &compiled)
}
