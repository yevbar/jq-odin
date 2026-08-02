package syntax

import "base:runtime"

@(private="package")
Fallible_Buffer_State :: enum u8 {
	Empty,
	Owned,
	Transfer_Pending,
}

// Fallible_Buffer owns allocation-sized slices rather than relying on dynamic
// array growth. During growth, storage remains the active handle until its
// release succeeds. If that release fails, replacement remains explicitly
// owned and the transfer can be retried without allocating or copying again.
@(private="package")
Fallible_Buffer :: struct($T: typeid) {
	storage:     []T,
	count:       int,
	replacement: []T,
	allocator:   runtime.Allocator,
	state:       Fallible_Buffer_State,
}

@(private="package")
init_fallible_buffer :: proc(buffer: ^Fallible_Buffer($T), allocator: runtime.Allocator) {
	buffer^ = {}
	buffer.allocator = allocator
}

@(private="package")
fallible_buffer_view :: proc(buffer: ^Fallible_Buffer($T)) -> []T {
	return buffer.storage[:buffer.count]
}

@(private="package")
retry_fallible_buffer_transfer :: proc(
	buffer: ^Fallible_Buffer($T),
) -> runtime.Allocator_Error {
	if buffer.state != .Transfer_Pending {
		return nil
	}

	free_error := delete(buffer.storage, buffer.allocator)
	if free_error != nil && free_error != .Mode_Not_Implemented {
		return free_error
	}
	buffer.storage = buffer.replacement
	buffer.replacement = nil
	buffer.state = .Owned
	return nil
}

@(private="package")
append_fallible_buffer :: proc(
	buffer: ^Fallible_Buffer($T),
	value: T,
) -> runtime.Allocator_Error {
	if transfer_error := retry_fallible_buffer_transfer(buffer); transfer_error != nil {
		return transfer_error
	}
	if buffer.count < len(buffer.storage) {
		buffer.storage[buffer.count] = value
		buffer.count += 1
		return nil
	}
	if buffer.allocator.procedure == nil {
		return .Out_Of_Memory
	}

	new_capacity := 8
	if len(buffer.storage) > 0 {
		if len(buffer.storage) > max(int) / 2 {
			return .Out_Of_Memory
		}
		new_capacity = len(buffer.storage) * 2
	}
	replacement, allocation_error := make([]T, new_capacity, buffer.allocator)
	if allocation_error != nil {
		return allocation_error
	}
	copy(replacement[:buffer.count], buffer.storage[:buffer.count])

	if buffer.state == .Empty {
		buffer.storage = replacement
		buffer.state = .Owned
	} else {
		free_error := delete(buffer.storage, buffer.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			buffer.replacement = replacement
			buffer.state = .Transfer_Pending
			return free_error
		}
		buffer.storage = replacement
	}

	buffer.storage[buffer.count] = value
	buffer.count += 1
	return nil
}

@(private="package")
destroy_fallible_buffer :: proc(
	buffer: ^Fallible_Buffer($T),
) -> runtime.Allocator_Error {
	if transfer_error := retry_fallible_buffer_transfer(buffer); transfer_error != nil {
		return transfer_error
	}
	if buffer.state == .Owned {
		free_error := delete(buffer.storage, buffer.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			return free_error
		}
	}
	buffer.storage = nil
	buffer.count = 0
	buffer.replacement = nil
	buffer.allocator = {}
	buffer.state = .Empty
	return nil
}
