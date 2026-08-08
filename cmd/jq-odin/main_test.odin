package main

import "base:runtime"
import "core:testing"

input_fault_allocator_state :: struct {
	backing: runtime.Allocator,
	allocations: [2]rawptr,
	allocation_count: int,
	free_attempts: [4]rawptr,
	free_attempt_count: int,
	free_failures_remaining: int,
	live: int,
}

input_fault_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^input_fault_allocator_state)data
	if mode == .Free {
		if state.free_attempt_count < len(state.free_attempts) {
			state.free_attempts[state.free_attempt_count] = old_memory
		}
		state.free_attempt_count += 1
		if state.free_failures_remaining > 0 {
			state.free_failures_remaining -= 1
			return nil, .Invalid_Argument
		}
	}
	memory, err := state.backing.procedure(
		state.backing.data, mode, size, alignment, old_memory, old_size, location,
	)
	if err == nil || err == .Mode_Not_Implemented {
		if mode == .Alloc || mode == .Alloc_Non_Zeroed {
			if state.allocation_count < len(state.allocations) {
				state.allocations[state.allocation_count] = raw_data(memory)
			}
			state.allocation_count += 1
			state.live += 1
		} else if mode == .Free {
			state.live -= 1
		}
	}
	return memory, err
}

input_fault_allocator :: proc(state: ^input_fault_allocator_state) -> runtime.Allocator {
	return {procedure = input_fault_allocator_proc, data = state}
}

rejected_input_kind :: enum u8 {
	Nil,
	Short,
	Oversized,
	Errored,
	Misaligned,
}

rejected_input_allocator_state :: struct {
	backing: runtime.Allocator,
	kind: rejected_input_kind,
	allocation_count: int,
	old_memory: []byte,
	rejected_backing: []byte,
	rejected_memory: []byte,
	free_addresses: [8]rawptr,
	free_sizes: [8]int,
	free_count: int,
	rejected_free_failures: int,
	old_free_failures: int,
	live: int,
}

rejected_input_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	state := cast(^rejected_input_allocator_state)data
	if mode == .Alloc || mode == .Alloc_Non_Zeroed {
		state.allocation_count += 1
		if state.allocation_count == 2 {
			if state.kind == .Nil do return nil, nil
			actual_size := size
			switch state.kind {
			case .Short: actual_size = size-1
			case .Oversized: actual_size = size+7
			case .Misaligned: actual_size = size+1
			case .Errored, .Nil:
			}
			memory, err := runtime.mem_alloc_bytes(actual_size, alignment, state.backing)
			if err != nil do return memory, err
			state.rejected_backing = memory
			state.rejected_memory = memory
			if state.kind == .Misaligned {
				state.rejected_memory = memory[1:]
			}
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
		if len(state.old_memory) > 0 && old_memory == raw_data(state.old_memory) &&
		   state.old_free_failures > 0 {
			state.old_free_failures -= 1
			return nil, .Invalid_Argument
		}
	}
	memory, err := state.backing.procedure(
		state.backing.data, mode, size, alignment, old_memory, old_size, location,
	)
	if err == nil || err == .Mode_Not_Implemented {
		if mode == .Alloc || mode == .Alloc_Non_Zeroed {
			state.old_memory = memory
			state.live += 1
		} else if mode == .Free {
			state.old_memory = nil
			state.live -= 1
		}
	}
	return memory, err
}

rejected_input_allocator :: proc(state: ^rejected_input_allocator_state) -> runtime.Allocator {
	return {procedure = rejected_input_allocator_proc, data = state}
}

@(test)
input_growth_retains_both_allocations_when_both_frees_fail :: proc(t: ^testing.T) {
	state := input_fault_allocator_state{backing = context.allocator}
	saved_allocator := context.allocator
	context.allocator = input_fault_allocator(&state)
	defer context.allocator = saved_allocator

	buffer := input_buffer{bom_eligible = true}
	initial: [INPUT_CHUNK_SIZE]byte
	for index in 0..<len(initial) do initial[index] = byte(index%251)
	testing.expect(t, append_input(&buffer, initial[:]))
	testing.expect_value(t, state.allocation_count, 1)
	old_memory := rawptr(raw_data(buffer.memory))

	state.free_failures_remaining = 2
	next := [1]byte{0xee}
	testing.expect_value(t, append_input(&buffer, next[:]), false)
	testing.expect_value(t, state.allocation_count, 2)
	replacement_memory := state.allocations[1]
	testing.expect(t, old_memory != replacement_memory)
	testing.expect_value(t, rawptr(raw_data(buffer.memory)), old_memory)
	testing.expect_value(t, rawptr(raw_data(buffer.cleanup_memory)), replacement_memory)
	testing.expect_value(t, buffer.length, len(initial))
	testing.expect_value(t, state.live, 2)
	testing.expect_value(t, state.free_attempt_count, 2)
	testing.expect_value(t, state.free_attempts[0], old_memory)
	testing.expect_value(t, state.free_attempts[1], replacement_memory)
	for index in 0..<len(initial) {
		testing.expect_value(t, buffer.memory[index], initial[index])
	}

	// Cleanup-only state cannot allocate, reread, append, or publish bytes.
	testing.expect_value(t, reserve_input(&buffer, 1), false)
	testing.expect_value(t, state.allocation_count, 2)
	testing.expect_value(t, buffer.length, len(initial))

	// The later retry releases the replacement first, then the published old
	// allocation. A repeated destroy is inert and cannot double-free either.
	testing.expect(t, destroy_input_buffer(&buffer))
	testing.expect_value(t, state.free_attempt_count, 4)
	testing.expect_value(t, state.free_attempts[2], replacement_memory)
	testing.expect_value(t, state.free_attempts[3], old_memory)
	testing.expect_value(t, state.live, 0)
	testing.expect(t, destroy_input_buffer(&buffer))
	testing.expect_value(t, state.free_attempt_count, 4)
}

@(test)
rejected_input_allocations_preserve_exact_cleanup_owner_and_retry :: proc(t: ^testing.T) {
	kinds := [5]rejected_input_kind{.Nil, .Short, .Oversized, .Errored, .Misaligned}
	for kind in kinds {
		state := rejected_input_allocator_state{
			backing = context.allocator,
			kind = kind,
			rejected_free_failures = 2,
			old_free_failures = 1,
		}
		saved_allocator := context.allocator
		context.allocator = rejected_input_allocator(&state)

		buffer := input_buffer{bom_eligible = true}
		initial: [INPUT_CHUNK_SIZE]byte
		for index in 0..<len(initial) do initial[index] = byte(index%251)
		testing.expect(t, append_input(&buffer, initial[:]))
		old_address := rawptr(raw_data(buffer.memory))
		old_size := len(buffer.memory)
		testing.expect_value(t, append_input(&buffer, []byte{0xee}), false)
		testing.expect_value(t, state.allocation_count, 2)
		testing.expect_value(t, rawptr(raw_data(buffer.memory)), old_address)
		testing.expect_value(t, len(buffer.memory), old_size)
		testing.expect_value(t, buffer.length, len(initial))

		if kind == .Nil {
			testing.expect_value(t, len(buffer.cleanup_memory), 0)
			testing.expect_value(t, state.free_count, 0)
		} else {
			rejected_address := rawptr(raw_data(state.rejected_memory))
			rejected_size := len(state.rejected_memory)
			testing.expect_value(t, rawptr(raw_data(buffer.cleanup_memory)), rejected_address)
			testing.expect_value(t, len(buffer.cleanup_memory), rejected_size)
			testing.expect_value(t, state.free_addresses[0], rejected_address)
			testing.expect_value(t, state.free_sizes[0], rejected_size)
			testing.expect_value(t, state.live, 2)
			// Cleanup-only retry cannot reserve, append, or mutate already buffered
			// input, so no caller can reread or republish it after this failure.
			testing.expect_value(t, reserve_input(&buffer, 1), false)
			testing.expect_value(t, append_input(&buffer, []byte{0xaa}), false)
			testing.expect_value(t, state.allocation_count, 2)
			testing.expect_value(t, buffer.length, len(initial))
			for index in 0..<len(initial) {
				testing.expect_value(t, buffer.memory[index], initial[index])
			}

			// Immediate retirement and the first destroy both fail for the exact
			// rejected slice. The next destroy frees it, then reaches a separately
			// failing old owner. A final retry releases only that old owner.
			testing.expect_value(t, destroy_input_buffer(&buffer), false)
			testing.expect_value(t, rawptr(raw_data(buffer.cleanup_memory)), rejected_address)
			testing.expect_value(t, destroy_input_buffer(&buffer), false)
			testing.expect_value(t, len(buffer.cleanup_memory), 0)
			testing.expect_value(t, rawptr(raw_data(buffer.memory)), old_address)
			testing.expect(t, destroy_input_buffer(&buffer))
			testing.expect_value(t, state.live, 0)
			free_count := state.free_count
			testing.expect(t, destroy_input_buffer(&buffer))
			testing.expect_value(t, state.free_count, free_count)
			context.allocator = saved_allocator
			continue
		}

		// Nil rejection retains no second owner; retire the unchanged old input.
		state.old_free_failures = 0
		testing.expect(t, destroy_input_buffer(&buffer))
		testing.expect_value(t, state.live, 0)
		context.allocator = saved_allocator
	}
}
