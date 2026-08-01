package eval

import "base:runtime"
import "core:mem"
import "core:sync"
import "core:testing"
import "core:thread"

@(private)
fail_allocator_state :: struct {
	backing:              runtime.Allocator,
	call:                 int,
	resize_calls:         int,
	fail_at:              int,
	failed:               bool,
	free_calls:            int,
	fail_free_at:          int,
	reject_free_count:     int,
	free_error:            runtime.Allocator_Error,
	free_failed:           bool,
	retired:              bool,
	called_while_retired: bool,
}

@(private)
fail_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^fail_allocator_state)data
	if state.retired {
		state.called_while_retired = true
	}
	switch mode {
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		if mode == .Resize || mode == .Resize_Non_Zeroed {
			state.resize_calls += 1
		}
		state.call += 1
		if state.call == state.fail_at {
			state.failed = true
			return nil, .Out_Of_Memory
		}
	case .Free:
		state.free_calls += 1
		if state.free_calls >= state.fail_free_at && state.reject_free_count > 0 {
			state.reject_free_count -= 1
			state.free_failed = true
			if state.free_error == .Mode_Not_Implemented {
				_, _ = state.backing.procedure(
					state.backing.data,
					mode,
					size,
					alignment,
					old_memory,
					old_size,
					loc,
				)
			}
			return nil, state.free_error
		}
	case .Free_All, .Query_Features, .Query_Info:
	}
	return state.backing.procedure(
		state.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		loc,
	)
}

@(private)
allocation_scope :: struct {
	previous: runtime.Allocator,
	tracker:  mem.Tracking_Allocator,
}

@(private)
allocation_scope_begin :: proc(scope: ^allocation_scope) {
	scope.previous = context.allocator
	mem.tracking_allocator_init(&scope.tracker, scope.previous)
	scope.tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	context.allocator = mem.tracking_allocator(&scope.tracker)
}

@(private)
allocation_scope_end :: proc(t: ^testing.T, scope: ^allocation_scope) {
	context.allocator = scope.previous
	testing.expect_value(t, len(scope.tracker.allocation_map), 0)
	testing.expect_value(t, len(scope.tracker.bad_free_array), 0)
	mem.tracking_allocator_destroy(&scope.tracker)
}

@(private)
prototype_test_state :: proc(machine: prototype_machine) -> ^prototype_machine_state {
	sync.mutex_lock(&prototype_registry_mutex)
	defer sync.mutex_unlock(&prototype_registry_mutex)
	return prototype_find_state_locked(machine)
}

@(private)
prototype_test_machine_state :: proc(machine: prototype_machine) -> prototype_state {
	state := prototype_test_state(machine)
	if state != nil {
		return state.state
	}
	return machine.terminal
}

@(private)
expect_output :: proc(
	t: ^testing.T,
	result: prototype_step,
	input, left, right: i64,
) {
	testing.expect_value(t, result.kind, prototype_step_kind.output)
	testing.expect_value(t, result.input, input)
	testing.expect_value(t, result.left_component, left)
	testing.expect_value(t, result.right_component, right)
}

@(test)
prototype_zero_one_many_are_ordered_and_resumable :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	zero: prototype_machine
	testing.expect(t, prototype_machine_init(&zero))
	zero_node, zero_ok := prototype_add_empty(&zero)
	testing.expect(t, zero_ok)
	testing.expect(t, prototype_start_single(&zero, zero_node, 100))
	testing.expect_value(t, prototype_step_machine(&zero).kind, prototype_step_kind.exhausted)

	one: prototype_machine
	testing.expect(t, prototype_machine_init(&one))
	one_node, one_ok := prototype_add_values(&one, []i64{7})
	testing.expect(t, one_ok)
	testing.expect(t, prototype_start_single(&one, one_node, 10))
	expect_output(t, prototype_step_machine(&one), 10, 0, 7)
	testing.expect_value(t, prototype_step_machine(&one).kind, prototype_step_kind.exhausted)

	many: prototype_machine
	testing.expect(t, prototype_machine_init(&many))
	many_node, many_ok := prototype_add_values(&many, []i64{3, 1, 4})
	testing.expect(t, many_ok)
	testing.expect(t, prototype_start_single(&many, many_node, 10))
	many_components := [3]i64{3, 1, 4}
	for component in many_components {
		expect_output(t, prototype_step_machine(&many), 10, 0, component)
		testing.expect_value(t, prototype_test_machine_state(many), prototype_state.active)
	}
	testing.expect_value(t, prototype_step_machine(&many).kind, prototype_step_kind.exhausted)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_cartesian_emits_uncombined_components :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	left, left_ok := prototype_add_values(&machine, []i64{1, 2})
	right, right_ok := prototype_add_values(&machine, []i64{10, 20, 30})
	testing.expect(t, left_ok && right_ok)
	testing.expect(t, prototype_start_cartesian(&machine, left, right, 7))

	expected := [6][2]i64{{1, 10}, {1, 20}, {1, 30}, {2, 10}, {2, 20}, {2, 30}}
	for pair in expected {
		expect_output(t, prototype_step_machine(&machine), 7, pair[0], pair[1])
	}
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_cartesian_terminal_errors_preserve_order :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	left_error: prototype_machine
	testing.expect(t, prototype_machine_init(&left_error))
	left, left_ok := prototype_add_values_then_error(&left_error, []i64{1, 2}, 41)
	right, right_ok := prototype_add_values(&left_error, []i64{10, 20})
	testing.expect(t, left_ok && right_ok)
	testing.expect(t, prototype_start_cartesian(&left_error, left, right, 0))
	left_error_pairs := [4][2]i64{{1, 10}, {1, 20}, {2, 10}, {2, 20}}
	for pair in left_error_pairs {
		expect_output(t, prototype_step_machine(&left_error), 0, pair[0], pair[1])
	}
	left_result := prototype_step_machine(&left_error)
	testing.expect_value(t, left_result.kind, prototype_step_kind.runtime_error)
	testing.expect_value(t, left_result.error_code, 41)
	testing.expect_value(t, prototype_step_machine(&left_error).error_code, 41)

	right_error: prototype_machine
	testing.expect(t, prototype_machine_init(&right_error))
	left, left_ok = prototype_add_values(&right_error, []i64{1, 2})
	right, right_ok = prototype_add_values_then_error(&right_error, []i64{10, 20}, 42)
	testing.expect(t, left_ok && right_ok)
	testing.expect(t, prototype_start_cartesian(&right_error, left, right, 0))
	expect_output(t, prototype_step_machine(&right_error), 0, 1, 10)
	expect_output(t, prototype_step_machine(&right_error), 0, 1, 20)
	right_result := prototype_step_machine(&right_error)
	testing.expect_value(t, right_result.kind, prototype_step_kind.runtime_error)
	testing.expect_value(t, right_result.error_code, 42)
	testing.expect_value(t, prototype_step_machine(&right_error).error_code, 42)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_cartesian_active_right_error_preempts_left_progress :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	left, left_ok := prototype_add_values_then_error(&machine, []i64{1, 2}, 41)
	right, right_ok := prototype_add_values_then_error(&machine, []i64{10}, 42)
	testing.expect(t, left_ok && right_ok)
	testing.expect(t, prototype_start_cartesian(&machine, left, right, 7))

	expect_output(t, prototype_step_machine(&machine), 7, 1, 10)
	right_error := prototype_step_machine(&machine)
	testing.expect_value(t, right_error.kind, prototype_step_kind.runtime_error)
	testing.expect_value(t, right_error.error_code, 42)
	testing.expect_value(t, prototype_step_machine(&machine).error_code, 42)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_cartesian_empty_right_advances_left_to_terminal_error :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	left, left_ok := prototype_add_values_then_error(&machine, []i64{1, 2}, 41)
	right, right_ok := prototype_add_empty(&machine)
	testing.expect(t, left_ok && right_ok)
	testing.expect(t, prototype_start_cartesian(&machine, left, right, 7))

	left_error := prototype_step_machine(&machine)
	testing.expect_value(t, left_error.kind, prototype_step_kind.runtime_error)
	testing.expect_value(t, left_error.error_code, 41)
	for _ in 0..<3 {
		replayed := prototype_step_machine(&machine)
		testing.expect_value(t, replayed.kind, prototype_step_kind.runtime_error)
		testing.expect_value(t, replayed.error_code, 41)
	}

	allocation_scope_end(t, &scope)
}

@(test)
prototype_empty_propagates_through_cartesian :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	empty_left: prototype_machine
	testing.expect(t, prototype_machine_init(&empty_left))
	left_empty, left_empty_ok := prototype_add_empty(&empty_left)
	right_values, right_values_ok := prototype_add_values(&empty_left, []i64{1, 2})
	testing.expect(t, left_empty_ok && right_values_ok)
	testing.expect(t, prototype_start_cartesian(&empty_left, left_empty, right_values, 0))
	testing.expect_value(t, prototype_step_machine(&empty_left).kind, prototype_step_kind.exhausted)

	empty_right: prototype_machine
	testing.expect(t, prototype_machine_init(&empty_right))
	left_values, left_values_ok := prototype_add_values(&empty_right, []i64{1, 2})
	right_empty, right_empty_ok := prototype_add_empty(&empty_right)
	testing.expect(t, left_values_ok && right_empty_ok)
	testing.expect(t, prototype_start_cartesian(&empty_right, left_values, right_empty, 0))
	testing.expect_value(t, prototype_step_machine(&empty_right).kind, prototype_step_kind.exhausted)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_nested_scoped_stops_resume_each_enclosing_continuation :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	inner_values, ok1 := prototype_add_values_then_error(&machine, []i64{1}, 73)
	inner_continuation, ok2 := prototype_add_values(&machine, []i64{3})
	testing.expect(t, ok1 && ok2)
	inner_scope, ok3 := prototype_add_limited_then(
		&machine,
		inner_values,
		1,
		inner_continuation,
	)
	outer_continuation, ok4 := prototype_add_values(&machine, []i64{4})
	testing.expect(t, ok3 && ok4)
	outer_scope, ok5 := prototype_add_limited_then(
		&machine,
		inner_scope,
		2,
		outer_continuation,
	)
	testing.expect(t, ok5)
	testing.expect(t, prototype_start_single(&machine, outer_scope, 0))

	expected := [3]i64{1, 3, 4}
	for component in expected {
		expect_output(t, prototype_step_machine(&machine), 0, 0, component)
	}
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_repeated_inner_stop_acknowledges_child_once :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	inner, inner_ok := prototype_add_values(&machine, []i64{1, 2})
	continuation, continuation_ok := prototype_add_values(&machine, []i64{3, 5})
	scope_node, scope_ok := prototype_add_limited_then(
		&machine,
		inner,
		10,
		continuation,
	)
	testing.expect(t, inner_ok && continuation_ok && scope_ok)
	testing.expect(t, prototype_start_single(&machine, scope_node, 0))

	expect_output(t, prototype_step_machine(&machine), 0, 0, 1)
	testing.expect(t, prototype_stop_inner(&machine))
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	expect_output(t, prototype_step_machine(&machine), 0, 0, 3)
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	expect_output(t, prototype_step_machine(&machine), 0, 0, 5)
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_explicit_innermost_stop_is_scoped :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	inner_values, ok1 := prototype_add_values(&machine, []i64{1, 2})
	inner_continuation, ok2 := prototype_add_values(&machine, []i64{3})
	inner_scope, ok3 := prototype_add_limited_then(
		&machine,
		inner_values,
		10,
		inner_continuation,
	)
	outer_continuation, ok4 := prototype_add_values(&machine, []i64{4})
	outer_scope, ok5 := prototype_add_limited_then(
		&machine,
		inner_scope,
		10,
		outer_continuation,
	)
	testing.expect(t, ok1 && ok2 && ok3 && ok4 && ok5)
	testing.expect(t, prototype_start_single(&machine, outer_scope, 0))

	expect_output(t, prototype_step_machine(&machine), 0, 0, 1)
	testing.expect(t, prototype_stop_inner(&machine))
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	expect_output(t, prototype_step_machine(&machine), 0, 0, 3)
	testing.expect(t, prototype_stop_inner(&machine))
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	expect_output(t, prototype_step_machine(&machine), 0, 0, 4)
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_nested_empty_resumes_outer_scopes :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	empty, ok1 := prototype_add_empty(&machine)
	three, ok2 := prototype_add_values(&machine, []i64{3})
	inner_scope, ok3 := prototype_add_limited_then(&machine, empty, 1, three)
	four, ok4 := prototype_add_values(&machine, []i64{4})
	outer_scope, ok5 := prototype_add_limited_then(&machine, inner_scope, 2, four)
	testing.expect(t, ok1 && ok2 && ok3 && ok4 && ok5)
	testing.expect(t, prototype_start_single(&machine, outer_scope, 0))

	expect_output(t, prototype_step_machine(&machine), 0, 0, 3)
	expect_output(t, prototype_step_machine(&machine), 0, 0, 4)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_nested_error_terminates_all_enclosing_continuations :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	inner_values, ok1 := prototype_add_values_then_error(&machine, []i64{1}, 73)
	three, ok2 := prototype_add_values(&machine, []i64{3})
	inner_scope, ok3 := prototype_add_limited_then(&machine, inner_values, 2, three)
	four, ok4 := prototype_add_values(&machine, []i64{4})
	outer_scope, ok5 := prototype_add_limited_then(&machine, inner_scope, 2, four)
	testing.expect(t, ok1 && ok2 && ok3 && ok4 && ok5)
	testing.expect(t, prototype_start_single(&machine, outer_scope, 0))

	expect_output(t, prototype_step_machine(&machine), 0, 0, 1)
	result := prototype_step_machine(&machine)
	testing.expect_value(t, result.kind, prototype_step_kind.runtime_error)
	testing.expect_value(t, result.error_code, 73)
	testing.expect_value(t, prototype_test_machine_state(machine), prototype_state.failed)
	for _ in 0..<3 {
		replayed := prototype_step_machine(&machine)
		testing.expect_value(t, replayed.kind, prototype_step_kind.runtime_error)
		testing.expect_value(t, replayed.error_code, 73)
	}

	allocation_scope_end(t, &scope)
}

@(test)
prototype_limit_negative_zero_one_match_jq_boundaries :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	negative: prototype_machine
	testing.expect(t, prototype_machine_init(&negative))
	negative_inner, ok1 := prototype_add_values(&negative, []i64{1})
	negative_outer, ok2 := prototype_add_values(&negative, []i64{3})
	negative_scope, ok3 := prototype_add_limited_then(
		&negative,
		negative_inner,
		-1,
		negative_outer,
	)
	testing.expect(t, ok1 && ok2 && ok3)
	testing.expect(t, prototype_start_single(&negative, negative_scope, 0))
	negative_result := prototype_step_machine(&negative)
	testing.expect_value(t, negative_result.kind, prototype_step_kind.runtime_error)
	testing.expect_value(t, negative_result.error_code, prototype_negative_limit_error)
	testing.expect_value(t, prototype_test_machine_state(negative), prototype_state.failed)
	testing.expect_value(
		t,
		prototype_step_machine(&negative).error_code,
		prototype_negative_limit_error,
	)

	zero: prototype_machine
	testing.expect(t, prototype_machine_init(&zero))
	zero_inner, ok4 := prototype_add_error(&zero, 91)
	zero_outer, ok5 := prototype_add_values(&zero, []i64{3})
	zero_scope, ok6 := prototype_add_limited_then(&zero, zero_inner, 0, zero_outer)
	testing.expect(t, ok4 && ok5 && ok6)
	testing.expect(t, prototype_start_single(&zero, zero_scope, 0))
	expect_output(t, prototype_step_machine(&zero), 0, 0, 3)
	testing.expect_value(t, prototype_step_machine(&zero).kind, prototype_step_kind.exhausted)

	one: prototype_machine
	testing.expect(t, prototype_machine_init(&one))
	one_inner, ok7 := prototype_add_values_then_error(&one, []i64{1}, 91)
	one_outer, ok8 := prototype_add_values(&one, []i64{3})
	one_scope, ok9 := prototype_add_limited_then(&one, one_inner, 1, one_outer)
	testing.expect(t, ok7 && ok8 && ok9)
	testing.expect(t, prototype_start_single(&one, one_scope, 0))
	expect_output(t, prototype_step_machine(&one), 0, 0, 1)
	expect_output(t, prototype_step_machine(&one), 0, 0, 3)
	testing.expect_value(t, prototype_step_machine(&one).kind, prototype_step_kind.exhausted)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_nested_negative_limit_does_not_resume_any_outer_scope :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	one, ok1 := prototype_add_values(&machine, []i64{1})
	three, ok2 := prototype_add_values(&machine, []i64{3})
	negative_scope, ok3 := prototype_add_limited_then(&machine, one, -1, three)
	four, ok4 := prototype_add_values(&machine, []i64{4})
	outer_scope, ok5 := prototype_add_limited_then(&machine, negative_scope, 2, four)
	testing.expect(t, ok1 && ok2 && ok3 && ok4 && ok5)
	testing.expect(t, prototype_start_single(&machine, outer_scope, 0))

	result := prototype_step_machine(&machine)
	testing.expect_value(t, result.kind, prototype_step_kind.runtime_error)
	testing.expect_value(t, result.error_code, prototype_negative_limit_error)
	testing.expect_value(t, prototype_test_state(machine), nil)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_nested_zero_limit_continuation_counts_in_outer_scope :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	suppressed_error, ok1 := prototype_add_error(&machine, 91)
	zero_continuation, ok2 := prototype_add_values(&machine, []i64{3, 5})
	zero_scope, ok3 := prototype_add_limited_then(
		&machine,
		suppressed_error,
		0,
		zero_continuation,
	)
	outer_continuation, ok4 := prototype_add_values(&machine, []i64{4})
	outer_scope, ok5 := prototype_add_limited_then(
		&machine,
		zero_scope,
		1,
		outer_continuation,
	)
	testing.expect(t, ok1 && ok2 && ok3 && ok4 && ok5)
	testing.expect(t, prototype_start_single(&machine, outer_scope, 0))

	// The zero scope enters its continuation immediately without evaluating
	// the error node. Its first output counts against the enclosing limit,
	// suppressing the second output before the outer continuation resumes.
	expect_output(t, prototype_step_machine(&machine), 0, 0, 3)
	expect_output(t, prototype_step_machine(&machine), 0, 0, 4)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_handles_are_lifetime_aware_and_machine_scoped :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	stale, stale_ok := prototype_add_values(&machine, []i64{11, 12})
	testing.expect(t, stale_ok)

	other: prototype_machine
	testing.expect(t, prototype_machine_init(&other))
	_, other_ok := prototype_add_values(&other, []i64{22})
	testing.expect(t, other_ok)
	testing.expect_value(t, prototype_start_single(&other, stale, 0), false)
	prototype_destroy(&other)

	alias := machine
	testing.expect(t, prototype_start_single(&alias, stale, 0))
	expect_output(t, prototype_step_machine(&alias), 0, 0, 11)
	prototype_destroy(&alias)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
	prototype_destroy(&machine)

	testing.expect(t, prototype_machine_init(&machine))
	fresh, fresh_ok := prototype_add_values(&machine, []i64{99})
	testing.expect(t, fresh_ok)
	testing.expect_value(t, fresh.slot, stale.slot)
	testing.expect(t, fresh.machine_id != stale.machine_id)
	testing.expect_value(t, prototype_start_single(&machine, stale, 0), false)
	testing.expect(t, prototype_start_single(&machine, fresh, 0))
	expect_output(t, prototype_step_machine(&machine), 0, 0, 99)
	prototype_destroy(&machine)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_stale_snapshot_restoration_cannot_revive_destroyed_state :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	stale, stale_ok := prototype_add_values(&machine, []i64{11})
	testing.expect(t, stale_ok)
	snapshot := machine
	snapshot_after_reinit := snapshot
	state := prototype_test_state(machine)
	initial_capacity := cap(state.nodes)
	for cap(state.nodes) == initial_capacity {
		_, ok := prototype_add_empty(&machine)
		testing.expect(t, ok)
	}

	// This is the accepted-finding sequence: save an ordinary Odin copy,
	// destroy the original, then restore the stale bits at the same address.
	prototype_destroy(&machine)
	machine = snapshot
	testing.expect_value(t, prototype_test_state(machine), nil)
	_, stale_add_ok := prototype_add_empty(&machine)
	testing.expect_value(t, stale_add_ok, false)
	testing.expect_value(t, prototype_start_single(&machine, stale, 0), false)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
	prototype_stop(&machine)
	prototype_destroy(&machine)
	prototype_destroy(&snapshot)

	// Reinitialization gets a never-reused identity. The old node handle and a
	// second restored stale machine copy cannot address the fresh state.
	testing.expect(t, prototype_machine_init(&machine))
	fresh, fresh_ok := prototype_add_values(&machine, []i64{22})
	testing.expect(t, fresh_ok)
	testing.expect(t, fresh.machine_id != stale.machine_id)
	testing.expect_value(t, prototype_start_single(&machine, stale, 0), false)
	testing.expect_value(
		t,
		prototype_start_single(&snapshot_after_reinit, fresh, 0),
		false,
	)
	_, stale_copy_add_ok := prototype_add_empty(&snapshot_after_reinit)
	testing.expect_value(t, stale_copy_add_ok, false)
	prototype_destroy(&snapshot_after_reinit)
	testing.expect(t, prototype_start_single(&machine, fresh, 8))
	expect_output(t, prototype_step_machine(&machine), 8, 0, 22)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
	prototype_destroy(&machine)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_saved_handles_survive_dynamic_array_growth :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine))
	left, left_ok := prototype_add_values(&machine, []i64{1, 2})
	right, right_ok := prototype_add_values(&machine, []i64{10, 20})
	testing.expect(t, left_ok && right_ok)
	capacity_before := cap(prototype_test_state(machine).nodes)
	for filler in 0..<256 {
		_, ok := prototype_add_values(&machine, []i64{i64(filler)})
		testing.expect(t, ok)
	}
	testing.expect(t, cap(prototype_test_state(machine).nodes) > capacity_before)
	testing.expect(t, prototype_start_cartesian(&machine, left, right, 0))
	expected := [4][2]i64{{1, 10}, {1, 20}, {2, 10}, {2, 20}}
	for pair in expected {
		expect_output(t, prototype_step_machine(&machine), 0, pair[0], pair[1])
	}
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_numeric_boundaries_remain_generator_components :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	upper: prototype_machine
	testing.expect(t, prototype_machine_init(&upper))
	upper_node, upper_ok := prototype_add_values(&upper, []i64{1})
	testing.expect(t, upper_ok)
	testing.expect(t, prototype_start_single(&upper, upper_node, max(i64)))
	expect_output(t, prototype_step_machine(&upper), max(i64), 0, 1)
	testing.expect_value(t, prototype_step_machine(&upper).kind, prototype_step_kind.exhausted)

	lower: prototype_machine
	testing.expect(t, prototype_machine_init(&lower))
	lower_node, lower_ok := prototype_add_values(&lower, []i64{-1})
	testing.expect(t, lower_ok)
	testing.expect(t, prototype_start_single(&lower, lower_node, min(i64)))
	expect_output(t, prototype_step_machine(&lower), min(i64), 0, -1)
	testing.expect_value(t, prototype_step_machine(&lower).kind, prototype_step_kind.exhausted)

	continuing: prototype_machine
	testing.expect(t, prototype_machine_init(&continuing))
	left, left_ok := prototype_add_values(&continuing, []i64{max(i64), 0})
	right, right_ok := prototype_add_values(&continuing, []i64{1})
	testing.expect(t, left_ok && right_ok)
	testing.expect(t, prototype_start_cartesian(&continuing, left, right, 0))
	expect_output(t, prototype_step_machine(&continuing), 0, max(i64), 1)
	expect_output(t, prototype_step_machine(&continuing), 0, 0, 1)
	testing.expect_value(
		t,
		prototype_step_machine(&continuing).kind,
		prototype_step_kind.exhausted,
	)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_init_and_partial_add_fail_atomically :: proc(t: ^testing.T) {
	machine: prototype_machine
	testing.expect_value(t, prototype_machine_init(&machine, runtime.nil_allocator()), false)
	testing.expect_value(t, machine, prototype_machine{})

	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	fail_state := fail_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		fail_at = 3,
		fail_free_at = 1,
		reject_free_count = 1,
		free_error = .Invalid_Argument,
	}
	allocator := runtime.Allocator {
		procedure = fail_allocator_proc,
		data = &fail_state,
	}
	testing.expect(t, prototype_machine_init(&machine, allocator))
	_, empty_ok := prototype_add_empty(&machine)
	testing.expect(t, empty_ok)
	handle, ok := prototype_add_values(&machine, []i64{7})
	testing.expect_value(t, ok, false)
	testing.expect_value(t, handle, prototype_node_handle{})
	state := prototype_test_state(machine)
	testing.expect_value(t, state.state, prototype_state.cleanup_failed)
	testing.expect_value(t, state.cleanup_operation, prototype_cleanup_operation.add_rollback)
	testing.expect(t, state.rollback_offsets != nil)
	testing.expect_value(t, len(state.nodes), 1)
	testing.expect_value(t, fail_state.failed, true)
	testing.expect_value(t, fail_state.free_failed, true)
	testing.expect_value(t, fail_state.resize_calls, 1)
	testing.expect_value(t, len(tracker.allocation_map), 2)

	handle, ok = prototype_add_values(&machine, []i64{7})
	testing.expect(t, ok)
	testing.expect_value(
		t,
		handle,
		prototype_node_handle{machine_id = machine.id, slot = 1},
	)
	testing.expect_value(t, len(prototype_test_state(machine).nodes), 2)
	testing.expect(t, prototype_start_single(&machine, handle, 9))
	expect_output(t, prototype_step_machine(&machine), 9, 0, 7)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
	testing.expect_value(t, prototype_test_machine_state(machine), prototype_state.exhausted)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)

	prototype_destroy(&machine)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(private)
run_deep_allocation_scenario :: proc(
	t: ^testing.T,
	fail_at: int,
) -> (calls: int, failed: bool) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	fail_state := fail_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		fail_at = fail_at,
	}
	allocator := runtime.Allocator {
		procedure = fail_allocator_proc,
		data = &fail_state,
	}

	machine: prototype_machine
	if prototype_machine_init(&machine, allocator) {
		inner, inner_ok := prototype_add_values(&machine, []i64{1, 2})
		outer, outer_ok := prototype_add_values(&machine, []i64{3})
		if inner_ok && outer_ok {
			scope_node, scope_ok := prototype_add_limited_then(&machine, inner, 1, outer)
			if scope_ok && prototype_start_single(&machine, scope_node, 0) {
				for prototype_step_machine(&machine).kind == .output {
				}
			}
		}
		prototype_destroy(&machine)
	}

	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	calls = fail_state.call
	failed = fail_state.failed
	mem.tracking_allocator_destroy(&tracker)
	return
}

@(test)
prototype_deep_scope_failure_injection_cleans_each_observed_call :: proc(t: ^testing.T) {
	allocation_calls, unexpected_failure := run_deep_allocation_scenario(t, max(int))
	testing.expect_value(t, unexpected_failure, false)
	testing.expect(t, allocation_calls >= 4)
	// This iterates only the allocation calls reached by the deep scoped
	// scenario above; exact-capacity reservations leave other syntactic
	// allocation-error branches unexecuted.
	for fail_at in 1..=allocation_calls {
		_, failed := run_deep_allocation_scenario(t, fail_at)
		testing.expect_value(t, failed, true)
	}
}

@(test)
prototype_deep_acyclic_chain_fills_frames_without_resize :: proc(t: ^testing.T) {
	practical_node_count :: 4096

	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	allocator_state := fail_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		fail_at = max(int),
	}
	allocator := runtime.Allocator {
		procedure = fail_allocator_proc,
		data = &allocator_state,
	}

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine, allocator))
	leaf, leaf_ok := prototype_add_values(&machine, []i64{7})
	testing.expect(t, leaf_ok)
	root := leaf
	for _ in 1..<practical_node_count {
		next, ok := prototype_add_limited_then(&machine, root, 1, leaf)
		testing.expect(t, ok)
		root = next
	}
	testing.expect_value(t, len(prototype_test_state(machine).nodes), practical_node_count)
	testing.expect(t, prototype_start_single(&machine, root, 9))
	state := prototype_test_state(machine)
	testing.expect_value(t, cap(state.frames), len(state.nodes))

	frames_data := raw_data(state.frames)
	allocation_calls_before_step := allocator_state.call
	resize_calls_before_step := allocator_state.resize_calls

	// Reaching the leaf requires one live frame for every node in this
	// back-reference-only chain, exactly filling the reserved capacity. The
	// returned output truncates the frames, so unchanged storage and allocator
	// counters establish that none of those pushes resized it.
	expect_output(t, prototype_step_machine(&machine), 9, 0, 7)
	testing.expect_value(t, raw_data(state.frames), frames_data)
	testing.expect_value(t, cap(state.frames), practical_node_count)
	testing.expect_value(t, allocator_state.call, allocation_calls_before_step)
	testing.expect_value(t, allocator_state.resize_calls, resize_calls_before_step)

	expect_output(t, prototype_step_machine(&machine), 9, 0, 7)
	testing.expect_value(t, raw_data(state.frames), frames_data)
	testing.expect_value(t, allocator_state.call, allocation_calls_before_step)
	testing.expect_value(t, allocator_state.resize_calls, resize_calls_before_step)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
	prototype_destroy(&machine)

	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
prototype_stop_building_machine_releases_owned_storage_once :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	allocator_state := fail_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		fail_at = max(int),
	}
	allocator := runtime.Allocator {
		procedure = fail_allocator_proc,
		data = &allocator_state,
	}

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine, allocator))
	stale, stale_ok := prototype_add_values(&machine, []i64{1, 2})
	testing.expect(t, stale_ok)
	state := prototype_test_state(machine)
	testing.expect_value(t, state.state, prototype_state.building)
	testing.expect_value(t, len(state.nodes), 1)
	testing.expect(t, state.nodes != nil)
	testing.expect(t, state.nodes[0].offsets != nil)
	testing.expect_value(t, len(tracker.allocation_map), 2)

	prototype_stop(&machine)
	testing.expect_value(t, machine.terminal, prototype_state.stopped)
	testing.expect_value(t, prototype_test_state(machine), nil)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)

	// Cleanup ends the allocator-data borrow. Replay, rejected stale-handle
	// operations, and repeated stop/destroy must not free either allocation
	// again or consult any allocator mode.
	allocator_state.retired = true
	for _ in 0..<3 {
		testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
		prototype_stop(&machine)
	}
	_, stopped_add_ok := prototype_add_values(&machine, []i64{3})
	testing.expect_value(t, stopped_add_ok, false)
	testing.expect_value(t, prototype_start_single(&machine, stale, 0), false)
	testing.expect_value(t, prototype_start_cartesian(&machine, stale, stale, 0), false)
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	testing.expect_value(t, allocator_state.called_while_retired, false)

	prototype_destroy(&machine)
	for _ in 0..<3 {
		testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
		prototype_stop(&machine)
		prototype_destroy(&machine)
	}
	_, destroyed_add_ok := prototype_add_values(&machine, []i64{4})
	testing.expect_value(t, destroyed_add_ok, false)
	testing.expect_value(t, prototype_start_single(&machine, stale, 0), false)
	testing.expect_value(t, prototype_start_cartesian(&machine, stale, stale, 0), false)
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	testing.expect_value(t, allocator_state.called_while_retired, false)
	testing.expect_value(t, machine, prototype_machine{})
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)

	mem.tracking_allocator_destroy(&tracker)
}

@(test)
prototype_stop_releases_custom_allocator_storage_before_destroy :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	allocator_state := fail_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		fail_at = max(int),
	}
	allocator := runtime.Allocator {
		procedure = fail_allocator_proc,
		data = &allocator_state,
	}

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine, allocator))
	inner, inner_ok := prototype_add_values(&machine, []i64{1, 2})
	outer, outer_ok := prototype_add_values(&machine, []i64{3})
	scope_node, scope_ok := prototype_add_limited_then(&machine, inner, 2, outer)
	testing.expect(t, inner_ok && outer_ok && scope_ok)
	testing.expect(t, prototype_start_single(&machine, scope_node, 0))
	expect_output(t, prototype_step_machine(&machine), 0, 0, 1)

	prototype_stop(&machine)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)

	// Keep allocator.data alive as an active detector after marking the
	// post-stop lifetime boundary. Every terminal or rejected operation below
	// must avoid all allocator modes, including queries and frees.
	allocator_state.retired = true
	for _ in 0..<3 {
		testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
		prototype_stop(&machine)
	}
	testing.expect_value(t, prototype_machine_init(&machine, allocator), false)
	_, stopped_values_ok := prototype_add_values(&machine, []i64{4})
	_, stopped_values_error_ok := prototype_add_values_then_error(&machine, []i64{4}, 92)
	_, stopped_empty_ok := prototype_add_empty(&machine)
	_, stopped_error_ok := prototype_add_error(&machine, 93)
	_, stopped_scope_ok := prototype_add_limited_then(&machine, inner, 1, outer)
	testing.expect_value(t, stopped_values_ok, false)
	testing.expect_value(t, stopped_values_error_ok, false)
	testing.expect_value(t, stopped_empty_ok, false)
	testing.expect_value(t, stopped_error_ok, false)
	testing.expect_value(t, stopped_scope_ok, false)
	testing.expect_value(t, prototype_start_single(&machine, scope_node, 0), false)
	testing.expect_value(t, prototype_start_cartesian(&machine, inner, outer, 0), false)
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	testing.expect_value(t, allocator_state.called_while_retired, false)

	prototype_destroy(&machine)
	for _ in 0..<3 {
		testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
		prototype_stop(&machine)
		prototype_destroy(&machine)
	}
	_, destroyed_values_ok := prototype_add_values(&machine, []i64{4})
	_, destroyed_values_error_ok := prototype_add_values_then_error(&machine, []i64{4}, 94)
	_, destroyed_empty_ok := prototype_add_empty(&machine)
	_, destroyed_error_ok := prototype_add_error(&machine, 95)
	_, destroyed_scope_ok := prototype_add_limited_then(&machine, inner, 1, outer)
	testing.expect_value(t, destroyed_values_ok, false)
	testing.expect_value(t, destroyed_values_error_ok, false)
	testing.expect_value(t, destroyed_empty_ok, false)
	testing.expect_value(t, destroyed_error_ok, false)
	testing.expect_value(t, destroyed_scope_ok, false)
	testing.expect_value(t, prototype_start_single(&machine, scope_node, 0), false)
	testing.expect_value(t, prototype_start_cartesian(&machine, inner, outer, 0), false)
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	testing.expect_value(t, allocator_state.called_while_retired, false)
	testing.expect_value(t, machine, prototype_machine{})

	mem.tracking_allocator_destroy(&tracker)
}

@(private)
run_retired_terminal_scenario :: proc(
	t: ^testing.T,
	fail_terminal: bool,
) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	allocator_state := fail_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		fail_at = max(int),
	}
	allocator := runtime.Allocator {
		procedure = fail_allocator_proc,
		data = &allocator_state,
	}

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine, allocator))
	node: prototype_node_handle
	node_ok: bool
	if fail_terminal {
		node, node_ok = prototype_add_values_then_error(&machine, []i64{1}, 77)
	} else {
		node, node_ok = prototype_add_values(&machine, []i64{1})
	}
	testing.expect(t, node_ok)
	testing.expect(t, prototype_start_single(&machine, node, 5))
	expect_output(t, prototype_step_machine(&machine), 5, 0, 1)

	terminal := prototype_step_machine(&machine)
	expected_kind := prototype_step_kind.exhausted
	if fail_terminal {
		expected_kind = .runtime_error
		testing.expect_value(t, terminal.error_code, 77)
	}
	testing.expect_value(t, terminal.kind, expected_kind)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)

	// Terminal cleanup ends the allocator-data borrow. Keep the detector
	// resident but retired while replay and every rejected mutation prove
	// that neither terminal state consults any allocator mode.
	allocator_state.retired = true
	for _ in 0..<3 {
		replayed := prototype_step_machine(&machine)
		testing.expect_value(t, replayed.kind, expected_kind)
		if fail_terminal {
			testing.expect_value(t, replayed.error_code, 77)
		}
		prototype_stop(&machine)
	}
	testing.expect_value(t, prototype_machine_init(&machine, allocator), false)
	_, terminal_values_ok := prototype_add_values(&machine, []i64{2})
	_, terminal_values_error_ok := prototype_add_values_then_error(&machine, []i64{2}, 78)
	_, terminal_empty_ok := prototype_add_empty(&machine)
	_, terminal_error_ok := prototype_add_error(&machine, 79)
	_, terminal_scope_ok := prototype_add_limited_then(&machine, node, 1, node)
	testing.expect_value(t, terminal_values_ok, false)
	testing.expect_value(t, terminal_values_error_ok, false)
	testing.expect_value(t, terminal_empty_ok, false)
	testing.expect_value(t, terminal_error_ok, false)
	testing.expect_value(t, terminal_scope_ok, false)
	testing.expect_value(t, prototype_start_single(&machine, node, 0), false)
	testing.expect_value(t, prototype_start_cartesian(&machine, node, node, 0), false)
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	testing.expect_value(t, allocator_state.called_while_retired, false)

	prototype_destroy(&machine)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
	prototype_stop(&machine)
	prototype_destroy(&machine)
	_, destroyed_add_ok := prototype_add_empty(&machine)
	testing.expect_value(t, destroyed_add_ok, false)
	testing.expect_value(t, prototype_start_single(&machine, node, 0), false)
	testing.expect_value(t, prototype_start_cartesian(&machine, node, node, 0), false)
	testing.expect_value(t, prototype_stop_inner(&machine), false)
	testing.expect_value(t, allocator_state.called_while_retired, false)

	mem.tracking_allocator_destroy(&tracker)
}

@(test)
prototype_natural_terminal_cleanup_ends_allocator_data_borrow :: proc(t: ^testing.T) {
	run_retired_terminal_scenario(t, false)
	run_retired_terminal_scenario(t, true)
}

@(test)
prototype_start_frame_allocation_failure_is_retryable_and_clean :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	fail_state := fail_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		fail_at = 3,
	}
	allocator := runtime.Allocator {
		procedure = fail_allocator_proc,
		data = &fail_state,
	}

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine, allocator))
	node, ok := prototype_add_values(&machine, []i64{1})
	testing.expect(t, ok)
	testing.expect_value(t, prototype_start_single(&machine, node, 0), false)
	state := prototype_test_state(machine)
	testing.expect_value(t, state.state, prototype_state.building)
	testing.expect_value(t, state.frames == nil, true)
	testing.expect_value(t, fail_state.failed, true)

	testing.expect(t, prototype_start_single(&machine, node, 9))
	expect_output(t, prototype_step_machine(&machine), 9, 0, 1)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
	testing.expect_value(t, prototype_test_machine_state(machine), prototype_state.exhausted)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)

	prototype_destroy(&machine)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
prototype_terminal_replay_and_whole_machine_stop_are_stable :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	building: prototype_machine
	testing.expect(t, prototype_machine_init(&building))
	node, ok := prototype_add_values(&building, []i64{1, 2})
	testing.expect(t, ok)
	testing.expect_value(t, prototype_step_machine(&building).kind, prototype_step_kind.exhausted)
	testing.expect_value(t, prototype_test_machine_state(building), prototype_state.exhausted)
	testing.expect_value(t, prototype_start_single(&building, node, 0), false)
	for _ in 0..<3 {
		testing.expect_value(t, prototype_step_machine(&building).kind, prototype_step_kind.exhausted)
	}

	stopped: prototype_machine
	testing.expect(t, prototype_machine_init(&stopped))
	left, left_ok := prototype_add_values(&stopped, []i64{1, 2})
	right, right_ok := prototype_add_values(&stopped, []i64{10, 20})
	testing.expect(t, left_ok && right_ok)
	testing.expect(t, prototype_start_cartesian(&stopped, left, right, 0))
	expect_output(t, prototype_step_machine(&stopped), 0, 1, 10)
	prototype_stop(&stopped)
	for _ in 0..<3 {
		testing.expect_value(t, prototype_step_machine(&stopped).kind, prototype_step_kind.exhausted)
	}
	prototype_destroy(&stopped)
	prototype_destroy(&building)

	allocation_scope_end(t, &scope)
}

@(test)
prototype_deterministic_randomized_cartesian_matches_model :: proc(t: ^testing.T) {
	scope: allocation_scope
	allocation_scope_begin(&scope)

	seed := u64(0x6a09e667f3bcc909)
	for case_index in 0..<200 {
		seed = seed ~ (seed << 13)
		seed = seed ~ (seed >> 7)
		seed = seed ~ (seed << 17)
		left_count := int(seed % 6)
		seed = seed ~ (seed << 13)
		seed = seed ~ (seed >> 7)
		seed = seed ~ (seed << 17)
		right_count := int(seed % 6)

		left_values: [5]i64
		right_values: [5]i64
		for index in 0..<left_count {
			seed = seed ~ (seed << 13)
			seed = seed ~ (seed >> 7)
			seed = seed ~ (seed << 17)
			left_values[index] = i64(seed % 21) - 10
		}
		for index in 0..<right_count {
			seed = seed ~ (seed << 13)
			seed = seed ~ (seed >> 7)
			seed = seed ~ (seed << 17)
			right_values[index] = i64(seed % 21) - 10
		}

		machine: prototype_machine
		testing.expect(t, prototype_machine_init(&machine))
		left, left_ok := prototype_add_values(&machine, left_values[:left_count])
		right, right_ok := prototype_add_values(&machine, right_values[:right_count])
		testing.expect(t, left_ok && right_ok)
		testing.expect(t, prototype_start_cartesian(&machine, left, right, i64(case_index)))
		for left_index in 0..<left_count {
			for right_index in 0..<right_count {
				expect_output(
					t,
					prototype_step_machine(&machine),
					i64(case_index),
					left_values[left_index],
					right_values[right_index],
				)
			}
		}
		testing.expect_value(
			t,
			prototype_step_machine(&machine).kind,
			prototype_step_kind.exhausted,
		)
	}

	allocation_scope_end(t, &scope)
}

@(private)
run_terminal_free_retry_scenario :: proc(
	t: ^testing.T,
	fail_terminal: bool,
	fail_free_at: int,
	reject_count := 1,
	free_error := runtime.Allocator_Error.Invalid_Argument,
) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	allocator_state := fail_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		fail_at = max(int),
		fail_free_at = fail_free_at,
		reject_free_count = reject_count,
		free_error = free_error,
	}
	allocator := runtime.Allocator {
		procedure = fail_allocator_proc,
		data = &allocator_state,
	}

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine, allocator))
	node: prototype_node_handle
	ok: bool
	if fail_terminal {
		node, ok = prototype_add_values_then_error(&machine, []i64{1}, 87)
	} else {
		node, ok = prototype_add_values(&machine, []i64{1})
	}
	testing.expect(t, ok)
	testing.expect(t, prototype_start_single(&machine, node, 3))
	expect_output(t, prototype_step_machine(&machine), 3, 0, 1)
	stale := machine

	expected_kind := prototype_step_kind.exhausted
	if fail_terminal {
		expected_kind = .runtime_error
	}
	if free_error == .Mode_Not_Implemented {
		terminal := prototype_step_machine(&machine)
		testing.expect_value(t, terminal.kind, expected_kind)
		testing.expect_value(t, allocator_state.free_failed, true)
	} else {
		for retry in 0..<reject_count {
			target := &machine
			if retry % 2 == 1 {
				target = &stale
			}
			cleanup := prototype_step_machine(target)
			testing.expect_value(t, cleanup.kind, prototype_step_kind.cleanup_error)
			testing.expect_value(t, cleanup.cleanup_error, free_error)
			state := prototype_test_state(target^)
			testing.expect(t, state != nil)
			testing.expect_value(t, state.state, prototype_state.cleanup_failed)
			testing.expect_value(
				t,
				state.cleanup_operation,
				prototype_cleanup_operation.terminal_step,
			)
			testing.expect(t, len(tracker.allocation_map) > 0)
		}
		terminal := prototype_step_machine(&machine)
		testing.expect_value(t, terminal.kind, expected_kind)
		if fail_terminal {
			testing.expect_value(t, terminal.error_code, 87)
		}
	}

	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	replayed := prototype_step_machine(&machine)
	testing.expect_value(t, replayed.kind, expected_kind)
	if fail_terminal {
		testing.expect_value(t, replayed.error_code, 87)
	}
	testing.expect_value(t, prototype_step_machine(&stale).kind, prototype_step_kind.exhausted)
	_ = prototype_destroy(&stale)
	_ = prototype_destroy(&machine)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
prototype_terminal_cleanup_rejects_each_free_and_retries_transactionally :: proc(t: ^testing.T) {
	// Single-mode teardown owns frames, one offsets array, and the node array,
	// in that deterministic release order.
	for fail_free_at in 1..=3 {
		run_terminal_free_retry_scenario(t, false, fail_free_at)
		run_terminal_free_retry_scenario(t, true, fail_free_at)
	}
	// Repeated rejection of the same descriptor must replay cleanup failure,
	// not exhaustion/error, until that descriptor is actually retired.
	run_terminal_free_retry_scenario(t, false, 1, 2)
	// Bulk-lifetime allocators retire a descriptor on Mode_Not_Implemented.
	run_terminal_free_retry_scenario(t, false, 1, 1, .Mode_Not_Implemented)
}

@(private)
run_stop_free_retry_scenario :: proc(t: ^testing.T, active: bool, fail_free_at: int) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	allocator_state := fail_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		fail_at = max(int),
		fail_free_at = fail_free_at,
		reject_free_count = 1,
		free_error = .Invalid_Argument,
	}
	allocator := runtime.Allocator {
		procedure = fail_allocator_proc,
		data = &allocator_state,
	}
	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine, allocator))
	node, ok := prototype_add_values(&machine, []i64{1})
	testing.expect(t, ok)
	if active {
		testing.expect(t, prototype_start_single(&machine, node, 0))
	}
	stale := machine
	testing.expect_value(t, prototype_stop(&machine), runtime.Allocator_Error.Invalid_Argument)
	state := prototype_test_state(stale)
	testing.expect(t, state != nil)
	testing.expect_value(t, state.state, prototype_state.cleanup_failed)
	testing.expect_value(t, state.cleanup_operation, prototype_cleanup_operation.stop)
	step := prototype_step_machine(&stale)
	testing.expect_value(t, step.kind, prototype_step_kind.cleanup_error)
	testing.expect_value(t, step.cleanup_error, runtime.Allocator_Error.Invalid_Argument)
	testing.expect_value(t, prototype_stop(&stale), runtime.Allocator_Error(nil))
	testing.expect_value(t, stale.terminal, prototype_state.stopped)
	testing.expect_value(t, prototype_step_machine(&stale).kind, prototype_step_kind.exhausted)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	_ = prototype_destroy(&machine)
	_ = prototype_destroy(&stale)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
prototype_building_and_active_stop_cleanup_is_retryable :: proc(t: ^testing.T) {
	for fail_free_at in 1..=2 {
		run_stop_free_retry_scenario(t, false, fail_free_at)
	}
	for fail_free_at in 1..=3 {
		run_stop_free_retry_scenario(t, true, fail_free_at)
	}
}

@(test)
prototype_destroy_cleanup_failure_preserves_owner_for_retry :: proc(t: ^testing.T) {
	for fail_free_at in 1..=2 {
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
		allocator_state := fail_allocator_state {
			backing = mem.tracking_allocator(&tracker),
			fail_at = max(int),
			fail_free_at = fail_free_at,
			reject_free_count = 1,
			free_error = .Invalid_Argument,
		}
		allocator := runtime.Allocator {
			procedure = fail_allocator_proc,
			data = &allocator_state,
		}
		machine: prototype_machine
		testing.expect(t, prototype_machine_init(&machine, allocator))
		_, ok := prototype_add_values(&machine, []i64{1})
		testing.expect(t, ok)
		stale := machine
		testing.expect_value(
			t,
			prototype_destroy(&machine),
			runtime.Allocator_Error.Invalid_Argument,
		)
		testing.expect(t, prototype_test_state(stale) != nil)
		testing.expect_value(t, prototype_destroy(&stale), runtime.Allocator_Error(nil))
		testing.expect_value(t, stale, prototype_machine{})
		testing.expect_value(t, len(tracker.allocation_map), 0)
		testing.expect_value(t, len(tracker.bad_free_array), 0)
		_ = prototype_destroy(&machine)
		mem.tracking_allocator_destroy(&tracker)
	}
}

@(private)
reentrant_allocator_state :: struct {
	backing: runtime.Allocator,
	machine: ^prototype_machine,
	calls: int,
	all_observed_busy: bool,
}

@(private)
reentrant_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^reentrant_allocator_state)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize ||
	   mode == .Resize_Non_Zeroed || mode == .Free {
		state.calls += 1
		result := prototype_step_machine(state.machine)
		state.all_observed_busy &&= result.kind == .operation_in_progress
		destroy_error := prototype_destroy(state.machine)
		state.all_observed_busy &&= destroy_error == .Invalid_Argument &&
		                           state.machine.id != 0
	}
	return state.backing.procedure(
		state.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		loc,
	)
}

@(test)
prototype_allocator_callbacks_never_hold_registry_mutex :: proc(t: ^testing.T) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array
	machine: prototype_machine
	allocator_state := reentrant_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		machine = &machine,
		all_observed_busy = true,
	}
	allocator := runtime.Allocator {
		procedure = reentrant_allocator_proc,
		data = &allocator_state,
	}
	testing.expect(t, prototype_machine_init(&machine, allocator))
	node, ok := prototype_add_values(&machine, []i64{1})
	testing.expect(t, ok)
	testing.expect(t, prototype_start_single(&machine, node, 0))
	expect_output(t, prototype_step_machine(&machine), 0, 0, 1)
	testing.expect_value(t, prototype_step_machine(&machine).kind, prototype_step_kind.exhausted)
	testing.expect(t, allocator_state.calls >= 5)
	testing.expect_value(t, allocator_state.all_observed_busy, true)
	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	_ = prototype_destroy(&machine)
	mem.tracking_allocator_destroy(&tracker)
}

@(private)
barrier_allocator_state :: struct {
	backing:          runtime.Allocator,
	barrier:          ^sync.Barrier,
	entered_callback: ^sync.Auto_Reset_Event,
	block_next_free: bool,
	reject_next_free: bool,
}

@(private)
barrier_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^barrier_allocator_state)data
	if mode == .Free && state.block_next_free {
		state.block_next_free = false
		sync.auto_reset_event_signal(state.entered_callback)
		_ = sync.barrier_wait(state.barrier)
	}
	if mode == .Free && state.reject_next_free {
		state.reject_next_free = false
		return nil, .Invalid_Argument
	}
	return state.backing.procedure(
		state.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		loc,
	)
}

@(private)
busy_winner_state :: struct {
	machine: ^prototype_machine,
	barrier: ^sync.Barrier,
	result:  prototype_step,
}

@(private)
busy_winner_proc :: proc(data: rawptr) {
	state := cast(^busy_winner_state)data
	state.result = prototype_step_machine(state.machine)
	_ = sync.barrier_wait(state.barrier)
}

@(private)
busy_observer_state :: struct {
	barrier: ^sync.Barrier,
	kind:    prototype_claim_kind,
}

@(private)
busy_claim_observer :: proc(data: rawptr, kind: prototype_claim_kind) {
	state := cast(^busy_observer_state)data
	state.kind = kind
	// First release the winner from its allocator callback. Then wait until
	// that terminal operation has finished (and, on success, unlinked) before
	// allowing the losing step to return from its captured classification.
	_ = sync.barrier_wait(state.barrier)
	_ = sync.barrier_wait(state.barrier)
}

@(private)
run_busy_terminal_classification_scenario :: proc(
	t: ^testing.T,
	terminal_error: bool,
	reject_cleanup: bool,
) {
	tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracker, context.allocator)
	tracker.bad_free_callback = mem.tracking_allocator_bad_free_callback_add_to_array

	barrier: sync.Barrier
	sync.barrier_init(&barrier, 2)
	entered_callback: sync.Auto_Reset_Event
	allocator_state := barrier_allocator_state {
		backing = mem.tracking_allocator(&tracker),
		barrier = &barrier,
		entered_callback = &entered_callback,
		block_next_free = true,
		reject_next_free = reject_cleanup,
	}
	allocator := runtime.Allocator {
		procedure = barrier_allocator_proc,
		data = &allocator_state,
	}

	machine: prototype_machine
	testing.expect(t, prototype_machine_init(&machine, allocator))
	node: prototype_node_handle
	ok: bool
	if terminal_error {
		node, ok = prototype_add_values_then_error(&machine, []i64{1}, 97)
	} else {
		node, ok = prototype_add_values(&machine, []i64{1})
	}
	testing.expect(t, ok)
	testing.expect(t, prototype_start_single(&machine, node, 0))
	expect_output(t, prototype_step_machine(&machine), 0, 0, 1)
	copy := machine

	winner_state := busy_winner_state {
		machine = &machine,
		barrier = &barrier,
	}
	winner := thread.create_and_start_with_data(
		rawptr(&winner_state),
		busy_winner_proc,
	)
	testing.expect(t, winner != nil)
	if winner == nil {
		_ = prototype_destroy(&machine)
		mem.tracking_allocator_destroy(&tracker)
		return
	}
	sync.auto_reset_event_wait(&entered_callback)

	observer_state := busy_observer_state{barrier = &barrier}
	loser := prototype_step_machine_impl(
		&copy,
		rawptr(&observer_state),
		busy_claim_observer,
	)
	thread.join(winner)
	thread.destroy(winner)

	testing.expect_value(t, observer_state.kind, prototype_claim_kind.busy)
	testing.expect_value(t, loser.kind, prototype_step_kind.operation_in_progress)
	expected_terminal := prototype_step_kind.exhausted
	if terminal_error {
		expected_terminal = .runtime_error
	}
	if reject_cleanup {
		testing.expect_value(t, winner_state.result.kind, prototype_step_kind.cleanup_error)
		testing.expect_value(
			t,
			winner_state.result.cleanup_error,
			runtime.Allocator_Error.Invalid_Argument,
		)
		retry := prototype_step_machine(&copy)
		testing.expect_value(t, retry.kind, expected_terminal)
		if terminal_error {
			testing.expect_value(t, retry.error_code, 97)
		}
	} else {
		testing.expect_value(t, winner_state.result.kind, expected_terminal)
		if terminal_error {
			testing.expect_value(t, winner_state.result.error_code, 97)
		}
		// The losing copy is stale after the winner's successful unlink.
		testing.expect_value(t, prototype_step_machine(&copy).kind, prototype_step_kind.exhausted)
	}

	testing.expect_value(t, len(tracker.allocation_map), 0)
	testing.expect_value(t, len(tracker.bad_free_array), 0)
	_ = prototype_destroy(&machine)
	_ = prototype_destroy(&copy)
	mem.tracking_allocator_destroy(&tracker)
}

@(test)
prototype_busy_terminal_claim_cannot_be_reclassified_after_winner_finishes :: proc(
	t: ^testing.T,
) {
	// Every iteration is barrier-controlled: the loser captures busy, releases
	// the winner, waits for the winner to finish, and only then returns. Repeating
	// all reachable terminal variants adds stress without depending on timing.
	for _ in 0..<32 {
		run_busy_terminal_classification_scenario(t, false, false)
		run_busy_terminal_classification_scenario(t, true, false)
		run_busy_terminal_classification_scenario(t, true, true)
	}
}
