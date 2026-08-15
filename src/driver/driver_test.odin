package driver

import "base:runtime"
import "core:testing"
import "core:strings"
import compiler "jq:compiler"
import eval "jq:eval"
import json "jq:json"
import program "jq:program"
import syntax "jq:syntax"
import value "jq:value"

@(test)
module_metadata_parameter_arity_counts_jq_formals :: proc(t: ^testing.T) {
	testing.expect_value(t, module_parameter_arity(""), 0)
	testing.expect_value(t, module_parameter_arity("x"), 1)
	testing.expect_value(t, module_parameter_arity("$x; y; $z"), 3)
}

@(test)
module_metadata_extractor_preserves_dependency_and_definition_order :: proc(t: ^testing.T) {
	source := "module {whatever:null}; import \"a\" as foo; import \"data\" as $d; def a: 0; def c: 1;"
	metadata: module_metadata
	err := extract_module_metadata(source, &metadata, context.allocator)
	testing.expect_value(t, err, runtime.Allocator_Error(nil))
	testing.expect_value(t, metadata.module_value, "{whatever:null}")
	testing.expect_value(t, len(metadata.deps), 2)
	testing.expect_value(t, metadata.deps[0].relpath, "a")
	testing.expect_value(t, metadata.deps[0].alias, "foo")
	testing.expect_value(t, metadata.deps[0].is_data, false)
	testing.expect_value(t, metadata.deps[1].relpath, "data")
	testing.expect_value(t, metadata.deps[1].alias, "d")
	testing.expect_value(t, metadata.deps[1].is_data, true)
	testing.expect_value(t, len(metadata.defs), 2)
	testing.expect_value(t, metadata.defs[0], "a/0")
	testing.expect_value(t, metadata.defs[1], "c/0")
	destroy_module_metadata(&metadata, context.allocator)
}

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
recursive_zero_argument_calls_are_bounded_and_catchable :: proc(t: ^testing.T) {
	// Recursive zero-argument calls use evaluator-owned frames.  The depth
	// guard is a jq-style user error, so `try` can recover it as ordinary data
	// instead of terminating the process or reporting internal misuse.
	expect_run(
		t,
		"def f: try f catch .; f",
		"1",
		"\"recursion depth exceeded\"\n",
	)
}

@(test)
unresolved_break_label_in_called_definition_is_compile_error :: proc(t: ^testing.T) {
	result: Run_Result
	err := run(&result, "def f: break $x; f", "null", context.allocator)
	testing.expect_value(t, err.kind, Run_Error_Kind.Filter_Compile)
	testing.expect_value(t, err.compile_kind, compiler.Lower_Error_Kind.Unresolved_Label)
	// The compile span covers `break $x`; the name span covers `$x` for the
	// CLI's jq-compatible `$*label-x` diagnostic.
	testing.expect_value(t, err.compile_error_span.start, 7)
	testing.expect_value(t, err.compile_error_span.end, 15)
	testing.expect_value(t, err.compile_error_name_span.start, 14)
	testing.expect_value(t, err.compile_error_name_span.end, 15)
	destroy_result_test(t, &result)
}

@(test)
recursive_definition_with_local_break_label_remains_valid :: proc(t: ^testing.T) {
	// The callee's label scope is lexical and survives its recursive call edge;
	// validating definition bodies separately must not mistake that cycle for
	// an unresolved label or recurse indefinitely.
	expect_run(t, "def f: label $x | break $x; f", "null", "")
}

@(test)
unresolved_variable_reports_name_and_source_span :: proc(t: ^testing.T) {
	result: Run_Result
	err := run(&result, ". as $foo | [$foo, $bar]", "null", context.allocator)
	testing.expect_value(t, err.kind, Run_Error_Kind.Filter_Compile)
	testing.expect_value(t, err.compile_kind, compiler.Lower_Error_Kind.Unresolved_Variable)
	// jq's caret covers the complete `$bar` token while the name span excludes
	// its sigil for reuse by the CLI formatter.
	testing.expect_value(t, err.compile_error_span.start, 19)
	testing.expect_value(t, err.compile_error_span.end, 23)
	testing.expect_value(t, err.compile_error_name_span.start, 20)
	testing.expect_value(t, err.compile_error_name_span.end, 23)
	destroy_result_test(t, &result)
}

@(test)
invalid_constant_object_key_reports_inner_source_span :: proc(t: ^testing.T) {
	result: Run_Result
	err := run(&result, "{(0):1}", "null", context.allocator)
	testing.expect_value(t, err.kind, Run_Error_Kind.Filter_Compile)
	testing.expect_value(t, err.compile_kind, compiler.Lower_Error_Kind.Invalid_Object_Key)
	testing.expect_value(t, err.compile_error_span.start, 2)
	testing.expect_value(t, err.compile_error_span.end, 3)
	destroy_result_test(t, &result)

	err = run(&result, "{non_const:., (0):1}", "null", context.allocator)
	testing.expect_value(t, err.kind, Run_Error_Kind.Filter_Compile)
	testing.expect_value(t, err.compile_kind, compiler.Lower_Error_Kind.Invalid_Object_Key)
	testing.expect_value(t, err.compile_error_span.start, 15)
	testing.expect_value(t, err.compile_error_span.end, 16)
	destroy_result_test(t, &result)
}

@(test)
invalid_escape_reports_lexical_message_and_span :: proc(t: ^testing.T) {
	result: Run_Result
	err := run(&result, "\"u\\vw\"", "null", context.allocator)
	testing.expect_value(t, err.kind, Run_Error_Kind.Filter_Parse)
	testing.expect_value(t, err.filter_parse_kind, syntax.Parse_Error_Kind.Lexical_Error)
	testing.expect_value(t, err.filter_parse_message, "Invalid escape")
	testing.expect_value(t, err.filter_start, 2)
	testing.expect_value(t, err.filter_end, 4)
	destroy_result_test(t, &result)
}

@(test)
bound_variable_remains_valid_inside_array_constructor :: proc(t: ^testing.T) {
	expect_run(t, ". as $foo | [$foo]", "null", "[\n  null\n]\n")
}

@(test)
parameterized_identity_uses_evaluator_argument_frame :: proc(t: ^testing.T) {
	// This exact fixture bypasses module/text expansion and exercises the
	// parser -> compiler -> evaluator two-edge Call contract.
	expect_run(t, "def id(x): x; id(1)", "null", "1\n")
	// Comma is a generator inside the single filter-valued argument.
	expect_run(t, "def id(x): x; id(1,2)", "null", "1\n2\n")
	expect_run(t, "def id(x): x; id(1;2)", "null", "", .Filter_Parse)
}

@(test)
parameterized_simple_arithmetic_uses_evaluator_argument_frame :: proc(t: ^testing.T) {
	// Additive bodies are structurally validated and run through the same
	// argument/callee frames; unsupported bodies continue to use the bridge.
	expect_run(t, "def twice(x): x+x; twice(1)", "null", "2\n")
	expect_run(t, "def inc(x): x+1; inc((1,2))", "null", "2\n3\n")
	expect_run(t, "def dec(x): x-1; dec(3)", "null", "2\n")
	expect_run(t, "def mul(x): x*2; mul(3)", "null", "6\n")
	expect_run(t, "def half(x): x/2; half(3)", "null", "1.5\n")
	expect_run(t, "def rem(x): x%2; rem(5)", "null", "1\n")
	expect_run(t, "def div(x): x/0; try div(1) catch .", "null", "\"number (1) and number (0) cannot be divided because the divisor is zero\"\n")
	expect_run(t, "def dec(x): x-1; try dec(\"a\") catch .", "null", "\"string (\\\"a\\\") and number (1) cannot be subtracted\"\n")
	// `.` is not the declaration parameter even though both lower to Identity;
	// this body therefore remains on the mature module path.
	expect_run(t, "def keep(x): .; keep(1)", "{\"a\":0}", "{\n  \"a\": 0\n}\n")
}

@(test)
parameterized_simple_route_is_ast_validated :: proc(t: ^testing.T) {
	testing.expect(t, parameterized_simple_definition("def twice(x): x+x; twice(1)", context.allocator))
	testing.expect(t, parameterized_simple_definition("def inc(x): x+1; inc((1,2))", context.allocator))
	testing.expect(t, parameterized_simple_definition("def dec(x): x-1; dec(3)", context.allocator))
	testing.expect(t, parameterized_simple_definition("def mul(x): x*2; mul(3)", context.allocator))
	testing.expect(t, parameterized_simple_definition("def half(x): x/2; half(3)", context.allocator))
	testing.expect(t, parameterized_simple_definition("def rem(x): x%2; rem(5)", context.allocator))
	testing.expect(t, !parameterized_simple_definition("def keep(x): .; keep(1)", context.allocator))
}

@(test)
generated_path_assignment_preserves_result_diagnostic :: proc(t: ^testing.T) {
	// Dynamic path filters are evaluated by the assignment frame so jq's
	// result-bearing invalid-path diagnostic remains catchable.
	expect_run(t, "try (def x: reverse; x=10) catch .", "[0,1,2]", "\"Invalid path expression with result [2,1,0]\"\n")
	expect_run(t, "try (def x: [\"a\"]; x=10) catch .", "null", "\"Invalid path expression with result [\\\"a\\\"]\"\n")
	expect_run(t, "try (def x: 1; x=10) catch .", "null", "\"Invalid path expression with result 1\"\n")
	// Literal paths retain their existing type-specific assignment errors.
	expect_run(t, "try (1 | .[1,2] = 10) catch .", "null", "\"Cannot index number with number\"\n")
}

@(test)
ordinary_string_interpolation_evaluates_and_stringifies_each_result :: proc(t: ^testing.T) {
	expect_run(t, `"inter\("pol" + "ation")"`, "null", `"interpolation"
`)
	expect_run(t, `"<b>\(.)</b>"`, `"<&"`, `"<b><&</b>"
`)
	expect_run(t, `"item=\(.[])"`, `[1,true,null,{"a":2}]`, `"item=1"
"item=true"
"item=null"
"item={\"a\":2}"
`)
}

@(test)
object_binding_shorthand_uses_name_as_key_and_variable_as_value :: proc(t: ^testing.T) {
	expect_run(t, `"v" as $x | {$x}`, "null", "{\n  \"x\": \"v\"\n}\n")
}

@(test)
computed_object_key_variable_stream_is_evaluated :: proc(t: ^testing.T) {
	expect_run(t, `"k" as $k | {($k): 1}`, "null", "{\n  \"k\": 1\n}\n")
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
	expect_run_mode(t, ".", "\"x\"", "x\n", .Raw)
	expect_run_mode(t, ".", "{\"a\":[1,2]}", "{\n  \"a\": [\n    1,\n    2\n  ]\n}\n", .Raw)
	expect_run_mode(t, ".", "{\"a\":[1,2]}", "{\"a\":[1,2]}\n", .Raw_Compact)
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
module_search_metadata_uses_and_releases_custom_allocator :: proc(t: ^testing.T) {
	state := test_allocator_state{backing = context.allocator}
	paths, paths_error := module_search_paths("./child", []string{"/base"}, test_allocator(&state))
	testing.expect_value(t, paths_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, len(paths), 2)
	testing.expect_value(t, paths[0], "/base/./child")
	testing.expect_value(t, paths[1], "/base")
	destroy_module_search_paths(paths, "./child", test_allocator(&state))
	testing.expect_value(t, state.live, 0)

	failing_state := test_allocator_state{backing = context.allocator, allocation_at = 1}
	failed_paths, failed_error := module_search_paths(
		"./child", []string{"/base"}, test_allocator(&failing_state),
	)
	testing.expect_value(t, len(failed_paths), 0)
	testing.expect_value(t, failed_error, runtime.Allocator_Error(.Out_Of_Memory))
	testing.expect_value(t, failing_state.live, 0)

	// With no -L paths, the relative metadata string still originates in the
	// caller's filter.  The loader must clone it before the destruction helper
	// releases the returned search-path array.
	no_path_state := test_allocator_state{backing = context.allocator}
	no_path, no_path_error := module_search_paths(
		"./relative", []string{}, test_allocator(&no_path_state),
	)
	testing.expect_value(t, no_path_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, len(no_path), 1)
	testing.expect_value(t, no_path[0], "./relative")
	destroy_module_search_paths(no_path, "./relative", test_allocator(&no_path_state))
	testing.expect_value(t, no_path_state.live, 0)

	empty_state := test_allocator_state{backing = context.allocator}
	empty_paths, empty_error := module_search_paths(
		"", []string{"/base"}, test_allocator(&empty_state),
	)
	testing.expect_value(t, empty_error, runtime.Allocator_Error(nil))
	destroy_module_search_paths(empty_paths, "", test_allocator(&empty_state))
	testing.expect_value(t, empty_state.live, 0)
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
module_data_array_literal_frames_adjacent_scalar_and_container :: proc(t: ^testing.T) {
	array, err := module_data_array_literal("1[2]", context.allocator)
	testing.expect_value(t, err, runtime.Allocator_Error(nil))
	testing.expect_value(t, array, "[1,[2]]")
	delete(array, context.allocator)
}

@(test)
module_data_array_literal_preserves_object_value :: proc(t: ^testing.T) {
	array, err := module_data_array_literal(`{"x":1}
`, context.allocator)
	testing.expect_value(t, err, runtime.Allocator_Error(nil))
	testing.expect_value(t, array, `[{"x":1}]`)
	delete(array, context.allocator)
}

@(test)
module_data_array_literal_rejects_malformed_trailing_stream :: proc(t: ^testing.T) {
	array, err := module_data_array_literal("1\n{bad", context.allocator)
	testing.expect_value(t, array, "")
	testing.expect_value(t, err, runtime.Allocator_Error.Invalid_Argument)
}

@(test)
module_data_reference_index_expands_object_literal :: proc(t: ^testing.T) {
	imports: [dynamic]module_data_import
	owned_data, data_error := strings.clone(`[{"x":1}]`, context.allocator)
	testing.expect_value(t, data_error, runtime.Allocator_Error(nil))
	owned_alias, alias_error := strings.clone("c", context.allocator)
	testing.expect_value(t, alias_error, runtime.Allocator_Error(nil))
	_, append_error := append(&imports, module_data_import{alias = owned_alias, data = owned_data})
	testing.expect_value(t, append_error, runtime.Allocator_Error(nil))
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	data_input := ""
	data_owned := false
	append_data := false
	scalar_add := false
	replace_input := false
	scalar_field_error := false
	cleanup_value: value.Value
	cleanup_parse_error: json.Scalar_Parse_Error
	ok := module_expand_data_references(
		"$c[0]", imports, &builder, &data_input, &data_owned,
		&append_data, &scalar_add, &replace_input, &scalar_field_error,
		&cleanup_value, &cleanup_parse_error, context.allocator,
	)
	testing.expect(t, ok)
	testing.expect(t, !scalar_field_error)
	testing.expect_value(t, strings.to_string(builder), `{"x":1}`)
	testing.expect_value(t, value.destroy_value(&cleanup_value), runtime.Allocator_Error(nil))
	testing.expect_value(t, json.destroy_scalar_parse_error(&cleanup_parse_error), runtime.Allocator_Error(nil))
	strings.builder_destroy(&builder)
	destroy_module_data_imports(&imports, context.allocator)
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
	testing.expect_value(t, outcome.kind, Module_Error_Kind.Syntax_Error)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
module_import_accepts_dollar_namespace_alias :: proc(t: ^testing.T) {
	name, alias, search, next, ok, unsupported := parse_module_import(
		"import \"answer\" as $a;", 0,
	)
	testing.expect_value(t, name, "answer")
	testing.expect_value(t, alias, "a")
	testing.expect_value(t, search, "")
	testing.expect_value(t, next, len("import \"answer\" as $a;"))
	testing.expect_value(t, ok, true)
	testing.expect_value(t, unsupported, false)
}

@(test)
module_include_accepts_search_metadata :: proc(t: ^testing.T) {
	name, search, next, ok, unsupported := parse_module_include(
		"include \"foo\" {search:\"./lib\"};", 0,
	)
	testing.expect_value(t, name, "foo")
	testing.expect_value(t, search, "./lib")
	testing.expect_value(t, next, len("include \"foo\" {search:\"./lib\"};"))
	testing.expect_value(t, ok, true)
	testing.expect_value(t, unsupported, false)
}

@(test)
module_include_accepts_quoted_search_metadata :: proc(t: ^testing.T) {
	name, search, next, ok, unsupported := parse_module_include(
		"include \"foo\" {\"search\":\"./lib\"};", 0,
	)
	testing.expect_value(t, name, "foo")
	testing.expect_value(t, search, "./lib")
	testing.expect_value(t, next, len("include \"foo\" {\"search\":\"./lib\"};"))
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
	testing.expect(t, outcome.kind == .Unsupported_Syntax || outcome.kind == .Undefined_Function || outcome.kind == .Syntax_Error)
	strings.builder_destroy(&builder)
}

module_expansion_matches :: proc(
	t: ^testing.T,
	definition_source, call_source, expected: string,
) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions(definition_source, &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source(call_source, definitions, &builder, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(builder), expected)
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
module_definition_bodies_keep_filter_boundaries :: proc(t: ^testing.T) {
	// A definition body is one jq filter expression, even when its caller
	// continues with a lower-precedence operator.
	module_expansion_matches(t, "def value: 1 + 2;", "value * 3", "( 1 + 2) * 3")
	module_expansion_matches(t, "def value: (1 + 2);", "value", "( (1 + 2))")
	module_expansion_matches(t, "def values: 1, 2 | .;", "values", "( 1, 2 | .)")
}

@(test)
module_definition_call_arguments_keep_filter_boundaries :: proc(t: ^testing.T) {
	module_expansion_matches(t, "def identity(x): x;", "identity(1, 2)", "( (1, 2))")
}

@(test)
filter_parameter_body_without_operator_whitespace_is_validated :: proc(t: ^testing.T) {
	// Bare filter parameters are replaced only in the temporary validation
	// source; expansion still substitutes the original filter argument.
	module_expansion_matches(t, "def increment(x): x+1;", "increment(2)", "( (2)+1)")
}

@(test)
filter_parameter_literal_postfix_indexes_avoid_grouping :: proc(t: ^testing.T) {
	// The parser accepts a literal postfix index but not a parenthesized
	// expression inside the brackets.  Keep the argument literal at this
	// narrow textual-expansion boundary; non-literals retain normal grouping.
	module_expansion_matches(
		t, "def field(x): .[x];", "field(\"a\")", "( .[\"a\"])",
	)
	module_expansion_matches(
		t, "def index(x): .[x];", "index(0)", "( .[0])",
	)
	module_expansion_matches(
		t, "def spaced(x): .[ x ];", "spaced(\"a\")", "( .[ \"a\" ])",
	)
	module_expansion_matches(
		t, "def field(x): .[x];", "field(.a)", "( .[(.a)])",
	)
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
module_definition_overloads_match_name_and_arity :: proc(t: ^testing.T) {
	module_expansion_matches(
		t, "def f: 1; def f(x): x;", "f", "( 1)",
	)
	module_expansion_matches(
		t, "def f: 1; def f(x): x;", "f(2)", "( (2))",
	)
	module_expansion_matches(
		t, "def f(x): x; def f: 1;", "f(2)", "( (2))",
	)
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
	testing.expect_value(t, strings.to_string(builder), "((7) as $x |  $x)")
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
dollar_parameters_preserve_value_cardinality_and_order :: proc(t: ^testing.T) {
	module_expansion_matches(
		t, "def dup($x): $x, $x;", "dup(1,2)", "((1,2) as $x |  $x, $x)",
	)
}

@(test)
multiple_dollar_parameters_use_independent_bindings :: proc(t: ^testing.T) {
	module_expansion_matches(
		t, "def pair($x;$y): [$x,$y];", "pair(1;2)",
		"((1) as $x | (2) as $y |  [$x,$y])",
	)
}

@(test)
module_value_parameter_binding_handles_start_and_nested_filter_calls :: proc(t: ^testing.T) {
	module_expansion_matches(
		t, "def x: 42; def f($x): x;", "f(1)",
		"((1) as $x |  ( 42))",
	)
}

@(test)
unbound_dollar_name_is_not_a_definition_call :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def name: 42;", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source("$name", definitions, &builder, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(builder), "$name")
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
module_call_argument_comments_do_not_split_semicolons :: proc(t: ^testing.T) {
	args: [dynamic]string
	close, count, ok := module_call_arguments(
		"identity(1 # ; this is a comment\n)", len("identity"), &args,
	)
	testing.expect(t, ok)
	testing.expect_value(t, close, len("identity(1 # ; this is a comment\n)")-1)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, args[0], "1 # ; this is a comment\n")
	delete(args)
	wide: [dynamic]string
	_, wide_count, wide_ok := module_call_arguments(
		"f(1;2;3;4;5;6;7;8;9;10;11;12;13;14;15;16;17)", 1, &wide,
	)
	testing.expect(t, wide_ok)
	testing.expect_value(t, wide_count, 17)
	testing.expect_value(t, wide[16], "17")
	delete(wide)
}

@(test)
module_boundary_write_failure_releases_cloned_arguments :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def identity(x): x;", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	state := test_allocator_state{backing = context.allocator, allocation_at = 3}
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, test_allocator(&state))
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source(
		"identity(1)", definitions, &builder, &stack, 0, "", {}, 0,
		test_allocator(&state),
	)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.Read_Failure)
	strings.builder_destroy(&builder)
	testing.expect_value(t, state.live, 0)
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
module_filter_expansion_alpha_renames_callee_bindings :: proc(t: ^testing.T) {
	module_expansion_matches(
		t, "def id(x): . as $x | x;", "id(1)",
		"( . as $__jq_module_scope_0_0 | (1))",
	)
}

@(test)
module_expansion_preserves_self_recursive_calls_for_runtime :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	outcome := find_module_definitions(
		"def countdown(x): if x == 0 then 0 else countdown(x - 1) end;",
		&definitions, context.allocator,
	)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source(
		"countdown(.)", definitions, &builder, &stack, 0, "", {}, 0, context.allocator,
	)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(builder), "0")
	strings.builder_destroy(&builder)
	destroy_module_definitions(&definitions, context.allocator)
}

@(test)
module_expansion_evaluates_literal_factorial_definition :: proc(t: ^testing.T) {
	module_expansion_matches(
		t,
		"def fact(x): if x == 0 then 1 else x * fact(x - 1) end;",
		"fact(3)",
		"6",
	)
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
qualified_module_callable_lookup_preserves_namespace_and_arity :: proc(t: ^testing.T) {
	definitions: [dynamic]module_definition
	make_error: runtime.Allocator_Error
	definitions, make_error = make([dynamic]module_definition, 0, 1, context.allocator)
	testing.expect_value(t, make_error, runtime.Allocator_Error(nil))
	name, name_error := strings.clone("foo::a", context.allocator)
	parameters, parameters_error := strings.clone("", context.allocator)
	body, body_error := strings.clone("\"a\"", context.allocator)
	testing.expect_value(t, name_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, parameters_error, runtime.Allocator_Error(nil))
	testing.expect_value(t, body_error, runtime.Allocator_Error(nil))
	_, append_error := append(&definitions, module_definition{
		name = name, parameters = parameters, body = body, active = true,
	})
	testing.expect_value(t, append_error, runtime.Allocator_Error(nil))
	entry, found := module_callable_lookup("foo::a", definitions)
	testing.expect(t, found)
	testing.expect_value(t, entry.definition_index, 0)
	testing.expect_value(t, entry.namespace, "foo")
	testing.expect_value(t, entry.local_name, "a")
	testing.expect_value(t, entry.arity, 0)
	_, found = module_callable_lookup("a", definitions)
	testing.expect(t, !found)
	_, found = module_callable_lookup("bar::a", definitions)
	testing.expect(t, !found)
	_, found = module_callable_lookup("foo::", definitions)
	testing.expect(t, !found)
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
module_expansion_does_not_treat_filter_commas_as_object_shorthand :: proc(t: ^testing.T) {
	module_expansion_matches(
		t, "def f: 1; def g: 2; def h: 3;", "f, g, h",
		"( 1), ( 2), ( 3)",
	)
}

@(test)
module_object_shorthand_handles_more_than_64_nested_objects :: proc(t: ^testing.T) {
	builder: strings.Builder
	_, init_error := strings.builder_init(&builder, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error(nil))
	for _ in 0..<65 do testing.expect_value(t, strings.write_string(&builder, "{"), 1)
	testing.expect_value(t, strings.write_string(&builder, "x"), 1)
	for _ in 0..<65 do testing.expect_value(t, strings.write_string(&builder, "}"), 1)
	source := strings.to_string(builder)
	definitions: [dynamic]module_definition
	outcome := find_module_definitions("def x: 42;", &definitions, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	expanded: strings.Builder
	_, expanded_error := strings.builder_init(&expanded, context.allocator)
	testing.expect_value(t, expanded_error, runtime.Allocator_Error(nil))
	stack: [module_loader_depth]int
	outcome = module_expand_source(source, definitions, &expanded, &stack, 0, "", {}, 0, context.allocator)
	testing.expect_value(t, outcome.kind, Module_Error_Kind.None)
	testing.expect_value(t, strings.to_string(expanded), source)
	strings.builder_destroy(&expanded)
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
prepare_filter_preserves_owner_when_cleanup_retry_fails :: proc(t: ^testing.T) {
	state := test_allocator_state{
		backing = context.allocator,
		free_at = 1,
		free_failures_remaining = 2,
	}
	prepared: Compiled_Filter
	err := prepare_filter(&prepared, ".a.", test_allocator(&state))
	testing.expect_value(t, err.kind, Run_Error_Kind.Cleanup)
	testing.expect_value(t, err.resource_error, runtime.Allocator_Error(.Invalid_Argument))
	testing.expect(t, prepared.owner.self == &prepared.owner)
	testing.expect_value(t, destroy_compiled_filter(&prepared), runtime.Allocator_Error(.Invalid_Argument))
	testing.expect_value(t, destroy_compiled_filter(&prepared), runtime.Allocator_Error(nil))
	testing.expect_value(t, state.live, 0)
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
