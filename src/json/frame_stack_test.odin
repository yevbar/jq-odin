package json

import "base:runtime"
import "core:testing"
import "jq:value"

@(private)
deep_unreachable_suffix :: proc(prefix: string, count: int = MAX_PARSING_DEPTH + 1) -> []byte {
	bytes := make([]byte, len(prefix) + count)
	copy(bytes, prefix)
	for i in len(prefix)..<len(bytes) do bytes[i] = '{'
	return bytes
}

@(private)
expect_bounded_unreachable_suffix :: proc(
	t: ^testing.T,
	prefix: string,
	kind: Scalar_Parse_Error_Kind,
	detection, cause, expected_temp_allocations: int,
) {
	input := deep_unreachable_suffix(prefix)
	defer delete(input)
	initial_bytes, size_ok := frame_stack_allocation_size(INITIAL_FRAME_CAPACITY)
	testing.expect(t, size_ok)
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		allocation_limit = initial_bytes,
	}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = probe_allocator(&probe)
	parsed, err := parse_value(transmute(string)input, context.allocator)
	context.temp_allocator = saved_temp_allocator

	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, kind)
	testing.expect_value(t, err.detection_offset, detection)
	testing.expect(t, err.has_cause_offset)
	testing.expect_value(t, err.cause_offset, cause)
	testing.expect_value(t, probe.allocations, expected_temp_allocations)
	testing.expect(t, probe.maximum_request <= initial_bytes)
	testing.expect_value(t, probe.live, 0)
	testing.expect_value(t, destroy_scalar_parse_error(&err), runtime.Allocator_Error.None)
}

@(test)
unreachable_deep_suffixes_cannot_change_error_or_frame_allocation :: proc(t: ^testing.T) {
	// The first case is the exact accepted blocker. The rest stop at distinct
	// earlier grammar states or completed values before the 10,000 openers.
	expect_bounded_unreachable_suffix(t, "[] }", .Unmatched_Object_Closer, 3, 3, 1)
	expect_bounded_unreachable_suffix(t, "[null true ", .Expected_Separator, 10, 6, 1)
	expect_bounded_unreachable_suffix(t, `{"a" null `, .Expected_Separator, 9, 5, 2)
	expect_bounded_unreachable_suffix(t, `{"a":} `, .Unmatched_Object_Closer, 5, 5, 2)
	expect_bounded_unreachable_suffix(t, "[} ", .Unmatched_Object_Closer, 1, 1, 1)
	expect_bounded_unreachable_suffix(t, "null }", .Unmatched_Object_Closer, 5, 5, 0)
	expect_bounded_unreachable_suffix(t, "[] false ", .Unexpected_Extra_Values, 3, 3, 1)
	expect_bounded_unreachable_suffix(t, "null [] ", .Unexpected_Extra_Values, 5, 5, 1)
}

@(test)
frame_growth_uses_alloc_only_and_has_no_10000_frame_storage_ceiling :: proc(t: ^testing.T) {
	resize_unsupported_modes := [2]bool{true, false}
	for unsupported in resize_unsupported_modes {
		probe := allocator_probe{
			backing = context.allocator,
			fail_after = max(int),
			resize_unsupported = unsupported,
			resize_failure = !unsupported,
		}
		input := nested_null_input(32)
		saved_temp_allocator := context.temp_allocator
		context.temp_allocator = probe_allocator(&probe)
		parsed, err := parse_value(transmute(string)input, context.allocator)
		context.temp_allocator = saved_temp_allocator
		delete(input)
		testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
		testing.expect_value(t, probe.resize_calls, 0)
		testing.expect(t, probe.allocations > 1)
		testing.expect_value(t, probe.live, 0)
		testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
	}

	stack := frame_stack{allocator = context.allocator}
	for i in 0..<12_345 {
		owner := value.invalid_value()
		err := push_container_frame(&stack, &owner, i, .Array)
		testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	}
	testing.expect_value(t, stack.active_count, 12_345)
	cleanup_error := Scalar_Parse_Error{}
	retire_frame_stack(&stack, &cleanup_error)
	testing.expect_value(t, cleanup_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect(t, stack.blocks == nil)
}

@(test)
frame_growth_allocation_failure_and_overflow_are_failure_atomic :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = 1}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = probe_allocator(&probe)
	parsed, err := parse_value("[[]]", context.allocator)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, err.detection_offset, 1)
	testing.expect_value(t, probe.allocations, 2)
	testing.expect_value(t, probe.live, 0)

	oversized := frame_stack_block{capacity = max(int) / 2 + 1}
	stack := frame_stack{blocks = &oversized, allocator = context.allocator}
	overflow_error := grow_frame_stack(&stack, 17)
	testing.expect_value(t, overflow_error.kind, Scalar_Parse_Error_Kind.Size_Overflow)
	testing.expect_value(t, overflow_error.detection_offset, 17)
	testing.expect(t, stack.blocks == &oversized)
	_, size_ok := frame_stack_allocation_size(max(int))
	testing.expect(t, !size_ok)
}

@(test)
growth_mismatch_and_each_live_block_remain_retryable :: proc(t: ^testing.T) {
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_at_plus_one = 2,
		free_fail_at_plus_one = 1,
	}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = probe_allocator(&probe)
	parsed, err := parse_value("[[]]", context.allocator)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, err.cause_kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, probe.live, 1)
	testing.expect_value(t, destroy_scalar_parse_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	testing.expect_value(t, probe.allocations, 2)
	testing.expect_value(t, probe.frees, 3)
}

@(test)
cleanup_retries_after_growth_without_leaks_or_double_frees :: proc(t: ^testing.T) {
	// Eight active frames occupy four linked blocks (capacities 1, 2, 4, 8).
	// Fail each block's first Free in turn. Every earlier success may unlink
	// only the released suffix; the failed block and all predecessors remain
	// reachable from the cleanup error until retry succeeds.
	saved_temp_allocator := context.temp_allocator
	for failed_free in 1..=4 {
		probe := allocator_probe{
			backing = context.allocator,
			fail_after = max(int),
			free_fail_at_plus_one = failed_free,
		}
		input := nested_null_input(8)
		context.temp_allocator = probe_allocator(&probe)
		parsed, err := parse_value(transmute(string)input, context.allocator)
		context.temp_allocator = saved_temp_allocator
		delete(input)
		testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
		testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
		testing.expect_value(t, err.cause_kind, Scalar_Parse_Error_Kind.None)
		testing.expect_value(t, probe.allocations, 4)
		testing.expect_value(t, probe.live, 5 - failed_free)
		testing.expect(t, err.cleanup_frame_blocks != nil)
		testing.expect_value(t, destroy_scalar_parse_error(&err), runtime.Allocator_Error.None)
		testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
		testing.expect_value(t, probe.live, 0)
		testing.expect_value(t, probe.frees, 5)
	}

	bounded := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = SCALAR_PARSE_CLEANUP_RETRY_LIMIT + 1,
	}
	context.temp_allocator = probe_allocator(&bounded)
	bounded_value, bounded_error := parse_value("[[]]", context.allocator)
	context.temp_allocator = saved_temp_allocator
	testing.expect_value(t, value.kind_of(&bounded_value), value.Kind.Invalid)
	result, retries := retry_scalar_parse_error_cleanup(&bounded_error)
	testing.expect_value(t, result, scalar_parse_cleanup_retry_result.Exhausted)
	testing.expect_value(t, retries, SCALAR_PARSE_CLEANUP_RETRY_LIMIT)
	testing.expect(t, bounded.live > 0)
	testing.expect_value(
		t,
		destroy_scalar_parse_error(&bounded_error),
		runtime.Allocator_Error.None,
	)
	testing.expect_value(t, bounded.live, 0)
}

@(test)
active_value_cleanup_failure_retains_frame_cursor_and_count_for_retry :: proc(t: ^testing.T) {
	value_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 2,
	}
	temporary_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	saved_temp_allocator := context.temp_allocator
	context.temp_allocator = probe_allocator(&temporary_probe)
	parsed, err := parse_value(`[[1],`, probe_allocator(&value_probe))
	context.temp_allocator = saved_temp_allocator

	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, err.cause_kind, Scalar_Parse_Error_Kind.Unfinished_Array)
	testing.expect(t, err.cleanup_frame_blocks != nil)
	testing.expect(t, err.cleanup_frame_current != nil)
	testing.expect(t, err.cleanup_frame_count > 0)
	retained_blocks := err.cleanup_frame_blocks
	retained_current := err.cleanup_frame_current
	retained_count := err.cleanup_frame_count

	testing.expect_value(
		t,
		destroy_scalar_parse_error(&err),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect(t, err.cleanup_frame_blocks == retained_blocks)
	testing.expect(t, err.cleanup_frame_current == retained_current)
	testing.expect_value(t, err.cleanup_frame_count, retained_count)

	testing.expect_value(t, destroy_scalar_parse_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value_probe.live, 0)
	testing.expect_value(t, temporary_probe.live, 0)
}
