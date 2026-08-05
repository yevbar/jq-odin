package value

import "base:runtime"

Object_Error :: enum u8 {
	None,
	Out_Of_Memory,
	Wrong_Kind,
	Size_Overflow,
	Aliased_Operand,
	Allocator_Unsupported,
	Cleanup_Failed,
}

@(private)
object_operation_error_storage :: struct {
	kind:              Object_Error,
	cause:             Object_Error,
	constructor_error: Constructor_Error,
}

// Object_Operation_Error may preserve an interrupted Object_Error and own a
// failed temporary allocation cleanup. It must not be copied; use
// take_object_error and destroy_object_error.
Object_Operation_Error :: union {
	object_operation_error_storage,
}

@(private)
make_object_error :: proc(kind: Object_Error) -> Object_Operation_Error {
	if kind == .None do return {}
	return object_operation_error_storage{kind = kind}
}

@(private)
make_object_cleanup_error :: proc(
	cause: Object_Error,
	cleanup: ^Constructor_Error,
) -> Object_Operation_Error {
	normalized_cause := cause
	if normalized_cause == .Cleanup_Failed do normalized_cause = .None
	return object_operation_error_storage{
		kind = .Cleanup_Failed,
		cause = normalized_cause,
		constructor_error = take_constructor_error(cleanup),
	}
}

object_error_kind :: proc(err: ^Object_Operation_Error) -> Object_Error {
	if err == nil || err^ == nil do return .None
	return err.(object_operation_error_storage).kind
}

// object_error_cause returns the operation outcome interrupted by cleanup. It
// is None unless object_error_kind is Cleanup_Failed.
object_error_cause :: proc(err: ^Object_Operation_Error) -> Object_Error {
	if err == nil || err^ == nil do return .None
	storage := &err.(object_operation_error_storage)
	if storage.kind != .Cleanup_Failed do return .None
	return storage.cause
}

object_error_needs_cleanup :: proc(err: ^Object_Operation_Error) -> bool {
	if err == nil || err^ == nil do return false
	storage := &err.(object_operation_error_storage)
	return constructor_error_needs_cleanup(&storage.constructor_error)
}

take_object_error :: proc(source: ^Object_Operation_Error) -> Object_Operation_Error {
	if source == nil do return {}
	result := source^
	source^ = {}
	return result
}

destroy_object_error :: proc(err: ^Object_Operation_Error) -> runtime.Allocator_Error {
	if err == nil || err^ == nil do return nil
	storage := &err.(object_operation_error_storage)
	cleanup_error := destroy_constructor_error(&storage.constructor_error)
	if cleanup_error != nil do return cleanup_error
	err^ = {}
	return nil
}

@(private)
retire_object_temporary :: proc(
	kind: Object_Error,
	memory: []byte,
	allocator: runtime.Allocator,
) -> Object_Operation_Error {
	if len(memory) > 0 {
		free_error := runtime.mem_free_bytes(memory, allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			cleanup := make_cleanup_constructor_error(.Out_Of_Memory, memory, allocator)
			return make_object_cleanup_error(kind, &cleanup)
		}
	}
	return make_object_error(kind)
}

@(private)
object_slot :: struct {
	next:  int,
	hash:  u32,
	key:   Value,
	value: Value,
}

@(private)
OBJECT_INITIAL_CAPACITY :: 8

@(private)
OBJECT_EMPTY_SLOT_NEXT :: -1

#assert(size_of(payload) % align_of(object_slot) == 0)
#assert(size_of(object_slot) % align_of(int) == 0)
#assert(align_of(payload) >= align_of(object_slot))

@(private)
object_allocation_size :: proc(capacity: int) -> (size: int, ok: bool) {
	if capacity <= 0 || capacity > max(int) / 2 do return 0, false
	bucket_count := capacity * 2
	header := int(size_of(payload))
	if capacity > (max(int) - header) / int(size_of(object_slot)) do return 0, false
	slots_end := header + capacity * int(size_of(object_slot))
	if bucket_count > (max(int) - slots_end) / int(size_of(int)) do return 0, false
	return slots_end + bucket_count * int(size_of(int)), true
}

@(private)
object_payload_slots :: proc(p: ^payload) -> []object_slot {
	if p == nil || p.object_capacity == 0 do return nil
	data := cast([^]object_slot)(uintptr(p) + size_of(payload))
	return data[:p.object_capacity]
}

@(private)
object_payload_buckets :: proc(p: ^payload) -> []int {
	if p == nil || p.object_capacity == 0 do return nil
	data := cast([^]int)(uintptr(p) + size_of(payload) +
		uintptr(p.object_capacity * int(size_of(object_slot))))
	return data[:p.object_capacity * 2]
}

@(private)
object_slot_set_empty :: proc(slot: ^object_slot) {
	assert(slot != nil)
	slot^ = {next = OBJECT_EMPTY_SLOT_NEXT}
}

@(private)
object_slot_is_canonical_empty :: proc(slot: ^object_slot) -> bool {
	return slot != nil && slot.next == OBJECT_EMPTY_SLOT_NEXT && slot.hash == 0 &&
	       slot.key == nil && slot.value == nil
}

@(private)
allocate_object_payload :: proc(
	capacity: int,
	allocator: runtime.Allocator,
) -> (p: ^payload, err: Object_Operation_Error) {
	allocation_size, size_ok := object_allocation_size(capacity)
	if !size_ok do return nil, make_object_error(.Size_Overflow)
	memory, alloc_error := runtime.mem_alloc(allocation_size, align_of(payload), allocator)
	if alloc_error != nil || len(memory) != allocation_size {
		kind := Object_Error.Out_Of_Memory
		if alloc_error == .Mode_Not_Implemented do kind = .Allocator_Unsupported
		return nil, retire_object_temporary(kind, memory, allocator)
	}
	p = cast(^payload)(raw_data(memory))
	p.references = 1
	p.allocator = allocator
	p.allocation_size = allocation_size
	p.kind = .Object
	p.object_capacity = capacity
	for &slot in object_payload_slots(p) {
		object_slot_set_empty(&slot)
	}
	for &bucket in object_payload_buckets(p) do bucket = -1
	return p, nil
}

// object_value constructs an empty owning object. The allocation identity is
// retained by clone_value and detached by the first mutation of a shared copy.
object_value :: proc(allocator: runtime.Allocator) -> (Value, Object_Operation_Error) {
	p, err := allocate_object_payload(OBJECT_INITIAL_CAPACITY, allocator)
	if object_error_kind(&err) != .None do return {}, err
	return value_from_payload(.Object, p), nil
}

@(private)
object_storage_extent_valid :: proc(storage: ^value_storage, allow_retiring := false) -> bool {
	if storage == nil do return false
	if storage.kind != .Object || storage.owned_payload == nil ||
	   storage.owned_payload.kind != .Object ||
	   (!allow_retiring && storage.owned_payload.object_retiring) {
		return false
	}
	p := storage.owned_payload
	if p.references <= 0 || p.references == max(int) ||
	   p.object_capacity < OBJECT_INITIAL_CAPACITY ||
	   p.object_capacity & (p.object_capacity - 1) != 0 ||
	   p.object_next_free < 0 || p.object_next_free > p.object_capacity ||
	   p.object_length < 0 || p.object_length > p.object_next_free {
		return false
	}
	expected_size, size_ok := object_allocation_size(p.object_capacity)
	return size_ok && payload_bound_matches(storage, expected_size)
}

@(private)
object_storage_of :: proc(value: ^Value) -> (^payload, bool) {
	if value == nil || value^ == nil do return nil, false
	storage := value_storage_of(value)
	if !object_storage_extent_valid(storage) do return nil, false
	p := storage.owned_payload
	return p, true
}

object_length :: proc(value: ^Value) -> (int, bool) {
	p, ok := object_storage_of(value)
	if !ok do return 0, false
	return p.object_length, true
}

@(private)
object_hash :: proc(bytes: string) -> u32 {
	// Hash choice is representation-private: jq-visible iteration follows slot
	// order, never bucket order.
	h := u32(2166136261)
	for c in bytes {
		h = (h ~ u32(c)) * 16777619
	}
	return h
}

@(private)
object_find_slot :: proc(p: ^payload, key: string) -> (index: int, found: bool) {
	hash := object_hash(key)
	buckets := object_payload_buckets(p)
	slots := object_payload_slots(p)
	index = buckets[int(hash & u32(len(buckets) - 1))]
	for index >= 0 {
		slot := &slots[index]
		candidate, ok := string_borrowed(&slot.key)
		if ok && slot.hash == hash && candidate == key do return index, true
		index = slot.next
	}
	return -1, false
}

// object_get_copy borrows object/key and returns an independently owned value.
// The result must be transferred or destroyed. No borrowed slot escapes.
object_get_copy :: proc(object: ^Value, key: string) -> (Value, bool) {
	p, ok := object_storage_of(object)
	if !ok do return {}, false
	index, found := object_find_slot(p, key)
	if !found do return {}, false
	return clone_value(&object_payload_slots(p)[index].value), true
}

@(private)
object_copy_for_write :: proc(p: ^payload) -> (^payload, Object_Operation_Error) {
	copy_payload, err := allocate_object_payload(p.object_capacity, p.allocator)
	if object_error_kind(&err) != .None do return nil, err
	copy_payload.object_next_free = p.object_next_free
	copy_payload.object_length = p.object_length
	source := object_payload_slots(p)
	destination := object_payload_slots(copy_payload)
	for i in 0..<p.object_next_free {
		destination[i].next = source[i].next
		destination[i].hash = source[i].hash
		if kind_of(&source[i].key) == .String {
			destination[i].key = clone_value(&source[i].key)
			destination[i].value = clone_value(&source[i].value)
		}
	}
	copy(object_payload_buckets(copy_payload), object_payload_buckets(p))
	return copy_payload, nil
}

@(private)
object_rehash_unique :: proc(object: ^Value, p: ^payload) -> (^payload, Object_Operation_Error) {
	if p.object_capacity > max(int) / 2 do return nil, make_object_error(.Size_Overflow)
	replacement, err := allocate_object_payload(p.object_capacity * 2, p.allocator)
	if object_error_kind(&err) != .None do return nil, err
	source := object_payload_slots(p)
	destination := object_payload_slots(replacement)
	buckets := object_payload_buckets(replacement)
	for i in 0..<p.object_next_free {
		if kind_of(&source[i].key) != .String do continue
		at := replacement.object_next_free
		destination[at].key = source[i].key
		destination[at].value = source[i].value
		destination[at].hash = source[i].hash
		bucket := int(destination[at].hash & u32(len(buckets) - 1))
		destination[at].next = buckets[bucket]
		buckets[bucket] = at
		replacement.object_next_free += 1
		replacement.object_length += 1
	}
	old_size := value_storage_of(object).payload_allocation_bound
	old_memory := ([^]byte)(rawptr(p))[:old_size]
	free_error := runtime.mem_free_bytes(old_memory, p.allocator)
	if free_error != nil && free_error != .Mode_Not_Implemented {
		replacement_memory := ([^]byte)(rawptr(replacement))[:replacement.allocation_size]
		return nil, retire_object_temporary(.Cleanup_Failed, replacement_memory, p.allocator)
	}
	value_storage_of(object).owned_payload = replacement
	value_storage_of(object).payload_allocation_bound = replacement.allocation_size
	return replacement, nil
}

@(private)
object_make_writable :: proc(object: ^Value) -> (^payload, Object_Operation_Error) {
	p, ok := object_storage_of(object)
	if !ok do return nil, make_object_error(.Wrong_Kind)
	if p.references == 1 do return p, nil
	copy_payload, err := object_copy_for_write(p)
	if object_error_kind(&err) != .None do return nil, err
	p.references -= 1
	value_storage_of(object).owned_payload = copy_payload
	value_storage_of(object).payload_allocation_bound = copy_payload.allocation_size
	return copy_payload, nil
}

@(private)
object_operand_aliased :: proc(p: ^payload, operand: ^Value) -> bool {
	if operand == nil do return false
	slots := object_payload_slots(p)
	if len(slots) == 0 do return false
	first := uintptr(&slots[0])
	limit := first + uintptr(len(slots) * int(size_of(object_slot)))
	address := uintptr(operand)
	return address >= first && address < limit
}

// object_set_take inserts or replaces by string key. Success consumes key and
// value. For replacement, duplicate_key owns the unused incoming key and
// displaced owns the prior value; callers must destroy or transfer both. On
// failure all returned Values are invalid and both inputs remain unchanged.
object_set_take :: proc(
	object, key, value: ^Value,
) -> (duplicate_key, displaced: Value, err: Object_Operation_Error) {
	p, ok := object_storage_of(object)
	if !ok || kind_of(key) != .String || !value_local_extent_valid(key) ||
	   kind_of(value) == .Invalid || !value_local_extent_valid(value) ||
	   value_is_retiring(value) {
		return {}, {}, make_object_error(.Wrong_Kind)
	}
	if object == key || object == value || key == value ||
	   object_operand_aliased(p, key) || object_operand_aliased(p, value) {
		return {}, {}, make_object_error(.Aliased_Operand)
	}
	key_bytes, _ := string_borrowed(key)
	_, existed := object_find_slot(p, key_bytes)
	writable, write_error := object_make_writable(object)
	if object_error_kind(&write_error) != .None do return {}, {}, write_error
	if !existed && writable.object_next_free == writable.object_capacity {
		writable, write_error = object_rehash_unique(object, writable)
		if object_error_kind(&write_error) != .None do return {}, {}, write_error
	}
	index, found := object_find_slot(writable, key_bytes)
	slots := object_payload_slots(writable)
	if found {
		duplicate_key = take_value(key)
		displaced = take_value(&slots[index].value)
		slots[index].value = take_value(value)
		return
	}
	index = writable.object_next_free
	hash := object_hash(key_bytes)
	buckets := object_payload_buckets(writable)
	bucket := int(hash & u32(len(buckets) - 1))
	slots[index].next = buckets[bucket]
	slots[index].hash = hash
	slots[index].key = take_value(key)
	slots[index].value = take_value(value)
	buckets[bucket] = index
	writable.object_next_free += 1
	writable.object_length += 1
	return
}

// object_delete_take removes key if present and returns the owned stored key
// and value. The string argument is borrowed. Failure/miss changes nothing.
object_delete_take :: proc(
	object: ^Value,
	key: string,
) -> (removed_key, removed_value: Value, found: bool, err: Object_Operation_Error) {
	p, ok := object_storage_of(object)
	if !ok do return {}, {}, false, make_object_error(.Wrong_Kind)
	_, existed := object_find_slot(p, key)
	if !existed do return {}, {}, false, nil
	writable, write_error := object_make_writable(object)
	if object_error_kind(&write_error) != .None do return {}, {}, false, write_error
	hash := object_hash(key)
	buckets := object_payload_buckets(writable)
	bucket := int(hash & u32(len(buckets) - 1))
	slots := object_payload_slots(writable)
	previous := &buckets[bucket]
	index := previous^
	for index >= 0 {
		slot := &slots[index]
		candidate, key_ok := string_borrowed(&slot.key)
		if key_ok && slot.hash == hash && candidate == key {
			previous^ = slot.next
			removed_key = take_value(&slot.key)
			removed_value = take_value(&slot.value)
			object_slot_set_empty(slot)
			writable.object_length -= 1
			return removed_key, removed_value, true, nil
		}
		previous = &slot.next
		index = slot.next
	}
	return {}, {}, false, nil
}

// Object_Iterator is a borrowed traversal position. It may only be used with
// the same live, unmutated object. Returned keys/values are independent owners.
Object_Iterator :: struct {
	index: int,
}

object_iterator :: proc() -> Object_Iterator { return {index = -1} }

object_iter_next_copy :: proc(
	object: ^Value,
	iterator: ^Object_Iterator,
) -> (key, value: Value, ok: bool) {
	p, object_ok := object_storage_of(object)
	if !object_ok || iterator == nil do return
	for i := iterator.index + 1; i < p.object_next_free; i += 1 {
		slot := &object_payload_slots(p)[i]
		if kind_of(&slot.key) == .String {
			iterator.index = i
			return clone_value(&slot.key), clone_value(&slot.value), true
		}
	}
	iterator.index = p.object_next_free
	return
}

@(private)
objects_equal :: proc(a, b: ^Value) -> bool {
	left, left_ok := object_storage_of(a)
	right, right_ok := object_storage_of(b)
	if !left_ok || !right_ok || left.object_length != right.object_length do return false
	if left == right do return true
	for i in 0..<left.object_next_free {
		slot := &object_payload_slots(left)[i]
		key, key_ok := string_borrowed(&slot.key)
		if !key_ok do continue
		right_index, found := object_find_slot(right, key)
		if !found || !values_equal(&slot.value, &object_payload_slots(right)[right_index].value) {
			return false
		}
	}
	return true
}
