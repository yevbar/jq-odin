package value

import "base:runtime"

// Array_Error distinguishes API misuse and representational overflow from
// allocation failure.
Array_Error :: enum u8 {
	None,
	Out_Of_Memory,
	Wrong_Kind,
	Invalid_Index,
	Index_Too_Large,
	Size_Overflow,
	Aliased_Operand,
	Allocator_Unsupported,
	Cleanup_Failed,
}

@(private)
array_operation_error_storage :: struct {
	kind:              Array_Error,
	constructor_error: Constructor_Error,
}

// Array_Operation_Error is inert for ordinary failures. If exact allocation
// validation receives a nonempty mismatched allocation whose Free fails, it
// owns the existing opaque Constructor_Error cleanup handle until retirement
// succeeds. It must not be copied.
Array_Operation_Error :: union {
	array_operation_error_storage,
}

@(private)
make_array_operation_error :: proc(kind: Array_Error) -> Array_Operation_Error {
	if kind == .None {
		return {}
	}
	return array_operation_error_storage{kind = kind}
}

@(private)
make_array_cleanup_error :: proc(
	kind: Array_Error,
	cleanup: ^Constructor_Error,
) -> Array_Operation_Error {
	return array_operation_error_storage{
		kind = kind,
		constructor_error = take_constructor_error(cleanup),
	}
}

array_error_kind :: proc(err: ^Array_Operation_Error) -> Array_Error {
	if err == nil || err^ == nil {
		return .None
	}
	return err.(array_operation_error_storage).kind
}

array_error_needs_cleanup :: proc(err: ^Array_Operation_Error) -> bool {
	if err == nil || err^ == nil {
		return false
	}
	storage := &err.(array_operation_error_storage)
	return constructor_error_needs_cleanup(&storage.constructor_error)
}

take_array_error :: proc(source: ^Array_Operation_Error) -> Array_Operation_Error {
	if source == nil {
		return {}
	}
	result := source^
	source^ = {}
	return result
}

// destroy_array_error retires any partial allocation through the owning
// Constructor_Error contract. Genuine Free failures preserve this handle for
// retry; Mode_Not_Implemented retires it under the allocator's bulk lifetime.
destroy_array_error :: proc(err: ^Array_Operation_Error) -> runtime.Allocator_Error {
	if err == nil || err^ == nil {
		return nil
	}
	storage := &err.(array_operation_error_storage)
	cleanup_error := destroy_constructor_error(&storage.constructor_error)
	if cleanup_error != nil {
		return cleanup_error
	}
	err^ = {}
	return nil
}

@(private)
retire_array_temporary :: proc(
	kind: Array_Error,
	memory: []byte,
	allocator: runtime.Allocator,
) -> Array_Operation_Error {
	if len(memory) > 0 {
		free_error := runtime.mem_free_bytes(memory, allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			cleanup := make_cleanup_constructor_error(.Out_Of_Memory, memory, allocator)
			return make_array_cleanup_error(kind, &cleanup)
		}
	}
	return make_array_operation_error(kind)
}

@(private)
ARRAY_INITIAL_CAPACITY :: 16

#assert(size_of(payload) % align_of(Value) == 0)
#assert(align_of(payload) >= align_of(Value))

@(private)
array_payload_values :: proc(p: ^payload) -> []Value {
	if p == nil || p.array_capacity + p.array_retired_count == 0 {
		return nil
	}
	data := cast([^]Value)(uintptr(p) + size_of(payload))
	return data[:p.array_capacity + p.array_retired_count]
}

@(private)
array_allocation_size :: proc(capacity: int) -> (size: int, ok: bool) {
	if capacity < 0 || capacity > (max(int) - int(size_of(payload))) / int(size_of(Value)) {
		return 0, false
	}
	return int(size_of(payload)) + capacity * int(size_of(Value)), true
}

@(private)
allocate_array_payload :: proc(
	capacity: int,
	allocator: runtime.Allocator,
	retired_count: int = 0,
) -> (p: ^payload, err: Array_Operation_Error) {
	if retired_count < 0 || capacity > max(int) - retired_count {
		return nil, make_array_operation_error(.Size_Overflow)
	}
	allocation_size, size_ok := array_allocation_size(capacity + retired_count)
	if !size_ok {
		return nil, make_array_operation_error(.Size_Overflow)
	}
	memory, alloc_error := runtime.mem_alloc(
		allocation_size,
		align_of(payload),
		allocator,
	)
	if alloc_error != nil || len(memory) != allocation_size {
		kind := Array_Error.Out_Of_Memory
		if alloc_error == .Mode_Not_Implemented {
			kind = .Allocator_Unsupported
		}
		return nil, retire_array_temporary(kind, memory, allocator)
	}
	p = cast(^payload)(raw_data(memory))
	p.references = 1
	p.allocator = allocator
	p.allocation_size = allocation_size
	p.kind = .Array
	p.array_capacity = capacity
	p.array_retired_count = retired_count
	return p, nil
}

// array_value constructs an empty owning array using allocator. Even an empty
// array has an allocated identity, matching clone/COW and allocator provenance
// rules. Failure returns an inert Value.
array_value :: proc(allocator: runtime.Allocator) -> (result: Value, err: Array_Operation_Error) {
	p, alloc_error := allocate_array_payload(ARRAY_INITIAL_CAPACITY, allocator)
	if array_error_kind(&alloc_error) != .None {
		return {}, alloc_error
	}
	return value_from_storage({kind = .Array, owned_payload = p}), nil
}

@(private)
array_storage_of :: proc(value: ^Value) -> (^value_storage, ^payload, bool) {
	if value == nil || value^ == nil {
		return nil, nil, false
	}
	storage := value_storage_of(value)
	if storage.kind != .Array || storage.owned_payload == nil ||
	   storage.owned_payload.kind != .Array || storage.owned_payload.array_retiring {
		return nil, nil, false
	}
	return storage, storage.owned_payload, true
}

array_length :: proc(value: ^Value) -> (length: int, ok: bool) {
	storage, _, array_ok := array_storage_of(value)
	if !array_ok {
		return 0, false
	}
	return storage.array_length, true
}

// Raw slots never cross the package boundary. Even package-internal callers
// must not retain one across a mutation, take, or destruction.
@(private)
array_element_slot :: proc(value: ^Value, index: int) -> (element: ^Value, ok: bool) {
	storage, p, array_ok := array_storage_of(value)
	if !array_ok || index < 0 || index >= storage.array_length {
		return nil, false
	}
	elements := array_payload_values(p)
	return &elements[int(storage.array_offset) + index], true
}

// array_element_copy borrows the array and returns an independently owned
// element handle. The caller must transfer or destroy a successful result.
array_element_copy :: proc(value: ^Value, index: int) -> (element: Value, ok: bool) {
	slot, slot_ok := array_element_slot(value, index)
	if !slot_ok {
		return {}, false
	}
	return clone_value(slot), true
}

@(private)
array_growth_capacity :: proc(required: int) -> (capacity: int, ok: bool) {
	if required < 0 {
		return 0, false
	}
	capacity = required
	if required <= max(int) - required / 2 {
		capacity = required + required / 2
	} else {
		return 0, false
	}
	_, ok = array_allocation_size(capacity)
	return
}

@(private)
array_grow_unique :: proc(
	storage: ^value_storage,
	p: ^payload,
	required: int,
) -> (^payload, Array_Operation_Error) {
	capacity, capacity_ok := array_growth_capacity(required)
	if !capacity_ok {
		return nil, make_array_operation_error(.Size_Overflow)
	}
	offset := int(storage.array_offset)
	hidden_count := p.array_initialized_length - storage.array_length
	if hidden_count < 0 || p.array_retired_count > max(int) - hidden_count {
		return nil, make_array_operation_error(.Size_Overflow)
	}
	retired_count := p.array_retired_count + hidden_count
	if capacity > max(int) - retired_count {
		return nil, make_array_operation_error(.Size_Overflow)
	}
	allocator := p.allocator
	old_size := p.allocation_size
	replacement, allocation_error := allocate_array_payload(capacity, allocator, retired_count)
	if array_error_kind(&allocation_error) != .None {
		return nil, allocation_error
	}
	// Raw-transfer every owner so the old allocation can be retired without a
	// fallible recursive release. Only the visible values remain addressable;
	// source-only and previously retired owners move to the private tail.
	source := array_payload_values(p)
	destination := array_payload_values(replacement)
	for i in 0..<storage.array_length {
		destination[i] = source[offset + i]
	}
	retired_at := capacity
	for i in 0..<offset {
		destination[retired_at] = source[i]
		retired_at += 1
	}
	for i in offset + storage.array_length..<p.array_initialized_length {
		destination[retired_at] = source[i]
		retired_at += 1
	}
	for i in 0..<p.array_retired_count {
		destination[retired_at] = source[p.array_capacity + i]
		retired_at += 1
	}
	assert(retired_at == capacity + retired_count)
	for i in storage.array_length..<required {
		destination[i] = null_value()
	}
	replacement.array_initialized_length = required
	old_memory := ([^]byte)(rawptr(p))[:old_size]
	old_free_error := runtime.mem_free_bytes(old_memory, allocator)
	if old_free_error != nil && old_free_error != .Mode_Not_Implemented {
		replacement_memory := ([^]byte)(rawptr(replacement))[:replacement.allocation_size]
		return nil, retire_array_temporary(.Cleanup_Failed, replacement_memory, allocator)
	}
	storage.owned_payload = replacement
	storage.array_offset = 0
	return replacement, nil
}

@(private)
array_copy_for_write :: proc(
	storage: ^value_storage,
	p: ^payload,
	required: int,
) -> (^payload, Array_Operation_Error) {
	capacity, capacity_ok := array_growth_capacity(required)
	if !capacity_ok {
		return nil, make_array_operation_error(.Size_Overflow)
	}
	copy_payload, alloc_error := allocate_array_payload(capacity, p.allocator)
	if array_error_kind(&alloc_error) != .None {
		return nil, alloc_error
	}
	copy_payload.array_initialized_length = required
	source := array_payload_values(p)
	destination := array_payload_values(copy_payload)
	offset := int(storage.array_offset)
	for i in 0..<storage.array_length {
		destination[i] = clone_value(&source[offset + i])
	}
	for i in storage.array_length..<required {
		destination[i] = null_value()
	}
	return copy_payload, nil
}

@(private)
array_make_writable :: proc(array: ^Value, required: int) -> (^payload, Array_Operation_Error) {
	storage, p, array_ok := array_storage_of(array)
	if !array_ok {
		return nil, make_array_operation_error(.Wrong_Kind)
	}
	if int(storage.array_offset) + required <= p.array_capacity && p.references == 1 {
		return p, nil
	}
	if p.references == 1 {
		grown, growth_error := array_grow_unique(storage, p, required)
		if array_error_kind(&growth_error) != .None {
			return nil, growth_error
		}
		return grown, nil
	}
	copy_payload, copy_error := array_copy_for_write(storage, p, required)
	if array_error_kind(&copy_error) != .None {
		return nil, copy_error
	}
	p.references -= 1
	storage.owned_payload = copy_payload
	storage.array_offset = 0
	return copy_payload, nil
}

@(private)
array_normalize_set_index :: proc(length, index: int) -> (int, bool) {
	result := index
	if result < 0 {
		if result < -length {
			return 0, false
		}
		result += length
	}
	return result, result >= 0
}

@(private)
JQ_ARRAY_INDEX_MAX :: int(max(i32) >> 2)

// array_set_take mutates array with jq-style logical value semantics. On
// success it takes element (leaving element invalid), fills any gap with null,
// and returns ownership of the displaced slot (or invalid when no slot was
// displaced). The caller must destroy or transfer that returned Value exactly
// once. This keeps fallible destruction outside the mutation transaction. On
// every failure, displaced is invalid and both operands remain owned and
// logically unchanged. A shared array always detaches before write; unique
// storage is reused when capacity permits.
array_set_take :: proc(
	array: ^Value,
	index: int,
	element: ^Value,
) -> (displaced: Value, err: Array_Operation_Error) {
	if element == nil || element^ == nil {
		return {}, make_array_operation_error(.Wrong_Kind)
	}
	element_storage := value_storage_of(element)
	if element_storage.owned_payload != nil &&
	   element_storage.owned_payload.kind == .Array &&
	   element_storage.owned_payload.array_retiring {
		return {}, make_array_operation_error(.Wrong_Kind)
	}
	array_storage, p, array_ok := array_storage_of(array)
	if !array_ok {
		return {}, make_array_operation_error(.Wrong_Kind)
	}
	// Taking the handle being mutated cannot have move semantics. Package-private
	// raw slots are rejected defensively; public callers can only obtain copies.
	if element == array {
		return {}, make_array_operation_error(.Aliased_Operand)
	}
	storage := array_payload_values(p)
	if len(storage) > 0 {
		first := uintptr(&storage[0])
		limit := first + uintptr(len(storage) * int(size_of(Value)))
		address := uintptr(element)
		if address >= first && address < limit {
			return {}, make_array_operation_error(.Aliased_Operand)
		}
	}
	old_length := array_storage.array_length
	normalized, index_ok := array_normalize_set_index(old_length, index)
	if !index_ok || normalized > JQ_ARRAY_INDEX_MAX - int(array_storage.array_offset) {
		kind := Array_Error.Invalid_Index
		if index_ok {
			kind = .Index_Too_Large
		}
		return {}, make_array_operation_error(kind)
	}
	required := max(old_length, normalized + 1)
	writable, write_error := array_make_writable(array, required)
	if array_error_kind(&write_error) != .None {
		return {}, write_error
	}
	array_storage = value_storage_of(array)
	elements := array_payload_values(writable)
	position := int(array_storage.array_offset) + normalized
	initialized_before := writable.array_initialized_length
	if position >= writable.array_initialized_length {
		for i in writable.array_initialized_length..=position {
			elements[i] = null_value()
		}
	}
	if position < initialized_before && (writable == p || normalized < old_length) {
		displaced = take_value(&elements[position])
	}
	elements[position] = take_value(element)
	writable.array_initialized_length = max(initialized_before, position + 1)
	array_storage.array_length = required
	return displaced, nil
}

// array_append_take has the same transactional ownership shape as set. A
// unique sliced view can append over an initialized hidden suffix slot, so the
// displaced owner must be returned rather than destroyed internally.
array_append_take :: proc(array: ^Value, element: ^Value) -> (
	displaced: Value,
	err: Array_Operation_Error,
) {
	length, ok := array_length(array)
	if !ok {
		return {}, make_array_operation_error(.Wrong_Kind)
	}
	if length == max(int) {
		return {}, make_array_operation_error(.Size_Overflow)
	}
	return array_set_take(array, length, element)
}

@(private)
clamp_slice_index :: proc(length, index: int) -> int {
	result := index
	if result < 0 {
		if result < -length {
			return 0
		}
		result += length
	}
	return clamp(result, 0, length)
}

// array_slice borrows source and returns an independently owned array handle.
// A normal nonempty slice retains the same backing and adjusts only its view.
// Empty slices and 16-bit offset overflow materialize through allocator.
array_slice :: proc(
	source: ^Value,
	start, end: int,
	allocator: runtime.Allocator,
) -> (result: Value, err: Array_Operation_Error) {
	source_storage, p, ok := array_storage_of(source)
	if !ok {
		return {}, make_array_operation_error(.Wrong_Kind)
	}
	clamped_start := clamp_slice_index(source_storage.array_length, start)
	clamped_end := clamp_slice_index(source_storage.array_length, end)
	if clamped_end < clamped_start {
		clamped_end = clamped_start
	}
	length := clamped_end - clamped_start
	if length == 0 {
		return array_value(allocator)
	}
	new_offset := int(source_storage.array_offset) + clamped_start
	if new_offset < 1 << 16 {
		assert(p.references > 0)
		if p.references == max(int) {
			return {}, make_array_operation_error(.Size_Overflow)
		}
		p.references += 1
		return value_from_storage({
			kind = .Array,
			owned_payload = p,
			array_length = length,
			array_offset = u16(new_offset),
		}), nil
	}

	copy_payload, alloc_error := allocate_array_payload(length, allocator)
	if array_error_kind(&alloc_error) != .None {
		return {}, alloc_error
	}
	copy_payload.array_initialized_length = length
	source_elements := array_payload_values(p)
	destination := array_payload_values(copy_payload)
	for i in 0..<length {
		destination[i] = clone_value(
			&source_elements[int(source_storage.array_offset) + clamped_start + i],
		)
	}
	return value_from_storage({
		kind = .Array,
		owned_payload = copy_payload,
		array_length = length,
	}), nil
}

@(private)
arrays_equal :: proc(a, b: ^Value) -> bool {
	left_storage, left, left_ok := array_storage_of(a)
	right_storage, right, right_ok := array_storage_of(b)
	if !left_ok || !right_ok || left_storage.array_length != right_storage.array_length {
		return false
	}
	if left == right && left_storage.array_offset == right_storage.array_offset {
		return true
	}
	left_elements := array_payload_values(left)
	right_elements := array_payload_values(right)
	for i in 0..<left_storage.array_length {
		left_index := int(left_storage.array_offset) + i
		right_index := int(right_storage.array_offset) + i
		if !values_equal(&left_elements[left_index], &right_elements[right_index]) {
			return false
		}
	}
	return true
}
