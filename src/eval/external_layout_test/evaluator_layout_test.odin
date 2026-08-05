package eval_external_layout_test

import "base:runtime"
import "core:testing"
import eval "jq:eval"
import program "jq:program"
import value "jq:value"

EVALUATOR_SIZE :: 264
EVALUATOR_ALIGNMENT :: 8
VALUE_SIZE :: 56
VALUE_ALIGNMENT :: 8
GUARD_BEFORE :: u64(0x9d_72_43_81_a6_5c_e0_3f)
GUARD_AFTER :: u64(0x47_1b_f2_6d_90_ca_35_8e)

Wrapper :: struct {
	before:    u64,
	evaluator: eval.Evaluator,
	after:     u64,
}

build_program :: proc(
	t: ^testing.T,
	compiled: ^program.Program,
	opcode: program.Opcode,
	key := "",
) {
	operand_count := 0 if len(key) == 0 else 1
	init_result := program.init_program(
		compiled, 1, program.Count(operand_count), program.Count(len(key)), context.allocator,
	)
	testing.expect_value(t, init_result.kind, program.Init_Error_Kind.None)
	testing.expect(t, program.set_instruction(compiled, 0, {
		opcode = opcode,
		operands_count = program.Count(operand_count),
	}))
	if operand_count == 1 {
		testing.expect(t, program.set_operand(compiled, 0, {
			kind = .Text,
			text_count = program.Count(len(key)),
		}))
		testing.expect(t, program.set_text(compiled, 0, key))
	}
	testing.expect(t, program.set_root(compiled, 0))
	testing.expect(t, program.finalize_program(compiled))
}

expect_guards :: proc(t: ^testing.T, wrapper: ^Wrapper) {
	testing.expect_value(t, wrapper.before, GUARD_BEFORE)
	testing.expect_value(t, wrapper.after, GUARD_AFTER)
}

@(test)
typed_wrapper_preserves_adjacent_values_through_complete_lifecycle :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(value.Value), VALUE_SIZE)
	testing.expect_value(t, align_of(value.Value), VALUE_ALIGNMENT)
	testing.expect_value(t, size_of(eval.Evaluator), EVALUATOR_SIZE)
	testing.expect_value(t, align_of(eval.Evaluator), EVALUATOR_ALIGNMENT)
	testing.expect_value(t, offset_of(Wrapper, evaluator), 8)
	testing.expect_value(t, offset_of(Wrapper, after), 272)
	testing.expect_value(t, size_of(Wrapper), 280)

	compiled: program.Program
	build_program(t, &compiled, .Identity)
	wrapper := Wrapper{before = GUARD_BEFORE, after = GUARD_AFTER}
	expect_guards(t, &wrapper)
	wrapper.evaluator = nil
	expect_guards(t, &wrapper)

	input := value.number_value(7)
	init_result := eval.init_evaluator(
		&wrapper.evaluator, &compiled, &input, context.allocator,
	)
	testing.expect_value(t, init_result.kind, eval.Init_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&input), value.Kind.Invalid)
	expect_guards(t, &wrapper)

	step_result := eval.step_evaluator(&wrapper.evaluator)
	testing.expect_value(t, step_result.kind, eval.Step_Kind.Output)
	expect_guards(t, &wrapper)
	output := eval.take_step_output(&step_result)
	number, number_ok := value.number_value_get(&output)
	testing.expect(t, number_ok)
	testing.expect_value(t, number, 7.0)
	testing.expect_value(t, value.destroy_value(&output), runtime.Allocator_Error(nil))

	testing.expect_value(
		t, eval.step_evaluator(&wrapper.evaluator).kind, eval.Step_Kind.Done,
	)
	expect_guards(t, &wrapper)
	testing.expect_value(
		t, eval.destroy_evaluator(&wrapper.evaluator), runtime.Allocator_Error(nil),
	)
	testing.expect_value(t, wrapper.evaluator == nil, true)
	expect_guards(t, &wrapper)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error(nil))
}

@(test)
exact_size_alignment_allocation_frees_successfully :: proc(t: ^testing.T) {
	compiled: program.Program
	build_program(t, &compiled, .Identity)
	memory, allocation_error := runtime.mem_alloc_bytes(
		EVALUATOR_SIZE, EVALUATOR_ALIGNMENT, context.allocator,
	)
	testing.expect_value(t, allocation_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, len(memory), EVALUATOR_SIZE)
	for index in 0..<len(memory) do memory[index] = 0
	evaluator := cast(^eval.Evaluator)raw_data(memory)

	input := value.number_value(8)
	testing.expect_value(
		t,
		eval.init_evaluator(evaluator, &compiled, &input, context.allocator).kind,
		eval.Init_Error_Kind.None,
	)
	result := eval.step_evaluator(evaluator)
	testing.expect_value(t, result.kind, eval.Step_Kind.Output)
	output := eval.take_step_output(&result)
	testing.expect_value(t, value.destroy_value(&output), runtime.Allocator_Error(nil))
	testing.expect_value(t, eval.step_evaluator(evaluator).kind, eval.Step_Kind.Done)
	testing.expect_value(t, eval.destroy_evaluator(evaluator), runtime.Allocator_Error(nil))
	testing.expect_value(
		t, runtime.mem_free_bytes(memory, context.allocator), runtime.Allocator_Error(nil),
	)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error(nil))
}

Retry_Allocator :: struct {
	backing: runtime.Allocator,
	rejected: bool,
	free_calls: int,
}

retry_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^Retry_Allocator)data
	if mode == .Free {
		state.free_calls += 1
		if !state.rejected {
			state.rejected = true
			return nil, .Invalid_Pointer
		}
	}
	return state.backing.procedure(
		state.backing.data, mode, size, alignment, old_memory, old_size, loc,
	)
}

@(test)
typed_wrapper_preserves_guards_for_error_terminal_and_cleanup_retry :: proc(t: ^testing.T) {
	compiled: program.Program
	build_program(t, &compiled, .Field, "key")
	wrapper := Wrapper{before = GUARD_BEFORE, after = GUARD_AFTER}
	input := value.number_value(1)
	testing.expect_value(
		t,
		eval.init_evaluator(&wrapper.evaluator, &compiled, &input, context.allocator).kind,
		eval.Init_Error_Kind.None,
	)
	runtime_result := eval.step_evaluator(&wrapper.evaluator)
	testing.expect_value(t, runtime_result.kind, eval.Step_Kind.Runtime_Error)
	testing.expect_value(t, runtime_result.runtime_error.key, "key")
	expect_guards(t, &wrapper)
	testing.expect_value(
		t, eval.step_evaluator(&wrapper.evaluator).kind, eval.Step_Kind.Runtime_Error,
	)
	expect_guards(t, &wrapper)
	testing.expect_value(
		t, eval.destroy_evaluator(&wrapper.evaluator), runtime.Allocator_Error(nil),
	)
	expect_guards(t, &wrapper)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error(nil))

	build_program(t, &compiled, .Identity)
	wrapper.evaluator = nil
	input = value.number_value(2)
	testing.expect_value(
		t,
		eval.init_evaluator(&wrapper.evaluator, &compiled, &input, context.allocator).kind,
		eval.Init_Error_Kind.None,
	)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error(nil))
	misuse := eval.step_evaluator(&wrapper.evaluator)
	testing.expect_value(t, misuse.kind, eval.Step_Kind.Misuse)
	testing.expect_value(t, misuse.misuse, eval.Misuse_Kind.Invalid_Program_Lifetime)
	expect_guards(t, &wrapper)
	testing.expect_value(
		t, eval.step_evaluator(&wrapper.evaluator).misuse,
		eval.Misuse_Kind.Invalid_Program_Lifetime,
	)
	testing.expect_value(
		t, eval.destroy_evaluator(&wrapper.evaluator), runtime.Allocator_Error(nil),
	)
	expect_guards(t, &wrapper)

	build_program(t, &compiled, .Identity)
	retry_state := Retry_Allocator{backing = context.allocator}
	retry_allocator := runtime.Allocator{
		procedure = retry_allocator_proc,
		data = &retry_state,
	}
	wrapper.evaluator = nil
	input = value.number_value(3)
	testing.expect_value(
		t,
		eval.init_evaluator(&wrapper.evaluator, &compiled, &input, retry_allocator).kind,
		eval.Init_Error_Kind.None,
	)
	result := eval.step_evaluator(&wrapper.evaluator)
	testing.expect_value(t, result.kind, eval.Step_Kind.Output)
	output := eval.take_step_output(&result)
	testing.expect_value(t, value.destroy_value(&output), runtime.Allocator_Error(nil))
	testing.expect_value(
		t, eval.step_evaluator(&wrapper.evaluator).kind, eval.Step_Kind.Resource_Error,
	)
	expect_guards(t, &wrapper)
	testing.expect_value(
		t, eval.step_evaluator(&wrapper.evaluator).kind, eval.Step_Kind.Done,
	)
	testing.expect_value(t, retry_state.free_calls, 2)
	expect_guards(t, &wrapper)
	testing.expect_value(
		t, eval.destroy_evaluator(&wrapper.evaluator), runtime.Allocator_Error(nil),
	)
	expect_guards(t, &wrapper)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error(nil))
}
