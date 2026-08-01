package eval

import "base:runtime"
import "core:sync"

@(private)
prototype_step_kind :: enum {
	output,
	exhausted,
	runtime_error,
	cleanup_error,
	operation_in_progress,
}

@(private)
prototype_step :: struct {
	kind:            prototype_step_kind,
	input:           i64,
	left_component:  i64,
	right_component: i64,
	error_code:      int,
	cleanup_error:   runtime.Allocator_Error,
}

@(private)
prototype_node_handle :: struct {
	machine_id: u64,
	slot:       int,
}

@(private)
prototype_node_kind :: enum {
	values,
	empty,
	limited_then,
}

@(private)
prototype_node :: struct {
	kind:               prototype_node_kind,
	offsets:            [dynamic]i64,
	has_terminal_error: bool,
	error_code:         int,

	inner_slot: int,
	limit:      int,
	outer_slot: int,
}

@(private)
prototype_cursor :: struct {
	node_slot:      int,
	input:          i64,
	left_component: i64,
	next:           int,
}

@(private)
prototype_frame_phase :: enum {
	enter,
	values,
	limited_inner,
	limited_continuation_pending,
	limited_outer,
}

@(private)
prototype_frame :: struct {
	node_slot:     int,
	input:         i64,
	phase:         prototype_frame_phase,
	next:          int,
	inner_outputs: int,
}

@(private)
prototype_mode :: enum {
	unconfigured,
	single,
	cartesian,
}

@(private)
prototype_state :: enum {
	uninitialized,
	initializing,
	building,
	active,
	cleanup_failed,
	exhausted,
	stopped,
	failed,
}

@(private)
prototype_cleanup_operation :: enum {
	none,
	add_rollback,
	start_rollback,
	terminal_step,
	stop,
	destroy,
}

@(private)
prototype_machine_state :: struct {
	id:   u64,
	next: ^prototype_machine_state,
	busy: bool,

	// Borrowed in full: both the procedure and allocator.data must remain
	// valid until every machine allocation has been released by a successful
	// terminal step, prototype_stop, or prototype_destroy. A genuine cleanup
	// error extends the borrow through retry.
	allocator: runtime.Allocator,
	nodes:     [dynamic]prototype_node,
	frames:    [dynamic]prototype_frame,

	mode:  prototype_mode,
	state: prototype_state,

	left:         prototype_cursor,
	right:        prototype_cursor,
	right_slot:   int,
	right_active: bool,

	error_code: int,

	cleanup_operation: prototype_cleanup_operation,
	cleanup_resume:    prototype_state,
	cleanup_terminal:  prototype_state,
	cleanup_error:     runtime.Allocator_Error,
	rollback_offsets:  [dynamic]i64,
	rollback_frames:   [dynamic]prototype_frame,
}

// A machine is a copyable, non-owning capability. All mutable and
// allocator-bearing state is package-owned and found by this process-unique
// identifier. Copies share one logical machine; destroying through any copy
// retires it for every copy. A stale identifier is inert and is never
// dereferenced as an address.
@(private)
prototype_machine :: struct {
	id:         u64,
	terminal:   prototype_state,
	error_code: int,
}

@(private)
prototype_negative_limit_error :: -2

@(private)
prototype_frame_allocation_error :: -3

@(private)
prototype_lifetime_counter: u64

@(private)
prototype_registry_mutex: sync.Mutex

@(private)
prototype_registry_head: ^prototype_machine_state

@(private)
prototype_claim_kind :: enum {
	absent,
	busy,
	claimed,
}

@(private)
prototype_claim :: struct {
	kind:  prototype_claim_kind,
	state: ^prototype_machine_state,
}

@(private)
prototype_next_lifetime_locked :: proc() -> u64 {
	if prototype_lifetime_counter == max(u64) {
		return 0
	}
	prototype_lifetime_counter += 1
	return prototype_lifetime_counter
}

@(private)
prototype_find_state_locked :: proc(machine: prototype_machine) -> ^prototype_machine_state {
	if machine.id == 0 {
		return nil
	}
	state := prototype_registry_head
	for state != nil {
		if state.id == machine.id {
			return state
		}
		state = state.next
	}
	return nil
}

@(private)
prototype_claim_state :: proc(machine: prototype_machine) -> prototype_claim {
	sync.mutex_lock(&prototype_registry_mutex)
	defer sync.mutex_unlock(&prototype_registry_mutex)
	state := prototype_find_state_locked(machine)
	if state == nil {
		return prototype_claim{kind = .absent}
	}
	if state.busy {
		return prototype_claim{kind = .busy}
	}
	state.busy = true
	return prototype_claim{kind = .claimed, state = state}
}

@(private)
prototype_release_claim :: proc(state: ^prototype_machine_state) {
	if state == nil {
		return
	}
	sync.mutex_lock(&prototype_registry_mutex)
	state.busy = false
	sync.mutex_unlock(&prototype_registry_mutex)
}

@(private)
prototype_unlink_state_locked :: proc(state: ^prototype_machine_state) -> bool {
	previous: ^prototype_machine_state
	current := prototype_registry_head
	for current != nil && current != state {
		previous = current
		current = current.next
	}
	if current == nil {
		return false
	}
	if previous == nil {
		prototype_registry_head = current.next
	} else {
		previous.next = current.next
	}
	return true
}

// Initialize an inert handle. The returned handle is freely copyable
// and all copies share one package-owned state. The state control block uses
// runtime.heap_allocator; node/frame storage uses allocator. The complete
// caller allocator, including allocator.data, is borrowed until terminal
// stepping, prototype_stop, or prototype_destroy successfully releases that
// storage; genuine cleanup errors preserve the borrow and owner for retry.
@(private)
prototype_machine_init :: proc(
	machine: ^prototype_machine,
	allocator := context.allocator,
) -> bool {
	if machine == nil {
		return false
	}

	sync.mutex_lock(&prototype_registry_mutex)
	if machine.id != 0 || machine.terminal != .uninitialized ||
	   prototype_find_state_locked(machine^) != nil {
		sync.mutex_unlock(&prototype_registry_mutex)
		return false
	}
	id := prototype_next_lifetime_locked()
	if id == 0 {
		sync.mutex_unlock(&prototype_registry_mutex)
		return false
	}

	state, state_err := new(prototype_machine_state, runtime.heap_allocator())
	if state_err != nil {
		sync.mutex_unlock(&prototype_registry_mutex)
		return false
	}
	state^ = prototype_machine_state {
		id = id,
		next = prototype_registry_head,
		busy = true,
		allocator = allocator,
		state = .initializing,
	}
	prototype_registry_head = state
	machine^ = prototype_machine{id = id}
	sync.mutex_unlock(&prototype_registry_mutex)

	nodes, err := make([dynamic]prototype_node, 0, 1, allocator)
	if err != nil {
		sync.mutex_lock(&prototype_registry_mutex)
		prototype_unlink_state_locked(state)
		free_error := free(state, runtime.heap_allocator())
		if free_error != nil && free_error != .Mode_Not_Implemented {
			state.state = .cleanup_failed
			state.cleanup_operation = .destroy
			state.cleanup_error = free_error
			state.next = prototype_registry_head
			prototype_registry_head = state
			state.busy = false
		} else {
			machine^ = {}
		}
		sync.mutex_unlock(&prototype_registry_mutex)
		return false
	}
	state.nodes = nodes
	state.state = .building
	prototype_release_claim(state)
	return true
}

@(private)
prototype_handle_is_valid :: proc(
	machine: ^prototype_machine_state,
	handle: prototype_node_handle,
) -> bool {
	return machine != nil &&
	       handle.machine_id == machine.id &&
	       handle.slot >= 0 &&
	       handle.slot < len(machine.nodes)
}

// Node handles combine the machine's process-unique identifier with a stable slot.
// Slots remain valid across node-array growth, while destroy/reinitialize,
// another machine, and stale machine copies all reject old handles.
@(private)
prototype_add_node :: proc(
	machine: ^prototype_machine_state,
	node: prototype_node,
) -> (handle: prototype_node_handle, ok: bool) {
	if machine == nil || machine.state != .building {
		return {}, false
	}

	slot := len(machine.nodes)
	_, err := append(&machine.nodes, node)
	if err != nil {
		return {}, false
	}
	return prototype_node_handle {
		machine_id = machine.id,
		slot = slot,
	}, true
}

@(private)
prototype_free_succeeded :: proc(err: runtime.Allocator_Error) -> bool {
	return err == nil || err == .Mode_Not_Implemented
}

@(private)
prototype_mark_cleanup_failure :: proc(
	machine: ^prototype_machine_state,
	operation: prototype_cleanup_operation,
	resume, terminal: prototype_state,
	err: runtime.Allocator_Error,
) {
	machine.state = .cleanup_failed
	machine.cleanup_operation = operation
	machine.cleanup_resume = resume
	machine.cleanup_terminal = terminal
	machine.cleanup_error = err
}

@(private)
prototype_retry_rollback :: proc(
	machine: ^prototype_machine_state,
	operation: prototype_cleanup_operation,
) -> runtime.Allocator_Error {
	if machine.state != .cleanup_failed || machine.cleanup_operation != operation {
		return nil
	}
	if machine.rollback_offsets != nil {
		err := delete(machine.rollback_offsets)
		if !prototype_free_succeeded(err) {
			machine.cleanup_error = err
			return err
		}
		machine.rollback_offsets = nil
	}
	if machine.rollback_frames != nil {
		err := delete(machine.rollback_frames)
		if !prototype_free_succeeded(err) {
			machine.cleanup_error = err
			return err
		}
		machine.rollback_frames = nil
	}
	machine.state = machine.cleanup_resume
	machine.cleanup_operation = .none
	machine.cleanup_resume = .uninitialized
	machine.cleanup_error = nil
	return nil
}

@(private)
prototype_add_values_with_terminal_error :: proc(
	machine: ^prototype_machine_state,
	offsets: []i64,
	has_terminal_error: bool,
	error_code: int,
) -> (handle: prototype_node_handle, ok: bool) {
	if machine == nil {
		return {}, false
	}
	if machine.state == .cleanup_failed {
		if machine.cleanup_operation != .add_rollback ||
		   prototype_retry_rollback(machine, .add_rollback) != nil {
			return {}, false
		}
	}
	if machine.state != .building {
		return {}, false
	}

	owned_offsets, err := make([dynamic]i64, 0, len(offsets), machine.allocator)
	if err != nil {
		return {}, false
	}
	_, err = append(&owned_offsets, ..offsets)
	if err != nil {
		if owned_offsets != nil {
			free_error := delete(owned_offsets)
			if !prototype_free_succeeded(free_error) {
				machine.rollback_offsets = owned_offsets
				prototype_mark_cleanup_failure(
					machine,
					.add_rollback,
					.building,
					.uninitialized,
					free_error,
				)
			}
		}
		return {}, false
	}

	handle, ok = prototype_add_node(machine, prototype_node {
		kind = .values,
		offsets = owned_offsets,
		has_terminal_error = has_terminal_error,
		error_code = error_code,
	})
	if !ok && owned_offsets != nil {
		free_error := delete(owned_offsets)
		if !prototype_free_succeeded(free_error) {
			machine.rollback_offsets = owned_offsets
			prototype_mark_cleanup_failure(
				machine,
				.add_rollback,
				.building,
				.uninitialized,
				free_error,
			)
		}
	}
	return
}

@(private)
prototype_add_values :: proc(
	machine: ^prototype_machine,
	offsets: []i64,
) -> (handle: prototype_node_handle, ok: bool) {
	if machine == nil {
		return {}, false
	}
	claim := prototype_claim_state(machine^)
	if claim.kind != .claimed {
		return {}, false
	}
	state := claim.state
	defer prototype_release_claim(state)
	return prototype_add_values_with_terminal_error(
		state,
		offsets,
		false,
		0,
	)
}

@(private)
prototype_add_values_then_error :: proc(
	machine: ^prototype_machine,
	offsets: []i64,
	error_code: int,
) -> (handle: prototype_node_handle, ok: bool) {
	if machine == nil {
		return {}, false
	}
	claim := prototype_claim_state(machine^)
	if claim.kind != .claimed {
		return {}, false
	}
	state := claim.state
	defer prototype_release_claim(state)
	return prototype_add_values_with_terminal_error(
		state,
		offsets,
		true,
		error_code,
	)
}

@(private)
prototype_add_empty :: proc(
	machine: ^prototype_machine,
) -> (handle: prototype_node_handle, ok: bool) {
	if machine == nil {
		return {}, false
	}
	claim := prototype_claim_state(machine^)
	if claim.kind != .claimed {
		return {}, false
	}
	state := claim.state
	defer prototype_release_claim(state)
	return prototype_add_node(
		state,
		prototype_node{kind = .empty},
	)
}

@(private)
prototype_add_error :: proc(
	machine: ^prototype_machine,
	error_code: int,
) -> (handle: prototype_node_handle, ok: bool) {
	if machine == nil {
		return {}, false
	}
	claim := prototype_claim_state(machine^)
	if claim.kind != .claimed {
		return {}, false
	}
	state := claim.state
	defer prototype_release_claim(state)
	return prototype_add_values_with_terminal_error(
		state,
		nil,
		true,
		error_code,
	)
}

// Scoped nodes refer only to previously constructed nodes. This makes the
// graph acyclic, so len(nodes) is a sufficient maximum frame depth.
@(private)
prototype_add_limited_then :: proc(
	machine: ^prototype_machine,
	inner: prototype_node_handle,
	limit: int,
	outer: prototype_node_handle,
) -> (handle: prototype_node_handle, ok: bool) {
	if machine == nil {
		return {}, false
	}
	claim := prototype_claim_state(machine^)
	if claim.kind != .claimed {
		return {}, false
	}
	state := claim.state
	defer prototype_release_claim(state)
	if !prototype_handle_is_valid(state, inner) ||
	   !prototype_handle_is_valid(state, outer) {
		return {}, false
	}
	return prototype_add_node(state, prototype_node {
		kind = .limited_then,
		inner_slot = inner.slot,
		limit = limit,
		outer_slot = outer.slot,
	})
}

@(private)
prototype_prepare_frames :: proc(
	machine: ^prototype_machine_state,
	root_slot: int,
	input: i64,
) -> bool {
	frames, err := make(
		[dynamic]prototype_frame,
		0,
		len(machine.nodes),
		machine.allocator,
	)
	if err != nil {
		return false
	}
	_, err = append(&frames, prototype_frame {
		node_slot = root_slot,
		input = input,
	})
	if err != nil {
		if frames != nil {
			free_error := delete(frames)
			if !prototype_free_succeeded(free_error) {
				machine.rollback_frames = frames
				prototype_mark_cleanup_failure(
					machine,
					.start_rollback,
					.building,
					.uninitialized,
					free_error,
				)
			}
		}
		return false
	}
	machine.frames = frames
	return true
}

@(private)
prototype_start_single :: proc(
	machine: ^prototype_machine,
	root: prototype_node_handle,
	input: i64,
) -> bool {
	if machine == nil {
		return false
	}
	claim := prototype_claim_state(machine^)
	if claim.kind != .claimed {
		return false
	}
	state := claim.state
	defer prototype_release_claim(state)
	if state.state == .cleanup_failed {
		if state.cleanup_operation != .start_rollback ||
		   prototype_retry_rollback(state, .start_rollback) != nil {
			return false
		}
	}
	if !prototype_handle_is_valid(state, root) ||
	   state.state != .building ||
	   !prototype_prepare_frames(state, root.slot, input) {
		return false
	}

	state.mode = .single
	state.state = .active
	return true
}

@(private)
prototype_node_is_leaf :: proc(machine: ^prototype_machine_state, slot: int) -> bool {
	return machine.nodes[slot].kind != .limited_then
}

@(private)
prototype_start_cartesian :: proc(
	machine: ^prototype_machine,
	left, right: prototype_node_handle,
	input: i64,
) -> bool {
	if machine == nil {
		return false
	}
	claim := prototype_claim_state(machine^)
	if claim.kind != .claimed {
		return false
	}
	state := claim.state
	defer prototype_release_claim(state)
	if !prototype_handle_is_valid(state, left) ||
	   !prototype_handle_is_valid(state, right) ||
	   state.state != .building ||
	   !prototype_node_is_leaf(state, left.slot) ||
	   !prototype_node_is_leaf(state, right.slot) {
		return false
	}

	state.mode = .cartesian
	state.left = prototype_cursor{node_slot = left.slot, input = input}
	state.right_slot = right.slot
	state.right_active = false
	state.state = .active
	return true
}

@(private)
prototype_release_owned :: proc(machine: ^prototype_machine_state) -> runtime.Allocator_Error {
	if machine.rollback_offsets != nil {
		err := delete(machine.rollback_offsets)
		if !prototype_free_succeeded(err) {
			return err
		}
		machine.rollback_offsets = nil
	}
	if machine.rollback_frames != nil {
		err := delete(machine.rollback_frames)
		if !prototype_free_succeeded(err) {
			return err
		}
		machine.rollback_frames = nil
	}
	if machine.frames != nil {
		err := delete(machine.frames)
		if !prototype_free_succeeded(err) {
			return err
		}
		machine.frames = nil
	}
	for node_index in 0..<len(machine.nodes) {
		if machine.nodes[node_index].offsets != nil {
			err := delete(machine.nodes[node_index].offsets)
			if !prototype_free_succeeded(err) {
				return err
			}
			machine.nodes[node_index].offsets = nil
		}
	}
	if machine.nodes != nil {
		err := delete(machine.nodes)
		if !prototype_free_succeeded(err) {
			return err
		}
		machine.nodes = nil
	}
	machine.allocator = {}
	return nil
}

@(private)
prototype_truncate_frames :: proc(machine: ^prototype_machine_state, count: int) {
	for len(machine.frames) > count {
		pop(&machine.frames)
	}
}

@(private)
prototype_finalize :: proc(
	handle: ^prototype_machine,
	machine: ^prototype_machine_state,
	operation: prototype_cleanup_operation,
	terminal: prototype_state,
	zero_handle: bool,
) -> (runtime.Allocator_Error, bool) {
	terminal_error_code := machine.error_code
	cleanup_error := prototype_release_owned(machine)
	if cleanup_error != nil {
		prototype_mark_cleanup_failure(
			machine,
			operation,
			machine.state,
			terminal,
			cleanup_error,
		)
		return cleanup_error, false
	}
	machine.right_active = false

	sync.mutex_lock(&prototype_registry_mutex)
	prototype_unlink_state_locked(machine)
	control_error := free(machine, runtime.heap_allocator())
	if !prototype_free_succeeded(control_error) {
		machine.next = prototype_registry_head
		prototype_registry_head = machine
		prototype_mark_cleanup_failure(
			machine,
			operation,
			machine.state,
			terminal,
			control_error,
		)
		sync.mutex_unlock(&prototype_registry_mutex)
		return control_error, false
	}
	if zero_handle {
		handle^ = {}
	} else {
		handle^ = prototype_machine {
			terminal = terminal,
			error_code = terminal_error_code,
		}
	}
	sync.mutex_unlock(&prototype_registry_mutex)
	return nil, true
}

// Stop the innermost currently active limited child. Truncating to its frame
// discards only that child. The pending phase acknowledges that discard once,
// so another stop cannot target the same child before the next step enters its
// immediate continuation.
@(private)
prototype_stop_inner_locked :: proc(machine: ^prototype_machine_state) -> bool {
	if machine == nil || machine.state != .active || machine.mode != .single {
		return false
	}
	for frame_index := len(machine.frames) - 1; frame_index >= 0; frame_index -= 1 {
		phase := machine.frames[frame_index].phase
		if phase == .limited_continuation_pending {
			return false
		}
		if phase == .limited_inner {
			prototype_truncate_frames(machine, frame_index + 1)
			machine.frames[frame_index].phase = .limited_continuation_pending
			return true
		}
	}
	return false
}

@(private)
prototype_stop_inner :: proc(machine: ^prototype_machine) -> bool {
	if machine == nil {
		return false
	}
	claim := prototype_claim_state(machine^)
	if claim.kind != .claimed {
		return false
	}
	state := claim.state
	defer prototype_release_claim(state)
	return prototype_stop_inner_locked(state)
}

@(private)
prototype_stop :: proc(machine: ^prototype_machine) -> runtime.Allocator_Error {
	if machine == nil {
		return nil
	}
	claim := prototype_claim_state(machine^)
	if claim.kind == .busy {
		return .Invalid_Argument
	}
	if claim.kind == .absent {
		return nil
	}
	state := claim.state
	if state.state == .cleanup_failed && state.cleanup_operation != .stop {
		err := state.cleanup_error
		prototype_release_claim(state)
		return err
	}
	if state.state != .building && state.state != .active &&
	   !(state.state == .cleanup_failed && state.cleanup_operation == .stop) {
		prototype_release_claim(state)
		return nil
	}
	err, retired := prototype_finalize(machine, state, .stop, .stopped, false)
	if !retired {
		prototype_release_claim(state)
	}
	return err
}

@(private)
prototype_destroy :: proc(machine: ^prototype_machine) -> runtime.Allocator_Error {
	if machine == nil {
		return nil
	}
	claim := prototype_claim_state(machine^)
	if claim.kind == .busy {
		return .Invalid_Argument
	}
	if claim.kind == .absent {
		machine^ = {}
		return nil
	}
	state := claim.state
	err, retired := prototype_finalize(machine, state, .destroy, .uninitialized, true)
	if !retired {
		state.cleanup_operation = .destroy
		prototype_release_claim(state)
	}
	return err
}

@(private)
prototype_step_cursor :: proc(
	machine: ^prototype_machine_state,
	cursor: ^prototype_cursor,
) -> prototype_step {
	node := &machine.nodes[cursor.node_slot]
	switch node.kind {
	case .values:
		if cursor.next < len(node.offsets) {
			right_component := node.offsets[cursor.next]
			cursor.next += 1
			return prototype_step {
				kind = .output,
				input = cursor.input,
				left_component = cursor.left_component,
				right_component = right_component,
			}
		}
		if node.has_terminal_error {
			return prototype_step {
				kind = .runtime_error,
				error_code = node.error_code,
			}
		}
		return prototype_step{kind = .exhausted}
	case .empty:
		return prototype_step{kind = .exhausted}
	case .limited_then:
		unreachable()
	}
	unreachable()
}

@(private)
prototype_push_frame :: proc(
	machine: ^prototype_machine_state,
	node_slot: int,
	input: i64,
) -> bool {
	_, err := append(&machine.frames, prototype_frame {
		node_slot = node_slot,
		input = input,
	})
	return err == nil
}

@(private)
prototype_record_scoped_output :: proc(machine: ^prototype_machine_state) {
	truncate_to := len(machine.frames)
	for frame_index in 0..<len(machine.frames) - 1 {
		frame := &machine.frames[frame_index]
		if frame.phase != .limited_inner {
			continue
		}
		frame.inner_outputs += 1
		node := &machine.nodes[frame.node_slot]
		if frame.inner_outputs >= node.limit {
			truncate_to = min(truncate_to, frame_index + 1)
		}
	}
	if truncate_to < len(machine.frames) {
		prototype_truncate_frames(machine, truncate_to)
	}
}

@(private)
prototype_step_scoped :: proc(machine: ^prototype_machine_state) -> prototype_step {
	for len(machine.frames) > 0 {
		frame_index := len(machine.frames) - 1
		frame := &machine.frames[frame_index]
		node := &machine.nodes[frame.node_slot]

		switch frame.phase {
		case .enter:
			switch node.kind {
			case .values:
				frame.phase = .values
			case .empty:
				prototype_truncate_frames(machine, frame_index)
			case .limited_then:
				if node.limit < 0 {
					return prototype_step {
						kind = .runtime_error,
						error_code = prototype_negative_limit_error,
					}
				}
				inner_slot := node.inner_slot
				input := frame.input
				frame.phase = .limited_inner
				if node.limit > 0 &&
				   !prototype_push_frame(machine, inner_slot, input) {
					return prototype_step {
						kind = .runtime_error,
						error_code = prototype_frame_allocation_error,
					}
				}
			}
		case .values:
			if frame.next < len(node.offsets) {
				right_component := node.offsets[frame.next]
				frame.next += 1
				result := prototype_step {
					kind = .output,
					input = frame.input,
					right_component = right_component,
				}
				prototype_record_scoped_output(machine)
				return result
			}
			if node.has_terminal_error {
				return prototype_step {
					kind = .runtime_error,
					error_code = node.error_code,
				}
			}
			prototype_truncate_frames(machine, frame_index)
		case .limited_inner, .limited_continuation_pending:
			outer_slot := node.outer_slot
			input := frame.input
			frame.phase = .limited_outer
			if !prototype_push_frame(machine, outer_slot, input) {
				return prototype_step {
					kind = .runtime_error,
					error_code = prototype_frame_allocation_error,
				}
			}
		case .limited_outer:
			prototype_truncate_frames(machine, frame_index)
		}
	}
	return prototype_step{kind = .exhausted}
}

@(private)
prototype_fail :: proc(machine: ^prototype_machine_state, result: prototype_step) -> prototype_step {
	machine.error_code = result.error_code
	machine.right_active = false
	machine.state = .failed
	return result
}

@(private)
prototype_step_machine_locked :: proc(machine: ^prototype_machine_state) -> prototype_step {
	if machine == nil {
		return prototype_step{kind = .exhausted}
	}

	switch machine.state {
	case .exhausted, .stopped:
		return prototype_step{kind = .exhausted}
	case .failed:
		return prototype_step{kind = .runtime_error, error_code = machine.error_code}
	case .uninitialized:
		return prototype_step{kind = .exhausted}
	case .initializing, .cleanup_failed:
		return prototype_step{kind = .operation_in_progress}
	case .building:
		machine.right_active = false
		machine.state = .exhausted
		return prototype_step{kind = .exhausted}
	case .active:
	}

	switch machine.mode {
	case .single:
		result := prototype_step_scoped(machine)
		#partial switch result.kind {
		case .output:
			return result
		case .exhausted:
			machine.right_active = false
			machine.state = .exhausted
			return result
		case .runtime_error:
			return prototype_fail(machine, result)
		}
	case .cartesian:
		for {
			if machine.right_active {
				right_result := prototype_step_cursor(machine, &machine.right)
				#partial switch right_result.kind {
				case .output:
					return right_result
				case .exhausted:
					machine.right_active = false
				case .runtime_error:
					return prototype_fail(machine, right_result)
				}
			}

			left_result := prototype_step_cursor(machine, &machine.left)
			#partial switch left_result.kind {
			case .output:
				machine.right = prototype_cursor {
					node_slot = machine.right_slot,
					input = left_result.input,
					left_component = left_result.right_component,
				}
				machine.right_active = true
			case .exhausted:
				machine.right_active = false
				machine.state = .exhausted
				return left_result
			case .runtime_error:
				return prototype_fail(machine, left_result)
			}
		}
	case .unconfigured:
		machine.right_active = false
		machine.state = .exhausted
		return prototype_step{kind = .exhausted}
	}
	unreachable()
}

@(private)
prototype_claim_observer :: #type proc(data: rawptr, kind: prototype_claim_kind)

@(private)
prototype_step_machine_impl :: proc(
	machine: ^prototype_machine,
	observer_data: rawptr,
	observer: prototype_claim_observer,
) -> prototype_step {
	if machine == nil {
		return prototype_step{kind = .exhausted}
	}
	claim := prototype_claim_state(machine^)
	if observer != nil {
		observer(observer_data, claim.kind)
	}
	if claim.kind == .busy {
		return prototype_step{kind = .operation_in_progress}
	}
	if claim.kind == .absent {
		if machine.terminal == .failed {
			return prototype_step {
				kind = .runtime_error,
				error_code = machine.error_code,
			}
		}
		return prototype_step{kind = .exhausted}
	}
	state := claim.state
	if state.state == .cleanup_failed {
		if state.cleanup_operation != .terminal_step {
			err := state.cleanup_error
			prototype_release_claim(state)
			return prototype_step{kind = .cleanup_error, cleanup_error = err}
		}
		terminal := state.cleanup_terminal
		err, retired := prototype_finalize(machine, state, .terminal_step, terminal, false)
		if !retired {
			prototype_release_claim(state)
			return prototype_step{kind = .cleanup_error, cleanup_error = err}
		}
		if terminal == .failed {
			return prototype_step {
				kind = .runtime_error,
				error_code = machine.error_code,
			}
		}
		return prototype_step{kind = .exhausted}
	}
	result := prototype_step_machine_locked(state)
	if state.state == .exhausted || state.state == .failed {
		terminal := state.state
		err, retired := prototype_finalize(machine, state, .terminal_step, terminal, false)
		if !retired {
			prototype_release_claim(state)
			return prototype_step{kind = .cleanup_error, cleanup_error = err}
		}
		return result
	}
	prototype_release_claim(state)
	return result
}

@(private)
prototype_step_machine :: proc(machine: ^prototype_machine) -> prototype_step {
	return prototype_step_machine_impl(machine, nil, nil)
}
