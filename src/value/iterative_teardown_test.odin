package value

import "base:runtime"
import "core:testing"

ITERATIVE_TEARDOWN_DEPTH :: 10_000

@(private)
wrap_array_take :: proc(t: ^testing.T, child: ^Value, allocator: runtime.Allocator) -> Value {
	result, create_error := array_value(allocator)
	testing.expect_value(t, array_error_kind(&create_error), Array_Error.None)
	if array_error_kind(&create_error) != .None do return {}
	displaced, append_error := array_append_take(&result, child)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, kind_of(&displaced), Kind.Invalid)
	if array_error_kind(&append_error) != .None {
		destroy_value(&result)
		return {}
	}
	return result
}

@(private)
wrap_object_take :: proc(t: ^testing.T, child: ^Value, allocator: runtime.Allocator) -> Value {
	result, create_error := object_value(allocator)
	testing.expect_value(t, object_error_kind(&create_error), Object_Error.None)
	if object_error_kind(&create_error) != .None do return {}
	key, key_error := string_value("child", allocator)
	testing.expect_value(t, constructor_error_kind(&key_error), Error.None)
	if constructor_error_kind(&key_error) != .None {
		destroy_value(&result)
		return {}
	}
	duplicate, displaced, set_error := object_set_take(&result, &key, child)
	testing.expect_value(t, object_error_kind(&set_error), Object_Error.None)
	testing.expect_value(t, kind_of(&duplicate), Kind.Invalid)
	testing.expect_value(t, kind_of(&displaced), Kind.Invalid)
	if object_error_kind(&set_error) != .None {
		destroy_value(&key)
		destroy_value(&result)
		return {}
	}
	return result
}

@(test)
ten_thousand_nested_arrays_destroy_with_default_stack :: proc(t: ^testing.T) {
	root := null_value()
	for _ in 0..<ITERATIVE_TEARDOWN_DEPTH {
		root = wrap_array_take(t, &root, context.allocator)
	}
	testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&root), Kind.Invalid)
}

@(test)
ten_thousand_mixed_containers_destroy_with_default_stack :: proc(t: ^testing.T) {
	root := number_value(1)
	for depth in 0..<ITERATIVE_TEARDOWN_DEPTH {
		if depth & 1 == 0 {
			root = wrap_array_take(t, &root, context.allocator)
		} else {
			root = wrap_object_take(t, &root, context.allocator)
		}
	}
	testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&root), Kind.Invalid)
}

iterative_teardown_probe :: struct {
	backing:              runtime.Allocator,
	allocations:          int,
	allocation_attempts:  int,
	successful_frees:     int,
	free_attempts:        int,
	reject_allocations:   bool,
	fail_free_at:         int,
	free_failure_enabled: bool,
}

@(private)
iterative_teardown_probe_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	probe := cast(^iterative_teardown_probe)data
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		probe.allocation_attempts += 1
		if probe.reject_allocations do return nil, .Out_Of_Memory
		memory, err := probe.backing.procedure(
			probe.backing.data, mode, size, alignment, old_memory, old_size, location,
		)
		if err == nil && len(memory) == size do probe.allocations += 1
		return memory, err
	case .Free:
		attempt := probe.free_attempts
		probe.free_attempts += 1
		if probe.free_failure_enabled && attempt == probe.fail_free_at {
			probe.free_failure_enabled = false
			return nil, .Invalid_Pointer
		}
		memory, err := probe.backing.procedure(
			probe.backing.data, mode, size, alignment, old_memory, old_size, location,
		)
		if err == nil do probe.successful_frees += 1
		return memory, err
	case .Resize, .Resize_Non_Zeroed:
		probe.allocation_attempts += 1
		if probe.reject_allocations do return nil, .Out_Of_Memory
		return probe.backing.procedure(
			probe.backing.data, mode, size, alignment, old_memory, old_size, location,
		)
	}
	return nil, .Mode_Not_Implemented
}

@(private)
iterative_teardown_allocator :: proc(probe: ^iterative_teardown_probe) -> runtime.Allocator {
	return {procedure = iterative_teardown_probe_proc, data = probe}
}

@(test)
iterative_teardown_probe_rejects_all_resize_modes :: proc(t: ^testing.T) {
	probe := iterative_teardown_probe{backing = context.allocator}
	allocator := iterative_teardown_allocator(&probe)
	memories: [2][]byte
	for index in 0..<len(memories) {
		memory, err := runtime.mem_alloc(8, 1, allocator)
		testing.expect_value(t, err, runtime.Allocator_Error.None)
		testing.expect_value(t, len(memory), 8)
		memories[index] = memory
	}

	attempts_before_gate := probe.allocation_attempts
	probe.reject_allocations = true
	resize_modes := [2]runtime.Allocator_Mode{.Resize, .Resize_Non_Zeroed}
	for mode, index in resize_modes {
		resized, err := allocator.procedure(
			allocator.data,
			mode,
			16,
			1,
			raw_data(memories[index]),
			len(memories[index]),
		)
		if err == nil && len(resized) > 0 {
			memories[index] = resized
		}
		testing.expect_value(t, err, runtime.Allocator_Error.Out_Of_Memory)
		testing.expect_value(t, len(resized), 0)
	}
	testing.expect_value(t, probe.allocation_attempts, attempts_before_gate + len(resize_modes))

	for memory in memories {
		testing.expect_value(
			t,
			runtime.mem_free_with_size(raw_data(memory), len(memory), allocator),
			runtime.Allocator_Error.None,
		)
	}
	testing.expect_value(t, probe.successful_frees, probe.allocations)
}

@(test)
iterative_teardown_partial_free_failure_is_allocation_free_and_retryable :: proc(t: ^testing.T) {
	probe := iterative_teardown_probe{
		backing = context.allocator,
		fail_free_at = 37,
		free_failure_enabled = true,
	}
	allocator := iterative_teardown_allocator(&probe)
	root := null_value()
	for depth in 0..<128 {
		if depth & 1 == 0 {
			root = wrap_object_take(t, &root, allocator)
		} else {
			root = wrap_array_take(t, &root, allocator)
		}
	}
	allocations_before_destroy := probe.allocation_attempts
	probe.reject_allocations = true

	first_error := destroy_value(&root)
	testing.expect_value(t, first_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect(t, value_is_retiring(&root))
	testing.expect_value(t, probe.allocation_attempts, allocations_before_destroy)
	testing.expect(t, probe.successful_frees > 0)
	testing.expect(t, probe.successful_frees < probe.allocations)

	testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&root), Kind.Invalid)
	testing.expect_value(t, probe.allocation_attempts, allocations_before_destroy)
	testing.expect_value(t, probe.successful_frees, probe.allocations)
	testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.successful_frees, probe.allocations)
}

@(test)
iterative_teardown_preserves_shared_nested_cow_values :: proc(t: ^testing.T) {
	one := number_value(1)
	inner := wrap_array_take(t, &one, context.allocator)
	outer := wrap_object_take(t, &inner, context.allocator)
	alias := clone_value(&outer)

	alias_inner, found := object_get_copy(&alias, "child")
	testing.expect(t, found)
	two := number_value(2)
	displaced, append_error := array_append_take(&alias_inner, &two)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	destroy_value(&displaced)
	key, _ := string_value("child", context.allocator)
	duplicate, old_inner, set_error := object_set_take(&alias, &key, &alias_inner)
	testing.expect_value(t, object_error_kind(&set_error), Object_Error.None)
	destroy_value(&duplicate)
	destroy_value(&old_inner)

	original_inner, original_found := object_get_copy(&outer, "child")
	changed_inner, changed_found := object_get_copy(&alias, "child")
	original_length, original_ok := array_length(&original_inner)
	changed_length, changed_ok := array_length(&changed_inner)
	testing.expect(t, original_found && changed_found && original_ok && changed_ok)
	testing.expect_value(t, original_length, 1)
	testing.expect_value(t, changed_length, 2)
	destroy_value(&original_inner)
	destroy_value(&changed_inner)
	destroy_value(&outer)
	destroy_value(&alias)
}
