package value

import "base:runtime"

Value_Add_Error_Kind :: enum u8 {
	None,
	Invalid_Type_Pair,
	Invalid_Operand,
	Size_Overflow,
	Out_Of_Memory,
	Allocator_Unsupported,
	Cleanup_Failed,
}

@(private)
value_add_error_storage :: struct {
	kind:              Value_Add_Error_Kind,
	cause:             Value_Add_Error_Kind,
	cleanup_value:     Value,
	cleanup_work:      ^value_add_clone_frame,
	validation_work:   ^value_add_validation_block,
	constructor_error: Constructor_Error,
}

// Value_Add_Error is inert unless it owns failed partial-result cleanup. It
// must not be copied; transfer it with take_value_add_error and retire it with
// destroy_value_add_error before tearing down any captured allocator.
Value_Add_Error :: union {
	value_add_error_storage,
}

@(private)
make_value_add_error :: proc(kind: Value_Add_Error_Kind) -> Value_Add_Error {
	if kind == .None do return {}
	return value_add_error_storage{kind = kind}
}

value_add_error_kind :: proc(err: ^Value_Add_Error) -> Value_Add_Error_Kind {
	if err == nil || err^ == nil do return .None
	return err.(value_add_error_storage).kind
}

// value_add_error_cause returns the failure that cleanup interrupted. It is
// None unless value_add_error_kind is Cleanup_Failed.
value_add_error_cause :: proc(err: ^Value_Add_Error) -> Value_Add_Error_Kind {
	if err == nil || err^ == nil do return .None
	return err.(value_add_error_storage).cause
}

value_add_error_needs_cleanup :: proc(err: ^Value_Add_Error) -> bool {
	if err == nil || err^ == nil do return false
	storage := &err.(value_add_error_storage)
	return kind_of(&storage.cleanup_value) != .Invalid ||
	       storage.cleanup_work != nil ||
	       storage.validation_work != nil ||
	       constructor_error_needs_cleanup(&storage.constructor_error)
}

take_value_add_error :: proc(source: ^Value_Add_Error) -> Value_Add_Error {
	if source == nil do return {}
	result := source^
	source^ = {}
	return result
}

// Cleanup is deterministic: construction frames are retired while all of
// their borrowed destination payloads remain live, followed by the partial
// Value and any mismatched raw allocation. A genuine failure preserves the
// whole error and its exact cursor for retry. Mode_Not_Implemented is
// successful bulk retirement.
destroy_value_add_error :: proc(err: ^Value_Add_Error) -> runtime.Allocator_Error {
	if err == nil || err^ == nil do return nil
	storage := &err.(value_add_error_storage)
	work_error := value_add_destroy_work(&storage.cleanup_work)
	if work_error != nil do return work_error
	validation_error := value_add_destroy_validation_work(&storage.validation_work)
	if validation_error != nil do return validation_error
	value_error := destroy_value(&storage.cleanup_value)
	if value_error != nil do return value_error
	constructor_error := destroy_constructor_error(&storage.constructor_error)
	if constructor_error != nil do return constructor_error
	err^ = {}
	return nil
}

@(private)
value_add_error_from_constructor :: proc(
	kind: Value_Add_Error_Kind,
	err: ^Constructor_Error,
) -> Value_Add_Error {
	result_kind := kind
	if constructor_error_needs_cleanup(err) do result_kind = .Cleanup_Failed
	result := make_value_add_error(result_kind)
	if result_kind == .Cleanup_Failed {
		(&result.(value_add_error_storage)).cause = kind
	}
	if err != nil && err^ != nil {
		(&result.(value_add_error_storage)).constructor_error = take_constructor_error(err)
	}
	return result
}

@(private)
value_add_error_from_array :: proc(err: ^Array_Operation_Error) -> Value_Add_Error {
	kind := Value_Add_Error_Kind.Out_Of_Memory
	switch array_error_kind(err) {
	case .Size_Overflow:
		kind = .Size_Overflow
	case .Allocator_Unsupported:
		kind = .Allocator_Unsupported
	case .Wrong_Kind, .Invalid_Index, .Index_Too_Large, .Aliased_Operand:
		kind = .Invalid_Operand
	case .Cleanup_Failed:
		kind = .Cleanup_Failed
	case .None:
		return {}
	case .Out_Of_Memory:
	}
	result := make_value_add_error(kind)
	if kind == .Cleanup_Failed {
		cause := value_add_kind_from_array(array_error_cause(err))
		storage := &err.(array_operation_error_storage)
		if cause == .None do cause = value_add_kind_from_constructor(&storage.constructor_error)
		if cause != .None do (&result.(value_add_error_storage)).cause = cause
	}
	storage := &err.(array_operation_error_storage)
	if kind != .Cleanup_Failed && constructor_error_needs_cleanup(&storage.constructor_error) {
		result = make_value_add_error(.Cleanup_Failed)
		(&result.(value_add_error_storage)).cause = kind
	}
	(&result.(value_add_error_storage)).constructor_error =
		take_constructor_error(&storage.constructor_error)
	err^ = {}
	return result
}

@(private)
value_add_error_from_object :: proc(err: ^Object_Operation_Error) -> Value_Add_Error {
	kind := Value_Add_Error_Kind.Out_Of_Memory
	switch object_error_kind(err) {
	case .Size_Overflow:
		kind = .Size_Overflow
	case .Allocator_Unsupported:
		kind = .Allocator_Unsupported
	case .Wrong_Kind, .Aliased_Operand:
		kind = .Invalid_Operand
	case .Cleanup_Failed:
		kind = .Cleanup_Failed
	case .None:
		return {}
	case .Out_Of_Memory:
	}
	result := make_value_add_error(kind)
	if kind == .Cleanup_Failed {
		cause := value_add_kind_from_object(object_error_cause(err))
		storage := &err.(object_operation_error_storage)
		if cause == .None do cause = value_add_kind_from_constructor(&storage.constructor_error)
		if cause != .None do (&result.(value_add_error_storage)).cause = cause
	}
	storage := &err.(object_operation_error_storage)
	if kind != .Cleanup_Failed && constructor_error_needs_cleanup(&storage.constructor_error) {
		result = make_value_add_error(.Cleanup_Failed)
		(&result.(value_add_error_storage)).cause = kind
	}
	(&result.(value_add_error_storage)).constructor_error =
		take_constructor_error(&storage.constructor_error)
	err^ = {}
	return result
}

@(private)
value_add_kind_from_constructor :: proc(err: ^Constructor_Error) -> Value_Add_Error_Kind {
	if constructor_error_allocator_unsupported(err) do return .Allocator_Unsupported
	switch constructor_error_kind(err) {
	case .Out_Of_Memory:
		return .Out_Of_Memory
	case .Size_Overflow:
		return .Size_Overflow
	case .Invalid_Number_Literal:
		return .Invalid_Operand
	case .None:
		return .None
	}
	return .None
}

@(private)
value_add_kind_from_array :: proc(kind: Array_Error) -> Value_Add_Error_Kind {
	switch kind {
	case .Out_Of_Memory:
		return .Out_Of_Memory
	case .Size_Overflow:
		return .Size_Overflow
	case .Allocator_Unsupported:
		return .Allocator_Unsupported
	case .Wrong_Kind, .Invalid_Index, .Index_Too_Large, .Aliased_Operand:
		return .Invalid_Operand
	case .None, .Cleanup_Failed:
		return .None
	}
	return .None
}

@(private)
value_add_kind_from_object :: proc(kind: Object_Error) -> Value_Add_Error_Kind {
	switch kind {
	case .Out_Of_Memory:
		return .Out_Of_Memory
	case .Size_Overflow:
		return .Size_Overflow
	case .Allocator_Unsupported:
		return .Allocator_Unsupported
	case .Wrong_Kind, .Aliased_Operand:
		return .Invalid_Operand
	case .None, .Cleanup_Failed:
		return .None
	}
	return .None
}

@(private)
value_add_absorb_cleanup :: proc(destination: ^Value, err: ^Value_Add_Error) {
	if destination == nil || err == nil || err^ == nil do return
	storage := &err.(value_add_error_storage)
	if kind_of(&storage.cleanup_value) != .Invalid {
		destination^ = take_value(&storage.cleanup_value)
	}
}

@(private)
value_add_cleanup_partial :: proc(partial: ^Value, err: ^Value_Add_Error) {
	if err == nil || err^ == nil do return
	storage := &err.(value_add_error_storage)
	work_error := value_add_destroy_work(&storage.cleanup_work)
	if work_error != nil {
		if storage.kind != .Cleanup_Failed {
			storage.cause = storage.kind
			storage.kind = .Cleanup_Failed
		}
		if partial != nil && kind_of(partial) != .Invalid {
			storage.cleanup_value = take_value(partial)
		}
		return
	}
	if partial == nil || kind_of(partial) == .Invalid do return
	cleanup_error := destroy_value(partial)
	if cleanup_error != nil {
		if storage.kind != .Cleanup_Failed {
			storage.cause = storage.kind
			storage.kind = .Cleanup_Failed
		}
		storage.cleanup_value = take_value(partial)
	}
}

@(private)
value_add_clone_literal :: proc(
	source_storage: ^value_storage,
	allocator: runtime.Allocator,
) -> (Value, Value_Add_Error) {
	if !literal_storage_valid(source_storage) {
		return {}, make_value_add_error(.Invalid_Operand)
	}
	source := source_storage.owned_payload
	minimum_size := int(size_of(payload)) + source.byte_count
	coefficient_capacity := source_storage.payload_allocation_bound - minimum_size
	destination, constructor_error := allocate_payload(
		.Literal_Number,
		source.byte_count,
		coefficient_capacity,
		allocator,
	)
	if constructor_error_kind(&constructor_error) != .None {
		kind := value_add_kind_from_constructor(&constructor_error)
		return {}, value_add_error_from_constructor(kind, &constructor_error)
	}
	destination.coefficient_len = source.coefficient_len
	destination.exponent = source.exponent
	destination.negative = source.negative
	destination.explicit_positive_sign = source.explicit_positive_sign
	destination.infinite = source.infinite
	destination.native_cache = source.native_cache
	copy(payload_bytes(destination), payload_bytes(source))
	copy(
		literal_coefficient_capacity_borrowed(destination, coefficient_capacity),
		literal_coefficient_capacity_borrowed(source, coefficient_capacity),
	)
	return value_from_payload(.Number, destination), nil
}

@(private)
value_add_clone_frame_kind :: enum u8 {
	Array,
	Object,
}

// Frames borrow source payloads and destination payloads reachable from the
// result root. The linked chain is independently allocator-owned until each
// completed frame is freed or transferred with that root to Value_Add_Error.
@(private)
value_add_clone_frame :: struct {
	next:                ^value_add_clone_frame,
	allocator:           runtime.Allocator,
	kind:                value_add_clone_frame_kind,
	source_storage:      ^value_storage,
	source_payload:      ^payload,
	destination_payload: ^payload,
	at:                  int,
}

@(private)
value_add_destroy_work :: proc(head: ^^value_add_clone_frame) -> runtime.Allocator_Error {
	if head == nil do return nil
	for head^ != nil {
		frame := head^
		next := frame.next
		free_error := runtime.mem_free_with_size(
			frame,
			int(size_of(value_add_clone_frame)),
			frame.allocator,
		)
		if free_error != nil && free_error != .Mode_Not_Implemented do return free_error
		head^ = next
	}
	return nil
}

@(private)
value_add_allocate_frame :: proc(
	kind: value_add_clone_frame_kind,
	source_storage: ^value_storage,
	source_payload, destination_payload: ^payload,
	allocator: runtime.Allocator,
) -> (^value_add_clone_frame, Value_Add_Error) {
	size := int(size_of(value_add_clone_frame))
	memory, allocation_error := runtime.mem_alloc(size, align_of(value_add_clone_frame), allocator)
	if allocation_error != nil || len(memory) != size {
		constructor_error: Constructor_Error
		if len(memory) > 0 {
			free_error := runtime.mem_free_bytes(memory, allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				constructor_error = make_cleanup_constructor_error(.Out_Of_Memory, memory, allocator)
			}
		}
		kind := Value_Add_Error_Kind.Out_Of_Memory
		if allocation_error == .Mode_Not_Implemented do kind = .Allocator_Unsupported
		return nil, value_add_error_from_constructor(kind, &constructor_error)
	}
	frame := cast(^value_add_clone_frame)(raw_data(memory))
	frame^ = {
		allocator = allocator,
		kind = kind,
		source_storage = source_storage,
		source_payload = source_payload,
		destination_payload = destination_payload,
	}
	return frame, nil
}

@(private)
value_add_array_capacity :: proc(length: int) -> (int, bool) {
	if length < 0 do return 0, false
	capacity := max(length, ARRAY_INITIAL_CAPACITY)
	_, ok := array_allocation_size(capacity)
	return capacity, ok
}

@(private)
value_add_allocate_array :: proc(length: int, allocator: runtime.Allocator) -> (
	Value,
	Value_Add_Error,
) {
	capacity, capacity_ok := value_add_array_capacity(length)
	if !capacity_ok do return {}, make_value_add_error(.Size_Overflow)
	p, array_error := allocate_array_payload(capacity, allocator)
	if array_error_kind(&array_error) != .None {
		return {}, value_add_error_from_array(&array_error)
	}
	return value_from_payload(.Array, p), nil
}

@(private)
value_add_clone_start :: proc(
	source: ^Value,
	allocator: runtime.Allocator,
	head: ^^value_add_clone_frame,
) -> (Value, Value_Add_Error) {
	if !value_add_operand_local_valid(source) do return {}, make_value_add_error(.Invalid_Operand)
	storage := value_storage_of(source)
	switch storage.kind {
	case .Null:
		return null_value(), nil
	case .Boolean:
		return boolean_value(storage.boolean), nil
	case .Number:
		if storage.owned_payload == nil do return number_value(storage.native_number), nil
		return value_add_clone_literal(storage, allocator)
	case .String:
		result, constructor_error := string_value(
			transmute(string)payload_bytes(storage.owned_payload),
			allocator,
		)
		if constructor_error_kind(&constructor_error) != .None {
			kind := value_add_kind_from_constructor(&constructor_error)
			return {}, value_add_error_from_constructor(kind, &constructor_error)
		}
		return result, nil
	case .Array:
		result, result_error := value_add_allocate_array(storage.array_length, allocator)
		if value_add_error_kind(&result_error) != .None do return {}, result_error
		// The handle may be moved into its parent before this frame completes, so
		// record its final logical length now. Partial teardown is independently
		// bounded by array_initialized_length as children become owned.
		value_storage_of(&result).array_length = storage.array_length
		frame, frame_error := value_add_allocate_frame(
			.Array,
			storage,
			storage.owned_payload,
			value_storage_of(&result).owned_payload,
			allocator,
		)
		if value_add_error_kind(&frame_error) != .None {
			value_add_cleanup_partial(&result, &frame_error)
			return {}, frame_error
		}
		frame.next = head^
		head^ = frame
		return result, nil
	case .Object:
		capacity, capacity_ok := value_add_object_capacity(storage.owned_payload.object_length)
		if !capacity_ok do return {}, make_value_add_error(.Size_Overflow)
		p, object_error := allocate_object_payload(capacity, allocator)
		if object_error_kind(&object_error) != .None {
			return {}, value_add_error_from_object(&object_error)
		}
		result := value_from_payload(.Object, p)
		frame, frame_error := value_add_allocate_frame(
			.Object,
			storage,
			storage.owned_payload,
			p,
			allocator,
		)
		if value_add_error_kind(&frame_error) != .None {
			value_add_cleanup_partial(&result, &frame_error)
			return {}, frame_error
		}
		frame.next = head^
		head^ = frame
		return result, nil
	case .Invalid:
	}
	return {}, make_value_add_error(.Invalid_Operand)
}

@(private)
value_add_clone :: proc(source: ^Value, allocator: runtime.Allocator) -> (
	Value,
	Value_Add_Error,
) {
	head: ^value_add_clone_frame
	result, err := value_add_clone_start(source, allocator, &head)
	if value_add_error_kind(&err) != .None do return {}, err
	for head != nil {
		frame := head
		if frame.kind == .Array {
			source_storage := frame.source_storage
			if frame.at < source_storage.array_length {
				source_values := array_payload_values(frame.source_payload)
				destination_values := array_payload_values(frame.destination_payload)
				child, child_error := value_add_clone_start(
					&source_values[int(source_storage.array_offset) + frame.at],
					allocator,
					&head,
				)
				if value_add_error_kind(&child_error) != .None {
					value_add_absorb_cleanup(&destination_values[frame.at], &child_error)
					if kind_of(&destination_values[frame.at]) != .Invalid {
						frame.destination_payload.array_initialized_length = frame.at + 1
					}
					(&child_error.(value_add_error_storage)).cleanup_work = head
					head = nil
					value_add_cleanup_partial(&result, &child_error)
					return {}, child_error
				}
				destination_values[frame.at] = take_value(&child)
				frame.at += 1
				frame.destination_payload.array_initialized_length = frame.at
				continue
			}
		} else {
			source_slots := object_payload_slots(frame.source_payload)
			for frame.at < frame.source_payload.object_next_free &&
			      kind_of(&source_slots[frame.at].key) != .String {
				frame.at += 1
			}
			if frame.at < frame.source_payload.object_next_free {
				source_slot := &source_slots[frame.at]
				destination := &object_payload_slots(frame.destination_payload)[
					frame.destination_payload.object_next_free
				]
				key, key_error := value_add_clone_start(&source_slot.key, allocator, &head)
				if value_add_error_kind(&key_error) != .None {
					value_add_absorb_cleanup(&destination.key, &key_error)
					(&key_error.(value_add_error_storage)).cleanup_work = head
					head = nil
					value_add_cleanup_partial(&result, &key_error)
					return {}, key_error
				}
				destination.key = take_value(&key)
				key_text, _ := string_borrowed(&destination.key)
				destination.hash = object_hash(key_text)
				buckets := object_payload_buckets(frame.destination_payload)
				bucket := int(destination.hash & u32(len(buckets) - 1))
				destination.next = buckets[bucket]
				buckets[bucket] = frame.destination_payload.object_next_free
				frame.destination_payload.object_next_free += 1
				frame.destination_payload.object_length += 1
				frame.at += 1
				child, child_error := value_add_clone_start(&source_slot.value, allocator, &head)
				if value_add_error_kind(&child_error) != .None {
					value_add_absorb_cleanup(&destination.value, &child_error)
					(&child_error.(value_add_error_storage)).cleanup_work = head
					head = nil
					value_add_cleanup_partial(&result, &child_error)
					return {}, child_error
				}
				destination.value = take_value(&child)
				continue
			}
		}

		next := frame.next
		free_error := runtime.mem_free_with_size(
			frame,
			int(size_of(value_add_clone_frame)),
			frame.allocator,
		)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			err = make_value_add_error(.Cleanup_Failed)
			(&err.(value_add_error_storage)).cleanup_work = head
			head = nil
			value_add_cleanup_partial(&result, &err)
			return {}, err
		}
		head = next
	}
	return result, nil
}

@(private)
value_add_build_array :: proc(
	left, right: ^Value,
	allocator: runtime.Allocator,
) -> (Value, Value_Add_Error) {
	left_storage, _, left_ok := array_storage_of(left)
	if !left_ok do return {}, make_value_add_error(.Invalid_Operand)
	right_length := 0
	if right != nil {
		right_storage, _, right_ok := array_storage_of(right)
		if !right_ok do return {}, make_value_add_error(.Invalid_Operand)
		right_length = right_storage.array_length
	}
	if left_storage.array_length > max(int) - right_length {
		return {}, make_value_add_error(.Size_Overflow)
	}
	total := left_storage.array_length + right_length
	result, result_error := value_add_allocate_array(total, allocator)
	if value_add_error_kind(&result_error) != .None do return {}, result_error
	p := value_storage_of(&result).owned_payload
	destination := array_payload_values(p)
	inputs := [2]^Value{left, right}
	at := 0
	for input in inputs {
		if input == nil do continue
		input_storage, input_payload, input_ok := array_storage_of(input)
		if !input_ok {
			err := make_value_add_error(.Invalid_Operand)
			value_add_cleanup_partial(&result, &err)
			return {}, err
		}
		source_values := array_payload_values(input_payload)
		for i in 0..<input_storage.array_length {
			child, child_error := value_add_clone(
				&source_values[int(input_storage.array_offset) + i],
				allocator,
			)
			if value_add_error_kind(&child_error) != .None {
				value_add_absorb_cleanup(&destination[at], &child_error)
				if kind_of(&destination[at]) != .Invalid {
					p.array_initialized_length = at + 1
					value_storage_of(&result).array_length = at + 1
				}
				value_add_cleanup_partial(&result, &child_error)
				return {}, child_error
			}
			destination[at] = take_value(&child)
			at += 1
			p.array_initialized_length = at
			value_storage_of(&result).array_length = at
		}
	}
	assert(at == total)
	return result, nil
}

@(private)
value_add_object_capacity :: proc(length: int) -> (int, bool) {
	if length < 0 do return 0, false
	capacity := OBJECT_INITIAL_CAPACITY
	for capacity < length {
		if capacity > max(int) / 2 do return 0, false
		capacity *= 2
	}
	// Object bucket selection uses a u32 hash mask over twice the slot
	// capacity, so the complete bucket count must remain representable in u32.
	if capacity > int(max(u32)) / 2 + 1 do return 0, false
	_, ok := object_allocation_size(capacity)
	return capacity, ok
}

@(private)
value_add_object_unique_count :: proc(left, right: ^payload) -> (int, bool) {
	count := left.object_length
	if right == nil do return count, true
	for i in 0..<right.object_next_free {
		slot := &object_payload_slots(right)[i]
		key, key_ok := string_borrowed(&slot.key)
		if !key_ok do continue
		_, found := object_find_slot(left, key)
		if !found {
			if count == max(int) do return 0, false
			count += 1
		}
	}
	return count, true
}

@(private)
value_add_object_insert_clone :: proc(
	result: ^Value,
	source_key, source_value: ^Value,
	allocator: runtime.Allocator,
) -> Value_Add_Error {
	p, ok := object_storage_of(result)
	if !ok do return make_value_add_error(.Invalid_Operand)
	key_text, key_ok := string_borrowed(source_key)
	if !key_ok do return make_value_add_error(.Invalid_Operand)
	_, found := object_find_slot(p, key_text)
	if found do return make_value_add_error(.Invalid_Operand)
	index := p.object_next_free
	if index >= p.object_capacity do return make_value_add_error(.Size_Overflow)
	p.object_next_free += 1
	destination := &object_payload_slots(p)[index]
	key, key_error := value_add_clone(source_key, allocator)
	if value_add_error_kind(&key_error) != .None {
		value_add_absorb_cleanup(&destination.key, &key_error)
		return key_error
	}
	destination.key = take_value(&key)
	destination.hash = object_hash(key_text)
	buckets := object_payload_buckets(p)
	bucket := int(destination.hash & u32(len(buckets) - 1))
	destination.next = buckets[bucket]
	buckets[bucket] = index
	p.object_length += 1
	cloned_value, value_error := value_add_clone(source_value, allocator)
	if value_add_error_kind(&value_error) != .None {
		value_add_absorb_cleanup(&destination.value, &value_error)
		return value_error
	}
	destination.value = take_value(&cloned_value)
	return nil
}

@(private)
value_add_build_object :: proc(
	left, right: ^Value,
	allocator: runtime.Allocator,
) -> (Value, Value_Add_Error) {
	left_payload, left_ok := object_storage_of(left)
	if !left_ok do return {}, make_value_add_error(.Invalid_Operand)
	right_payload: ^payload
	if right != nil {
		right_ok: bool
		right_payload, right_ok = object_storage_of(right)
		if !right_ok do return {}, make_value_add_error(.Invalid_Operand)
	}
	unique_count, count_ok := value_add_object_unique_count(left_payload, right_payload)
	if !count_ok do return {}, make_value_add_error(.Size_Overflow)
	capacity, capacity_ok := value_add_object_capacity(unique_count)
	if !capacity_ok do return {}, make_value_add_error(.Size_Overflow)
	p, object_error := allocate_object_payload(capacity, allocator)
	if object_error_kind(&object_error) != .None {
		return {}, value_add_error_from_object(&object_error)
	}
	result := value_from_payload(.Object, p)
	for i in 0..<left_payload.object_next_free {
		slot := &object_payload_slots(left_payload)[i]
		if kind_of(&slot.key) != .String do continue
		selected_value := &slot.value
		if right_payload != nil {
			key_text, _ := string_borrowed(&slot.key)
			right_index, found := object_find_slot(right_payload, key_text)
			if found do selected_value = &object_payload_slots(right_payload)[right_index].value
		}
		err := value_add_object_insert_clone(
			&result,
			&slot.key,
			selected_value,
			allocator,
		)
		if value_add_error_kind(&err) != .None {
			value_add_cleanup_partial(&result, &err)
			return {}, err
		}
	}
	if right_payload != nil {
		for i in 0..<right_payload.object_next_free {
			slot := &object_payload_slots(right_payload)[i]
			if kind_of(&slot.key) != .String do continue
			key_text, _ := string_borrowed(&slot.key)
			_, found := object_find_slot(p, key_text)
			if found do continue
			err := value_add_object_insert_clone(
				&result,
				&slot.key,
				&slot.value,
				allocator,
			)
			if value_add_error_kind(&err) != .None {
				value_add_cleanup_partial(&result, &err)
				return {}, err
			}
		}
	}
	return result, nil
}

@(private)
value_add_strings :: proc(
	left, right: ^Value,
	allocator: runtime.Allocator,
) -> (Value, Value_Add_Error) {
	left_bytes, left_ok := string_borrowed(left)
	right_bytes, right_ok := string_borrowed(right)
	if !left_ok || !right_ok do return {}, make_value_add_error(.Invalid_Operand)
	if len(left_bytes) > max(int) - len(right_bytes) {
		return {}, make_value_add_error(.Size_Overflow)
	}
	total := len(left_bytes) + len(right_bytes)
	p, constructor_error := allocate_payload(.String, total, 0, allocator)
	if constructor_error_kind(&constructor_error) != .None {
		kind := value_add_kind_from_constructor(&constructor_error)
		return {}, value_add_error_from_constructor(kind, &constructor_error)
	}
	copy(payload_bytes(p), transmute([]byte)left_bytes)
	copy(payload_bytes(p)[len(left_bytes):], transmute([]byte)right_bytes)
	return value_from_payload(.String, p), nil
}

@(private)
VALUE_ADD_VALIDATION_BLOCK_CAPACITY :: 64

@(private)
value_add_validation_seen_state :: enum u8 {
	Visiting,
	Complete,
}

@(private)
value_add_validation_seen :: struct {
	payload:          ^payload,
	state:            value_add_validation_seen_state,
	reachable_owners: int,
}

@(private)
value_add_validation_frame :: struct {
	value:       ^Value,
	seen:        ^value_add_validation_seen,
	at:          int,
	object_value: bool,
}

@(private)
value_add_validation_block :: struct {
	previous:        ^value_add_validation_block,
	allocator:       runtime.Allocator,
	allocation_size: int,
	frame_count:     int,
	seen_count:      int,
	frames:          [VALUE_ADD_VALIDATION_BLOCK_CAPACITY]value_add_validation_frame,
	seen:            [VALUE_ADD_VALIDATION_BLOCK_CAPACITY]value_add_validation_seen,
}

@(private)
value_add_validation_work :: struct {
	blocks: ^value_add_validation_block,
}

@(private)
value_add_destroy_validation_work :: proc(
	head: ^^value_add_validation_block,
) -> runtime.Allocator_Error {
	if head == nil do return nil
	for head^ != nil {
		block := head^
		previous := block.previous
		free_error := runtime.mem_free_with_size(
			block,
			block.allocation_size,
			block.allocator,
		)
		if free_error != nil && free_error != .Mode_Not_Implemented do return free_error
		head^ = previous
	}
	return nil
}

@(private)
value_add_validation_error :: proc(
	kind: Value_Add_Error_Kind,
	work: ^value_add_validation_work,
) -> Value_Add_Error {
	err := make_value_add_error(kind)
	cleanup_error := value_add_destroy_validation_work(&work.blocks)
	if cleanup_error != nil {
		err = make_value_add_error(.Cleanup_Failed)
		storage := &err.(value_add_error_storage)
		storage.cause = kind
		storage.validation_work = work.blocks
		work.blocks = nil
	}
	return err
}

@(private)
value_add_validation_allocate_block :: proc(
	work: ^value_add_validation_work,
	allocator: runtime.Allocator,
) -> Value_Add_Error {
	size := int(size_of(value_add_validation_block))
	memory, allocation_error := runtime.mem_alloc(
		size,
		align_of(value_add_validation_block),
		allocator,
	)
	if allocation_error != nil || len(memory) != size {
		kind := Value_Add_Error_Kind.Out_Of_Memory
		if allocation_error == .Mode_Not_Implemented do kind = .Allocator_Unsupported
		constructor_error: Constructor_Error
		if len(memory) > 0 {
			free_error := runtime.mem_free_bytes(memory, allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				constructor_error = make_cleanup_constructor_error(
					.Out_Of_Memory,
					memory,
					allocator,
				)
			}
		}
		err := value_add_validation_error(kind, work)
		if constructor_error_needs_cleanup(&constructor_error) {
			if value_add_error_kind(&err) != .Cleanup_Failed {
				err = make_value_add_error(.Cleanup_Failed)
				(&err.(value_add_error_storage)).cause = kind
			}
			(&err.(value_add_error_storage)).constructor_error =
				take_constructor_error(&constructor_error)
		}
		return err
	}
	block := cast(^value_add_validation_block)(raw_data(memory))
	block^ = {
		previous = work.blocks,
		allocator = allocator,
		allocation_size = size,
	}
	work.blocks = block
	return {}
}

@(private)
value_add_validation_push :: proc(
	work: ^value_add_validation_work,
	value: ^Value,
	allocator: runtime.Allocator,
) -> Value_Add_Error {
	block := work.blocks
	if block == nil || block.frame_count == VALUE_ADD_VALIDATION_BLOCK_CAPACITY {
		err := value_add_validation_allocate_block(work, allocator)
		if value_add_error_kind(&err) != .None do return err
		block = work.blocks
	}
	block.frames[block.frame_count] = {value = value}
	block.frame_count += 1
	return {}
}

@(private)
value_add_validation_top :: proc(
	work: ^value_add_validation_work,
) -> ^value_add_validation_frame {
	for block := work.blocks; block != nil; block = block.previous {
		if block.frame_count > 0 do return &block.frames[block.frame_count - 1]
	}
	return nil
}

@(private)
value_add_validation_pop :: proc(work: ^value_add_validation_work) {
	for block := work.blocks; block != nil; block = block.previous {
		if block.frame_count > 0 {
			block.frame_count -= 1
			return
		}
	}
}

@(private)
value_add_validation_find_seen :: proc(
	work: ^value_add_validation_work,
	p: ^payload,
) -> ^value_add_validation_seen {
	for block := work.blocks; block != nil; block = block.previous {
		for i in 0..<block.seen_count {
			if block.seen[i].payload == p do return &block.seen[i]
		}
	}
	return nil
}

@(private)
value_add_validation_add_seen :: proc(
	work: ^value_add_validation_work,
	p: ^payload,
	allocator: runtime.Allocator,
) -> (^value_add_validation_seen, Value_Add_Error) {
	block := work.blocks
	if block == nil || block.seen_count == VALUE_ADD_VALIDATION_BLOCK_CAPACITY {
		err := value_add_validation_allocate_block(work, allocator)
		if value_add_error_kind(&err) != .None do return nil, err
		block = work.blocks
	}
	entry := &block.seen[block.seen_count]
	entry^ = {payload = p, state = .Visiting, reachable_owners = 1}
	block.seen_count += 1
	return entry, {}
}

@(private)
value_add_operand_local_valid :: proc(value: ^Value) -> bool {
	if value == nil || value^ == nil || value_is_retiring(value) do return false
	storage := value_storage_of(value)
	switch storage.kind {
	case .Null, .Boolean:
		return storage.owned_payload == nil && storage.payload_allocation_bound == 0
	case .Number:
		p := storage.owned_payload
		if p == nil do return storage.payload_allocation_bound == 0
		return p.references != max(int) && literal_storage_valid(storage)
	case .String:
		p := storage.owned_payload
		return p != nil && p.references != max(int) && string_storage_valid(storage)
	case .Array:
		p := storage.owned_payload
		if p == nil || p.kind != .Array || p.references <= 0 || p.references == max(int) ||
		   p.array_retiring || p.array_capacity < 0 ||
		   p.array_initialized_length < 0 ||
		   p.array_initialized_length > p.array_capacity || p.array_retired_count < 0 ||
		   storage.array_length < 0 {
			return false
		}
		offset := int(storage.array_offset)
		if offset > p.array_initialized_length ||
		   storage.array_length > p.array_initialized_length - offset ||
		   p.array_capacity > max(int) - p.array_retired_count {
			return false
		}
		total_owned := p.array_initialized_length + p.array_retired_count
		size, size_ok := array_allocation_size(p.array_capacity + p.array_retired_count)
		if !size_ok || !payload_bound_matches(storage, size) do return false
		values := array_payload_values(p)
		for i in 0..<total_owned {
			index := i
			if i >= p.array_initialized_length {
				index = p.array_capacity + i - p.array_initialized_length
			}
			if kind_of(&values[index]) == .Invalid || value_is_retiring(&values[index]) do return false
		}
		return true
	case .Object:
		p := storage.owned_payload
		if p == nil || p.kind != .Object || p.references <= 0 || p.references == max(int) ||
		   p.object_retiring || p.object_capacity < OBJECT_INITIAL_CAPACITY ||
		   p.object_capacity & (p.object_capacity - 1) != 0 ||
		   p.object_capacity > int(max(u32)) / 2 + 1 || p.object_next_free < 0 ||
		   p.object_next_free > p.object_capacity || p.object_length < 0 ||
		   p.object_length > p.object_next_free {
			return false
		}
		size, size_ok := object_allocation_size(p.object_capacity)
		if !size_ok || !payload_bound_matches(storage, size) do return false
		live := 0
		for i in 0..<p.object_capacity {
			slot := &object_payload_slots(p)[i]
			if slot.key == nil {
				if !object_slot_is_canonical_empty(slot) do return false
				continue
			}
			if i >= p.object_next_free do return false
			if kind_of(&slot.key) != .String || !value_add_operand_local_valid(&slot.key) ||
			   kind_of(&slot.value) == .Invalid || value_is_retiring(&slot.value) {
				return false
			}
			key_text, key_ok := string_borrowed(&slot.key)
			if !key_ok || slot.hash != object_hash(key_text) do return false
			live += 1
		}
		if live != p.object_length do return false
		// Equal text denotes one jq object member even when separately owned keys
		// have otherwise consistent hashes and links.
		slots := object_payload_slots(p)
		for i in 0..<p.object_next_free {
			if kind_of(&slots[i].key) != .String do continue
			left_text, left_ok := string_borrowed(&slots[i].key)
			if !left_ok do return false
			for j in i + 1..<p.object_next_free {
				if kind_of(&slots[j].key) != .String do continue
				right_text, right_ok := string_borrowed(&slots[j].key)
				if !right_ok || left_text == right_text do return false
			}
		}
		visited := 0
		buckets := object_payload_buckets(p)
		for head, bucket_index in buckets {
			if head < -1 || head >= p.object_next_free do return false
			index := head
			steps := 0
			for index >= 0 {
				if steps >= p.object_next_free do return false
				slot := &slots[index]
				if kind_of(&slot.key) != .String ||
				   int(slot.hash & u32(len(buckets) - 1)) != bucket_index ||
				   slot.next < -1 || slot.next >= p.object_next_free {
					return false
				}
				visited += 1
				steps += 1
				index = slot.next
			}
		}
		return visited == live
	case .Invalid:
		return false
	}
	return false
}

@(private)
value_add_validate_one :: proc(
	root: ^Value,
	work: ^value_add_validation_work,
	allocator: runtime.Allocator,
) -> Value_Add_Error {
	if !value_add_operand_local_valid(root) {
		return value_add_validation_error(.Invalid_Operand, work)
	}
	// Inline values own no payload. Every payload-bearing root must enter the
	// joint seen table, including strings and allocated number literals.
	if value_storage_of(root).owned_payload == nil do return {}
	push_error := value_add_validation_push(work, root, allocator)
	if value_add_error_kind(&push_error) != .None do return push_error

	for {
		frame := value_add_validation_top(work)
		if frame == nil do return {}
		storage := value_storage_of(frame.value)
		p := storage.owned_payload
		if frame.seen == nil {
			if !value_add_operand_local_valid(frame.value) {
				return value_add_validation_error(.Invalid_Operand, work)
			}
			if p == nil {
				value_add_validation_pop(work)
				continue
			}
			seen := value_add_validation_find_seen(work, p)
			if seen != nil {
				if seen.state == .Visiting {
					return value_add_validation_error(.Invalid_Operand, work)
				}
				if seen.reachable_owners == max(int) {
					return value_add_validation_error(.Invalid_Operand, work)
				}
				seen.reachable_owners += 1
				if seen.reachable_owners > p.references {
					return value_add_validation_error(.Invalid_Operand, work)
				}
				value_add_validation_pop(work)
				continue
			}
			seen_error: Value_Add_Error
			seen, seen_error = value_add_validation_add_seen(work, p, allocator)
			if value_add_error_kind(&seen_error) != .None do return seen_error
			frame.seen = seen
			kind := kind_of(frame.value)
			if kind != .Array && kind != .Object {
				seen.state = .Complete
				value_add_validation_pop(work)
				continue
			}
		}

		if storage.kind == .Array {
			total_owned := p.array_initialized_length + p.array_retired_count
			if frame.at < total_owned {
				index := frame.at
				if index >= p.array_initialized_length {
					index = p.array_capacity + index - p.array_initialized_length
				}
				frame.at += 1
				child_error := value_add_validation_push(
					work,
					&array_payload_values(p)[index],
					allocator,
				)
				if value_add_error_kind(&child_error) != .None do return child_error
				continue
			}
		} else {
			slots := object_payload_slots(p)
			for frame.at < p.object_next_free && kind_of(&slots[frame.at].key) != .String {
				frame.at += 1
			}
			if frame.at < p.object_next_free {
				child := &slots[frame.at].key
				if frame.object_value {
					child = &slots[frame.at].value
					frame.object_value = false
					frame.at += 1
				} else {
					frame.object_value = true
				}
				child_error := value_add_validation_push(work, child, allocator)
				if value_add_error_kind(&child_error) != .None do return child_error
				continue
			}
		}
		frame.seen.state = .Complete
		value_add_validation_pop(work)
	}
}

@(private)
value_add_validate_operands_with_allocator :: proc(
	left, right: ^Value,
	allocator: runtime.Allocator,
) -> Value_Add_Error {
	work: value_add_validation_work
	left_error := value_add_validate_one(left, &work, allocator)
	if value_add_error_kind(&left_error) != .None do return left_error
	// Passing the exact same borrowed storage twice does not create a second
	// owning handle. Distinct Value variables retain the joint seen/multiplicity
	// state, even when ordinary shallow assignment made their payload equal.
	if left == right do return value_add_validation_error(.None, &work)
	right_error := value_add_validate_one(right, &work, allocator)
	if value_add_error_kind(&right_error) != .None do return right_error
	return value_add_validation_error(.None, &work)
}

// value_add implements jq 1.8.1's low-level polymorphic addition while
// borrowing both operands. Success always returns an independently owned deep
// result allocated through allocator where storage is needed. Accepted pairs
// are null identity, number+number, string+string, array+array, and
// object+object; every other live pair is Invalid_Type_Pair.
value_add :: proc(
	left, right: ^Value,
	allocator: runtime.Allocator,
) -> (Value, Value_Add_Error) {
	validation_error := value_add_validate_operands_with_allocator(
		left,
		right,
		runtime.heap_allocator(),
	)
	if value_add_error_kind(&validation_error) != .None do return {}, validation_error
	left_kind := kind_of(left)
	right_kind := kind_of(right)
	if left_kind == .Null do return value_add_clone(right, allocator)
	if right_kind == .Null do return value_add_clone(left, allocator)
	if left_kind != right_kind {
		return {}, make_value_add_error(.Invalid_Type_Pair)
	}
	switch left_kind {
	case .Number:
		result, ok := number_add(left, right)
		if !ok do return {}, make_value_add_error(.Invalid_Operand)
		return result, nil
	case .String:
		return value_add_strings(left, right, allocator)
	case .Array:
		return value_add_build_array(left, right, allocator)
	case .Object:
		return value_add_build_object(left, right, allocator)
	case .Invalid:
		return {}, make_value_add_error(.Invalid_Operand)
	case .Null, .Boolean:
		return {}, make_value_add_error(.Invalid_Type_Pair)
	}
	return {}, make_value_add_error(.Invalid_Operand)
}
