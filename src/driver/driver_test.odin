package driver

import "base:runtime"
import "core:testing"
import "core:strings"
import eval "jq:eval"
import json "jq:json"
import program "jq:program"
import syntax "jq:syntax"
import value "jq:value"

EVALUATOR_GUARD_SIZE :: 64
EVALUATOR_GUARD_BYTE :: byte(0xa5)

guard_allocator_state :: struct {
	backing: runtime.Allocator,
	allocation: []byte,
	exposed: []byte,
	freed: bool,
}

guards_intact :: proc(state: ^guard_allocator_state) -> bool {
	if len(state.allocation) == 0 do return true
	for byte_value in state.allocation[:EVALUATOR_GUARD_SIZE] {
		if byte_value != EVALUATOR_GUARD_BYTE do return false
	}
	end := EVALUATOR_GUARD_SIZE+len(state.exposed)
	for byte_value in state.allocation[end:end+EVALUATOR_GUARD_SIZE] {
		if byte_value != EVALUATOR_GUARD_BYTE do return false
	}
	return true
}

guard_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^guard_allocator_state)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		if len(state.allocation) != 0 do return nil, .Invalid_Argument
		total := size+2*EVALUATOR_GUARD_SIZE
		memory, err := runtime.mem_alloc_bytes(total, alignment, state.backing)
		if err != nil do return nil, err
		for &byte_value in memory do byte_value = EVALUATOR_GUARD_BYTE
		state.allocation = memory
		state.exposed = memory[EVALUATOR_GUARD_SIZE:EVALUATOR_GUARD_SIZE+size]
		return state.exposed, nil
	}
	if mode == .Free {
		if old_memory != raw_data(state.exposed) || old_size != len(state.exposed) {
			return nil, .Invalid_Pointer
		}
		if !guards_intact(state) do return nil, .Invalid_Pointer
		err := runtime.mem_free_bytes(state.allocation, state.backing)
		if err == nil || err == .Mode_Not_Implemented {
			state.allocation = nil
			state.exposed = nil
			state.freed = true
		}
		return nil, err
	}
	return nil, .Mode_Not_Implemented
}

guard_allocator :: proc(state: ^guard_allocator_state) -> runtime.Allocator {
	return {procedure = guard_allocator_proc, data = state}
}

@(test)
evaluator_exact_typed_allocation_preserves_guards :: proc(t: ^testing.T) {
	reported_size, reported_alignment := evaluator_allocation_layout()
	testing.expect_value(t, reported_size, int(size_of(eval.Evaluator)))
	testing.expect_value(t, reported_alignment, int(align_of(eval.Evaluator)))

	compiled: program.Program
	init_error := program.init_program(&compiled, 1, 0, 0, context.allocator)
	testing.expect_value(t, init_error.kind, program.Init_Error_Kind.None)
	testing.expect(t, program.set_instruction(&compiled, 0, {
		opcode = .Identity,
		span = {start = 0, end = 1},
	}))
	testing.expect(t, program.set_root(&compiled, 0))
	testing.expect(t, program.finalize_program(&compiled))

	guard_state := guard_allocator_state{backing = context.allocator}
	memory, allocation_error := runtime.mem_alloc_bytes(
		reported_size, reported_alignment, guard_allocator(&guard_state),
	)
	testing.expect_value(t, allocation_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, len(memory), reported_size)
	testing.expect(t, uintptr(raw_data(memory))%uintptr(reported_alignment) == 0)
	evaluator := cast(^eval.Evaluator)raw_data(memory)
	evaluator^ = nil
	testing.expect(t, guards_intact(&guard_state), "guard changed before evaluator initialization")

	input := value.null_value()
	initialized := eval.init_evaluator(evaluator, &compiled, &input, context.allocator)
	testing.expect_value(t, initialized.kind, eval.Init_Error_Kind.None)
	testing.expect(t, guards_intact(&guard_state), "guard changed during evaluator initialization")

	step := eval.step_evaluator(evaluator)
	testing.expect_value(t, step.kind, eval.Step_Kind.Output)
	output := eval.take_step_output(&step)
	testing.expect_value(t, value.destroy_value(&output), runtime.Allocator_Error(nil))
	done := eval.step_evaluator(evaluator)
	testing.expect_value(t, done.kind, eval.Step_Kind.Done)
	testing.expect(t, guards_intact(&guard_state), "guard changed while stepping evaluator")

	testing.expect_value(t, eval.destroy_evaluator(evaluator), runtime.Allocator_Error(nil))
	testing.expect(t, guards_intact(&guard_state), "guard changed during evaluator destruction")
	testing.expect_value(
		t,
		runtime.mem_free_bytes(memory, guard_allocator(&guard_state)),
		runtime.Allocator_Error(nil),
	)
	testing.expect(t, guard_state.freed)
	testing.expect_value(t, program.destroy_program(&compiled), runtime.Allocator_Error(nil))
}

test_allocator_state :: struct {
	backing:       runtime.Allocator,
	allocation_at: int,
	free_at:       int,
	allocations:   int,
	frees:         int,
	failed_memory: rawptr,
	failed_memory_retry_frees: int,
	free_failures_remaining: int,
	live: int,
}

test_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^test_allocator_state)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed ||
	   mode == .Resize || mode == .Resize_Non_Zeroed {
		state.allocations += 1
		if state.allocation_at > 0 && state.allocations == state.allocation_at {
			return nil, .Out_Of_Memory
		}
	}
	if mode == .Free {
		state.frees += 1
		if state.free_at > 0 && state.frees >= state.free_at &&
		   (state.frees == state.free_at || state.free_failures_remaining > 0) {
			state.failed_memory = old_memory
			if state.free_failures_remaining > 0 do state.free_failures_remaining -= 1
			return nil, .Invalid_Argument
		}
		if state.failed_memory != nil && old_memory == state.failed_memory {
			state.failed_memory_retry_frees += 1
		}
	}
	memory, err := state.backing.procedure(
		state.backing.data, mode, size, alignment, old_memory, old_size, location,
	)
	if err == nil || err == .Mode_Not_Implemented {
		if mode == .Alloc || mode == .Alloc_Non_Zeroed {
			state.live += 1
		} else if mode == .Free {
			state.live -= 1
		}
	}
	return memory, err
}

emitter_probe :: struct {
	bytes: [256]byte,
	length: int,
	calls: int,
	max_borrowed: int,
	fail_at: int,
}

probe_emitter :: proc(data: rawptr, bytes: string) -> bool {
	probe := cast(^emitter_probe)data
	probe.calls += 1
	probe.max_borrowed = max(probe.max_borrowed, len(bytes))
	if probe.fail_at > 0 && probe.calls == probe.fail_at do return false
	if probe.length > len(probe.bytes)-len(bytes) do return false
	copy(probe.bytes[probe.length:probe.length+len(bytes)], transmute([]byte)bytes)
	probe.length += len(bytes)
	return true
}

test_allocator :: proc(state: ^test_allocator_state) -> runtime.Allocator {
	return {procedure = test_allocator_proc, data = state}
}

rejected_driver_kind :: enum u8 {
	Nil,
	Short,
	Oversized,
	Errored,
	Misaligned,
}

rejected_driver_phase :: enum u8 {
	Driver_Storage,
	Evaluator_Init,
	Runtime_Key,
}

rejected_driver_allocator_state :: struct {
	backing: runtime.Allocator,
	kind: rejected_driver_kind,
	phase: rejected_driver_phase,
	outer_seen: bool,
	rejected: bool,
	outer_memory: []byte,
	rejected_backing: []byte,
	rejected_memory: []byte,
	allocation_count: int,
	free_addresses: [32]rawptr,
	free_sizes: [32]int,
	free_count: int,
	rejected_free_failures: int,
	outer_free_failures: int,
	runtime_key_allocation_at: int,
	live: int,
}

rejected_driver_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^rejected_driver_allocator_state)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		state.allocation_count += 1
		evaluator_size, evaluator_alignment := evaluator_allocation_layout()
		is_outer := !state.outer_seen && size == evaluator_size &&
		            alignment == evaluator_alignment
		should_reject := !state.rejected &&
			(state.phase == .Driver_Storage && is_outer ||
			 state.phase == .Evaluator_Init && state.outer_seen ||
			 state.phase == .Runtime_Key &&
			 state.runtime_key_allocation_at > 0 &&
			 state.allocation_count == state.runtime_key_allocation_at)
		if should_reject {
			state.rejected = true
			if state.kind == .Nil do return nil, nil
			actual_size := size
			switch state.kind {
			case .Short: actual_size = size-1
			case .Oversized: actual_size = size+9
			case .Misaligned: actual_size = size+1
			case .Errored, .Nil:
			}
			memory, err := runtime.mem_alloc_bytes(actual_size, alignment, state.backing)
			if err != nil do return memory, err
			state.rejected_backing = memory
			state.rejected_memory = memory
			if state.kind == .Misaligned do state.rejected_memory = memory[1:]
			state.live += 1
			if state.kind == .Errored do return state.rejected_memory, .Out_Of_Memory
			return state.rejected_memory, nil
		}
	}
	if mode == .Free {
		if state.free_count < len(state.free_addresses) {
			state.free_addresses[state.free_count] = old_memory
			state.free_sizes[state.free_count] = old_size
		}
		state.free_count += 1
		if len(state.rejected_memory) > 0 && old_memory == raw_data(state.rejected_memory) {
			if old_size != len(state.rejected_memory) do return nil, .Invalid_Pointer
			if state.rejected_free_failures > 0 {
				state.rejected_free_failures -= 1
				return nil, .Invalid_Argument
			}
			err := runtime.mem_free_bytes(state.rejected_backing, state.backing)
			if err == nil || err == .Mode_Not_Implemented {
				state.rejected_backing = nil
				state.rejected_memory = nil
				state.live -= 1
			}
			return nil, err
		}
		if len(state.outer_memory) > 0 && old_memory == raw_data(state.outer_memory) &&
		   state.outer_free_failures > 0 {
			state.outer_free_failures -= 1
			return nil, .Invalid_Argument
		}
	}
	memory, err := state.backing.procedure(
		state.backing.data, mode, size, alignment, old_memory, old_size, location,
	)
	if err == nil || err == .Mode_Not_Implemented {
		if mode == .Alloc || mode == .Alloc_Non_Zeroed {
			state.live += 1
			evaluator_size, evaluator_alignment := evaluator_allocation_layout()
			if !state.outer_seen && size == evaluator_size && alignment == evaluator_alignment {
				state.outer_seen = true
				state.outer_memory = memory
			}
		} else if mode == .Free {
			if len(state.outer_memory) > 0 && old_memory == raw_data(state.outer_memory) {
				state.outer_memory = nil
			}
			state.live -= 1
		}
	}
	return memory, err
}

@(test)
runtime_key_free_failure_is_cleanup_with_retryable_owner :: proc(t: ^testing.T) {
	baseline_state := rejected_driver_allocator_state{
		backing = context.allocator,
		phase = .Runtime_Key,
	}
	baseline_result: Run_Result
	_ = run(&baseline_result, ".a", "1", rejected_driver_allocator(&baseline_state))
	destroy_result_test(t, &baseline_result)
	testing.expect(t, baseline_state.allocation_count > 0)
	state := rejected_driver_allocator_state{
		backing = context.allocator,
		kind = .Oversized,
		phase = .Runtime_Key,
		rejected_free_failures = 2,
		runtime_key_allocation_at = baseline_state.allocation_count,
	}
	result: Run_Result
	err := run(&result, ".a", "1", rejected_driver_allocator(&state))
	testing.expect(t, state.rejected, "runtime key allocation was not reached")
	testing.expect_value(t, err.kind, Run_Error_Kind.Cleanup)
	testing.expect_value(t, err.resource_error, runtime.Allocator_Error(.Invalid_Argument))
	testing.expect_value(t, len(result.cleanup_memory), len(state.rejected_memory))
	testing.expect_value(t, rawptr(raw_data(result.cleanup_memory)), rawptr(raw_data(state.rejected_memory)))
	testing.expect_value(t, destroy_run_result(&result), runtime.Allocator_Error(.Invalid_Argument))
	testing.expect_value(t, destroy_run_result(&result), runtime.Allocator_Error(nil))
	testing.expect_value(t, state.live, 0)
}

rejected_driver_allocator :: proc(state: ^rejected_driver_allocator_state) -> runtime.Allocator {
	return {procedure = rejected_driver_allocator_proc, data = state}
}

destroy_result_test :: proc(t: ^testing.T, result: ^Run_Result) {
	for _ in 0..<8 {
		err := destroy_run_result(result)
		if err == nil do return
	}
	testing.expect(t, false, "driver cleanup did not converge")
}

expect_run :: proc(
	t: ^testing.T,
	filter, input, expected: string,
	expected_kind: Run_Error_Kind = .None,
) {
	result: Run_Result
	err := run(&result, filter, input, context.allocator)
	testing.expect_value(t, err.kind, expected_kind)
	bytes, ok := run_result_bytes(&result)
	testing.expect(t, ok)
	testing.expect_value(t, bytes, expected)
	destroy_result_test(t, &result)
}

expect_run_mode :: proc(
	t: ^testing.T,
	filter, input, expected: string,
	mode: Output_Mode,
) {
	result: Run_Result
	err := run_with_options(
		&result, filter, input, context.allocator, {output_mode = mode},
	)
	testing.expect_value(t, err.kind, Run_Error_Kind.None)
	bytes, ok := run_result_bytes(&result)
	testing.expect(t, ok)
	testing.expect_value(t, bytes, expected)
	destroy_result_test(t, &result)
}

@(test)
zero_one_and_many_outputs_are_lf_delimited :: proc(t: ^testing.T) {
	expect_run(t, ".a?", "1", "")
	expect_run(t, ".a.b", "{\"a\":{\"b\":2}}", "2\n")
	expect_run(
		t, "., .a, .a.b", "{\"a\":{\"b\":2}}",
		"{\n  \"a\": {\n    \"b\": 2\n  }\n}\n{\n  \"b\": 2\n}\n2\n",
	)
	expect_run(t, ".a | .b", "{\"a\":{\"b\":2}}", "2\n")
}

@(test)
stream_inputs_and_output_modes_match_jq_bytes :: proc(t: ^testing.T) {
	input := "  1\n2[3,4]{\"a\":[true,{\"b\":null}]} \t"
	expect_run(
		t, ".", input,
		"1\n2\n[\n  3,\n  4\n]\n{\n  \"a\": [\n    true,\n    {\n      \"b\": null\n    }\n  ]\n}\n",
	)
	expect_run_mode(
		t, ".", input,
		"1\n2\n[3,4]\n{\"a\":[true,{\"b\":null}]}\n",
		.Compact,
	)
	expect_run(t, ".", " \r\n\t", "")
	expect_run(t, ".", "\"x\" false null", "\"x\"\nfalse\nnull\n")
}

@(test)
module_paths_are_borrowed_in_order_without_changing_execution :: proc(t: ^testing.T) {
	module_paths := []string{"/first", "/second"}
	result: Run_Result
	err := run_with_options(
		&result, ".", "1", context.allocator,
		{module_paths = module_paths},
	)
	testing.expect_value(t, err.kind, Run_Error_Kind.None)
	bytes, ok := run_result_bytes(&result)
	testing.expect(t, ok)
	testing.expect_value(t, bytes, "1\n")
	destroy_result_test(t, &result)
}

@(test)
module_definition_body_tracks_nested_jq_delimiters :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	source := "def answer: reduce .[] as $x (0; . + $x);"
	outcome := find_module_definitions(source, &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, len(definitions), 1)
	testing.expect_value(t, definitions[0].body, " reduce .[] as $x (0; . + $x)")
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
module_definition_body_rejects_unterminated_string :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def unused: \"unterminated;", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.Unsupported_Syntax)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
module_definition_requires_identifier_start :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def : 42;", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.Unsupported_Syntax)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
module_import_accepts_dollar_namespace_alias :: proc(t: ^testing.T) {
	name, alias, next, ok, unsupported := parse_module_import(
		"import \"answer\" as $a;", 0,
	)
	testing.expect_value(t, name, "answer")
	testing.expect_value(t, alias, "a")
	testing.expect_value(t, next, len("import \"answer\" as $a;"))
	testing.expect_value(t, ok, true)
	testing.expect_value(t, unsupported, false)
}

module_expansion_rejects_wrong_arity :: proc(
	t: ^testing.T,
	definitions: [dynamic]module_definition,
	source: string,
) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome := module_expand_source(source, definitions, &builder, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.Unsupported_Syntax)
	strings.builder_destroy(&builder)
}

@(test)
parameterized_module_calls_require_exact_arity :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def f(x): x;", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	module_expansion_rejects_wrong_arity(t, definitions, "f")
	module_expansion_rejects_wrong_arity(t, definitions, "f()")
	module_expansion_rejects_wrong_arity(t, definitions, "f(1;2)")
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
dollar_parameter_references_are_substituted :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def value($x): $x;", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source("value(7)", definitions, &builder, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(builder), "( (7))")
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
filter_parameter_arguments_preserve_expression_precedence :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def twice(x): x * 2;", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source("twice(.a + .b)", definitions, &builder, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(builder), "( (.a + .b) * 2)")
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
parameterized_module_arguments_expand_nested_definitions :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def one: 1; def id(x): x;", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source("id(one)", definitions, &builder, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(builder), "( (( 1)))")
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
nested_parameterized_module_calls_preserve_caller_arguments :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def id(x): x; def outer(x): id(x);", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source("outer(7)", definitions, &builder, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(builder), "( ( ((7))))")
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
parameterized_module_arguments_preserve_caller_environment :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def id(x): x; def outer(x): id(x);", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source("outer(7)", definitions, &builder, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(builder), "( ( ((7))))")
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
qualified_parameterized_module_arguments_preserve_caller_environment :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	make_error: runtime.Allocator_Error
	definitions, make_error = make([dynamic]module_definition, 0, 2, context.allocator)
	testing.expect_value(t, make_error, runtime.Allocator_Error(nil))
	id_name, id_name_error := strings.clone("m::id", context.allocator)
	id_parameters, id_parameters_error := strings.clone("x", context.allocator)
	id_body, id_body_error := strings.clone(" x", context.allocator)
	outer_name, outer_name_error := strings.clone("m::outer", context.allocator)
	outer_parameters, outer_parameters_error := strings.clone("x", context.allocator)
	outer_body, outer_body_error := strings.clone(" m::id(x)", context.allocator)
	testing.expect_value(t, id_name_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, id_parameters_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, id_body_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, outer_name_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, outer_parameters_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, outer_body_error, runtime.Allocator_Error(nil))
	append(&definitions, module_definition{name = id_name, parameters = id_parameters, body = id_body, active = true})
	append(&definitions, module_definition{name = outer_name, parameters = outer_parameters, body = outer_body, active = true})
	outcome: Module_Outcome
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source("m::outer(7)", definitions, &builder, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(builder), "( ( ((7))))")
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
module_expansion_preserves_object_shorthand :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def x: 42;", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source("{x}", definitions, &builder, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(builder), "{x}")
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
typed_filter_json_runtime_and_misuse_boundaries :: proc(t: ^testing.T) {
	parse_result: Run_Result
	parse_error := run(&parse_result, ".a.", "null", context.allocator)
	testing.expect_value(t, parse_error.kind, Run_Error_Kind.Filter_Parse)
	testing.expect_value(t, parse_error.filter_parse_kind, syntax.Parse_Error_Kind.Unexpected_End)
	destroy_result_test(t, &parse_result)

	compile_result: Run_Result
	compile_error := run(&compile_result, "1", "null", context.allocator)
	testing.expect_value(t, compile_error.kind, Run_Error_Kind.None)
	compile_bytes, compile_bytes_ok := run_result_bytes(&compile_result)
	testing.expect(t, compile_bytes_ok)
	testing.expect_value(t, compile_bytes, "1\n")
	destroy_result_test(t, &compile_result)

	json_result: Run_Result
	json_error := run(&json_result, ".", "{", context.allocator)
	testing.expect_value(t, json_error.kind, Run_Error_Kind.JSON_Input)
	testing.expect_value(t, json_error.json_kind, json.Scalar_Parse_Error_Kind.Unfinished_Object)
	destroy_result_test(t, &json_result)

	runtime_result: Run_Result
	runtime_error := run(&runtime_result, "., .a", "1", context.allocator)
	testing.expect_value(t, runtime_error.kind, Run_Error_Kind.Runtime)
	testing.expect_value(t, runtime_error.runtime_kind, eval.Runtime_Error_Kind.Cannot_Index_With_String)
	testing.expect_value(t, runtime_error.runtime_key, "a")
	bytes, bytes_ok := run_result_bytes(&runtime_result)
	testing.expect(t, bytes_ok)
	testing.expect_value(t, bytes, "1\n")
	destroy_result_test(t, &runtime_result)

	testing.expect_value(t, run(nil, ".", "null", context.allocator).kind, Run_Error_Kind.Misuse)
}

@(test)
run_result_rejects_address_change_without_disturbing_original_owner :: proc(t: ^testing.T) {
	result: Run_Result
	err := run(&result, ".a", "{\"a\":2}", context.allocator)
	testing.expect_value(t, err.kind, Run_Error_Kind.None)

	copy := result
	_, copy_bytes_ok := run_result_bytes(&copy)
	testing.expect_value(t, copy_bytes_ok, false)
	_, copy_error_ok := run_result_error(&copy)
	testing.expect_value(t, copy_error_ok, false)
	testing.expect_value(
		t, destroy_run_result(&copy), runtime.Allocator_Error(.Invalid_Pointer),
	)

	bytes, bytes_ok := run_result_bytes(&result)
	testing.expect(t, bytes_ok)
	testing.expect_value(t, bytes, "2\n")
	stored_error, stored_error_ok := run_result_error(&result)
	testing.expect(t, stored_error_ok)
	testing.expect_value(t, stored_error.kind, Run_Error_Kind.None)
	destroy_result_test(t, &result)
}

@(test)
allocation_failure_at_every_request_is_owned_and_retryable :: proc(t: ^testing.T) {
	baseline_state := test_allocator_state{backing = context.allocator}
	baseline_result: Run_Result
	baseline_error := run(
		&baseline_result, "., ., ., .", "{\"a\":[1,2,3]}",
		test_allocator(&baseline_state),
	)
	testing.expect_value(t, baseline_error.kind, Run_Error_Kind.None)
	request_count := baseline_state.allocations
	destroy_result_test(t, &baseline_result)
	testing.expect(t, request_count > 0)

	saw_failure_after_output := false
	for fail_at in 1..=request_count {
		state := test_allocator_state{
			backing = context.allocator,
			allocation_at = fail_at,
		}
		result: Run_Result
		err := run(&result, "., ., ., .", "{\"a\":[1,2,3]}", test_allocator(&state))
		testing.expect(t, err.kind == .Allocation || err.kind == .Cleanup)
		bytes, ok := run_result_bytes(&result)
		testing.expect(t, ok)
		if len(bytes) > 0 do saw_failure_after_output = true
		destroy_result_test(t, &result)
	}
	testing.expect(t, saw_failure_after_output, "no injected failure followed a serialized result")
}

@(test)
free_failure_cleanup_retries_without_losing_serialized_prefix :: proc(t: ^testing.T) {
	baseline_state := test_allocator_state{backing = context.allocator}
	baseline_result: Run_Result
	_ = run(&baseline_result, "., ., .a", "{\"a\":2}", test_allocator(&baseline_state))
	destroy_result_test(t, &baseline_result)
	free_count := baseline_state.frees
	testing.expect(t, free_count > 0)

	saw_cleanup_after_output := false
	for fail_at in 1..=free_count {
		state := test_allocator_state{
			backing = context.allocator,
			free_at = fail_at,
		}
		result: Run_Result
		err := run(&result, "., ., .a", "{\"a\":2}", test_allocator(&state))
		bytes, ok := run_result_bytes(&result)
		testing.expect(t, ok)
		if err.kind == .Cleanup && len(bytes) > 0 do saw_cleanup_after_output = true
		destroy_result_test(t, &result)
	}
	testing.expect(t, saw_cleanup_after_output, "no cleanup retry retained completed output")
}

@(test)
serializer_cleanup_failure_is_never_classified_as_allocation_oom :: proc(t: ^testing.T) {
	baseline_state := test_allocator_state{backing = context.allocator}
	baseline_result: Run_Result
	_ = run_with_options(
		&baseline_result, ".", "{\"a\":[1,{\"b\":2}]}",
		test_allocator(&baseline_state), {output_mode = .Compact},
	)
	destroy_result_test(t, &baseline_result)

	saw_cleanup := false
	for fail_at in 1..=baseline_state.frees {
		state := test_allocator_state{backing = context.allocator, free_at = fail_at}
		result: Run_Result
		err := run_with_options(
			&result, ".", "{\"a\":[1,{\"b\":2}]}",
			test_allocator(&state), {output_mode = .Compact},
		)
		testing.expect(
			t, !(err.kind == .Allocation && err.resource_error == .Out_Of_Memory),
			"a Free failure was falsely classified as allocation OOM",
		)
		if err.kind == .Cleanup do saw_cleanup = true
		destroy_result_test(t, &result)
	}
	testing.expect(t, saw_cleanup, "no injected serializer cleanup failure reached Cleanup")
}

@(test)
parser_scratch_cleanup_is_classified_retained_and_retried_once :: proc(t: ^testing.T) {
	state := test_allocator_state{
		backing = context.allocator,
		free_at = 1,
		// The parser's retirement and finish's immediate cleanup replay both
		// fail. Public destruction then performs the one successful retry.
		free_failures_remaining = 2,
	}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = test_allocator(&state)
	result: Run_Result
	err := run(&result, ".", "[[1],", context.allocator)
	context.temp_allocator = saved_temp_allocator

	testing.expect_value(t, err.kind, Run_Error_Kind.Cleanup)
	testing.expect_value(t, err.resource_error, runtime.Allocator_Error(.Invalid_Argument))
	testing.expect_value(
		t, result.json_error.kind,
		json.Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure,
	)
	testing.expect(t, result.json_error.cleanup_frame_blocks != nil)
	testing.expect(t, state.live > 0)
	testing.expect_value(t, state.failed_memory_retry_frees, 0)

	testing.expect_value(
		t, destroy_run_result(&result), runtime.Allocator_Error(nil),
	)
	testing.expect_value(t, state.failed_memory_retry_frees, 1)
	testing.expect_value(t, state.live, 0)
	testing.expect_value(
		t, destroy_run_result(&result), runtime.Allocator_Error(nil),
	)
	testing.expect_value(t, state.failed_memory_retry_frees, 1)
}

@(test)
synchronous_emitter_reuses_bounded_output_storage_and_backpressures :: proc(t: ^testing.T) {
	probe: emitter_probe
	result: Run_Result
	err := run_with_options(
		&result, "., .", "1 22 [3,4] {\"a\":5}", context.allocator,
		{output_mode = .Compact, emitter = probe_emitter, emitter_data = &probe},
	)
	testing.expect_value(t, err.kind, Run_Error_Kind.None)
	testing.expect_value(t, probe.calls, 8)
	testing.expect_value(
		t, transmute(string)probe.bytes[:probe.length],
		"1\n1\n22\n22\n[3,4]\n[3,4]\n{\"a\":5}\n{\"a\":5}\n",
	)
	testing.expect(t, probe.max_borrowed <= 8)
	bytes, bytes_ok := run_result_bytes(&result)
	testing.expect(t, bytes_ok)
	testing.expect_value(t, len(bytes), 0)
	destroy_result_test(t, &result)

	failing_probe := emitter_probe{fail_at = 2}
	failing_result: Run_Result
	failing_error := run_with_options(
		&failing_result, "., .", "1 2", context.allocator,
		{output_mode = .Compact, emitter = probe_emitter, emitter_data = &failing_probe},
	)
	testing.expect_value(t, failing_error.kind, Run_Error_Kind.Output)
	testing.expect_value(t, failing_probe.calls, 2)
	destroy_result_test(t, &failing_result)
}

@(test)
output_replacement_free_failure_retains_both_buffers_for_exact_retry :: proc(t: ^testing.T) {
	baseline_state := test_allocator_state{backing = context.allocator}
	baseline_result: Run_Result
	_ = run(
		&baseline_result, "., ., ., .",
		"{\"long\":\"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz\"}",
		test_allocator(&baseline_state),
	)
	destroy_result_test(t, &baseline_result)

	found := false
	for fail_at in 1..=baseline_state.frees {
		state := test_allocator_state{backing = context.allocator, free_at = fail_at}
		result: Run_Result
		err := run(
			&result, "., ., ., .",
			"{\"long\":\"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz\"}",
			test_allocator(&state),
		)
		if err.kind == .Cleanup && len(result.output_memory) > 0 &&
		   len(result.cleanup_memory) > 0 {
			found = true
			testing.expect(t, raw_data(result.output_memory) != raw_data(result.cleanup_memory))
			testing.expect_value(t, state.failed_memory, raw_data(result.output_memory))
			testing.expect_value(t, state.failed_memory_retry_frees, 0)
			testing.expect_value(
				t, destroy_run_result(&result), runtime.Allocator_Error(nil),
			)
			testing.expect_value(t, state.failed_memory_retry_frees, 1)
			testing.expect_value(
				t, destroy_run_result(&result), runtime.Allocator_Error(nil),
			)
			testing.expect_value(t, state.failed_memory_retry_frees, 1)
			break
		}
		destroy_result_test(t, &result)
	}
	testing.expect(t, found, "did not inject the old output buffer replacement Free")
}

@(test)
rejected_driver_evaluator_storage_has_typed_retryable_cleanup :: proc(t: ^testing.T) {
	kinds := [5]rejected_driver_kind{.Nil, .Short, .Oversized, .Errored, .Misaligned}
	for kind in kinds {
		state := rejected_driver_allocator_state{
			backing = context.allocator,
			kind = kind,
			phase = .Driver_Storage,
			rejected_free_failures = 2,
		}
		probe: emitter_probe
		result: Run_Result
		err := run_with_options(
			&result, ".", "null", rejected_driver_allocator(&state),
			{output_mode = .Compact, emitter = probe_emitter, emitter_data = &probe},
		)
		testing.expect(t, state.rejected, "typed evaluator allocation was not reached")
		testing.expect_value(t, probe.calls, 0)
		allocation_count := state.allocation_count
		if kind == .Nil {
			testing.expect_value(t, err.kind, Run_Error_Kind.Allocation)
			testing.expect_value(t, len(result.cleanup_memory), 0)
			destroy_result_test(t, &result)
			testing.expect_value(t, state.live, 0)
			continue
		}

		rejected_address := rawptr(raw_data(state.rejected_memory))
		rejected_size := len(state.rejected_memory)
		testing.expect_value(t, err.kind, Run_Error_Kind.Cleanup)
		testing.expect_value(t, rawptr(raw_data(result.cleanup_memory)), rejected_address)
		testing.expect_value(t, len(result.cleanup_memory), rejected_size)
		testing.expect_value(t, state.free_addresses[0], rejected_address)
		testing.expect_value(t, state.free_sizes[0], rejected_size)
		testing.expect_value(
			t, destroy_run_result(&result), runtime.Allocator_Error(.Invalid_Argument),
		)
		testing.expect_value(t, rawptr(raw_data(result.cleanup_memory)), rejected_address)
		testing.expect_value(t, len(result.cleanup_memory), rejected_size)
		testing.expect_value(t, state.allocation_count, allocation_count)
		testing.expect_value(t, probe.calls, 0)
		testing.expect_value(t, destroy_run_result(&result), runtime.Allocator_Error(nil))
		testing.expect_value(t, state.live, 0)
		free_count := state.free_count
		testing.expect_value(t, destroy_run_result(&result), runtime.Allocator_Error(nil))
		testing.expect_value(t, state.free_count, free_count)
	}
}

@(test)
evaluator_init_cleanup_chains_inner_and_outer_free_retries :: proc(t: ^testing.T) {
	state := rejected_driver_allocator_state{
		backing = context.allocator,
		kind = .Short,
		phase = .Evaluator_Init,
		// init_evaluator's immediate Free and finish's cleanup replay both fail.
		rejected_free_failures = 2,
		// The first public destroy then frees the inner allocation and reaches a
		// separately failing exact evaluator-storage Free.
		outer_free_failures = 1,
	}
	probe: emitter_probe
	result: Run_Result
	err := run_with_options(
		&result, ".", "null", rejected_driver_allocator(&state),
		{output_mode = .Compact, emitter = probe_emitter, emitter_data = &probe},
	)
	testing.expect(t, state.outer_seen)
	testing.expect(t, state.rejected)
	testing.expect_value(t, err.kind, Run_Error_Kind.Cleanup)
	testing.expect_value(t, probe.calls, 0)
	outer_address := rawptr(raw_data(state.outer_memory))
	outer_size := len(state.outer_memory)
	rejected_address := rawptr(raw_data(state.rejected_memory))
	rejected_size := len(state.rejected_memory)
	testing.expect_value(t, rawptr(result.evaluator), outer_address)
	testing.expect_value(t, len(result.evaluator_memory), outer_size)
	allocation_count := state.allocation_count

	testing.expect_value(
		t, destroy_run_result(&result), runtime.Allocator_Error(.Invalid_Argument),
	)
	// The inner allocation was released at its stable address and actual size;
	// the exact outer allocation remains published after its own failed Free.
	testing.expect_value(t, len(state.rejected_memory), 0)
	testing.expect_value(t, rawptr(result.evaluator), outer_address)
	testing.expect_value(t, len(result.evaluator_memory), outer_size)
	testing.expect_value(t, state.free_addresses[0], rejected_address)
	testing.expect_value(t, state.free_sizes[0], rejected_size)
	testing.expect_value(t, state.allocation_count, allocation_count)
	testing.expect_value(t, probe.calls, 0)

	testing.expect_value(t, destroy_run_result(&result), runtime.Allocator_Error(nil))
	testing.expect_value(t, state.live, 0)
	free_count := state.free_count
	testing.expect_value(t, destroy_run_result(&result), runtime.Allocator_Error(nil))
	testing.expect_value(t, state.free_count, free_count)
	testing.expect_value(t, state.allocation_count, allocation_count)
	testing.expect_value(t, probe.calls, 0)
}
