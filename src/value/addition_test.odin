package value

import "base:runtime"
import "core:math"
import "core:testing"

@(private)
add_expect_success :: proc(t: ^testing.T, left, right: ^Value) -> Value {
	result, err := value_add(left, right, context.allocator)
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.None)
	testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	return result
}

@(private)
add_array_of_two :: proc(t: ^testing.T, first, second: Value) -> Value {
	first_owner := first
	second_owner := second
	result, err := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&err), Array_Error.None)
	displaced, append_error := array_append_take(&result, &first_owner)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	displaced, append_error = array_append_take(&result, &second_owner)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	return result
}

@(private)
add_object_put_value :: proc(t: ^testing.T, object: ^Value, key_text: string, item: Value) {
	item_owner := item
	key, key_error := string_value(key_text, context.allocator)
	testing.expect_value(t, constructor_error_kind(&key_error), Error.None)
	duplicate, displaced, set_error := object_set_take(object, &key, &item_owner)
	testing.expect_value(t, object_error_kind(&set_error), Object_Error.None)
	testing.expect_value(t, destroy_value(&duplicate), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
}

@(test)
value_add_accepts_exact_jq_type_table_and_null_identity :: proc(t: ^testing.T) {
	null := null_value()
	false_value := boolean_value(false)
	number := number_value(2.5)
	string, string_error := string_value("ab", context.allocator)
	testing.expect_value(t, constructor_error_kind(&string_error), Error.None)
	array, array_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&array_error), Array_Error.None)
	object, object_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)

	identity_operands := [?]^Value{&null, &false_value, &number, &string, &array, &object}
	for operand in identity_operands {
		left_identity := add_expect_success(t, &null, operand)
		right_identity := add_expect_success(t, operand, &null)
		testing.expect(t, values_equal(&left_identity, operand))
		testing.expect(t, values_equal(&right_identity, operand))
		testing.expect_value(t, destroy_value(&left_identity), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&right_identity), runtime.Allocator_Error.None)
	}

	other_number := number_value(1.25)
	sum := add_expect_success(t, &number, &other_number)
	sum_number, sum_ok := number_value_get(&sum)
	testing.expect(t, sum_ok && sum_number == 3.75)
	other_string, other_string_error := string_value("cd", context.allocator)
	testing.expect_value(t, constructor_error_kind(&other_string_error), Error.None)
	joined := add_expect_success(t, &string, &other_string)
	joined_bytes, joined_ok := string_borrowed(&joined)
	testing.expect(t, joined_ok && joined_bytes == "abcd")
	empty_array_sum := add_expect_success(t, &array, &array)
	empty_object_sum := add_expect_success(t, &object, &object)
	empty_array_length, empty_array_ok := array_length(&empty_array_sum)
	empty_object_length, empty_object_ok := object_length(&empty_object_sum)
	testing.expect(t, empty_array_ok && empty_array_length == 0)
	testing.expect(t, empty_object_ok && empty_object_length == 0)

	owned_values := [?]^Value{
		&sum, &joined, &empty_array_sum, &empty_object_sum, &other_string,
		&object, &array, &string, &number, &false_value, &null,
	}
	for value in owned_values {
		testing.expect_value(t, destroy_value(value), runtime.Allocator_Error.None)
	}
}

@(test)
value_add_rejects_invalid_and_every_unaccepted_mixed_pair :: proc(t: ^testing.T) {
	invalid := invalid_value()
	null := null_value()
	boolean := boolean_value(true)
	number := number_value(1)
	string, string_error := string_value("x", context.allocator)
	testing.expect_value(t, constructor_error_kind(&string_error), Error.None)
	array, array_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&array_error), Array_Error.None)
	object, object_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	values := [?]^Value{&boolean, &number, &string, &array, &object}
	for left, left_index in values {
		for right, right_index in values {
			if left_index == right_index && left_index != 0 do continue
			result, err := value_add(left, right, context.allocator)
			testing.expect_value(t, kind_of(&result), Kind.Invalid)
			testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Invalid_Type_Pair)
			testing.expect(t, !value_add_error_needs_cleanup(&err))
			testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
		}
	}
	invalid_peers := [?]^Value{&null, &boolean, &number, &string, &array, &object}
	for operand in invalid_peers {
		result, err := value_add(&invalid, operand, context.allocator)
		testing.expect_value(t, kind_of(&result), Kind.Invalid)
		testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Invalid_Operand)
		testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	}
	result, nil_error := value_add(nil, &null, context.allocator)
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect_value(t, value_add_error_kind(&nil_error), Value_Add_Error_Kind.Invalid_Operand)
	testing.expect_value(t, destroy_value_add_error(&nil_error), runtime.Allocator_Error.None)
	owned_values := [?]^Value{&object, &array, &string, &number, &boolean, &null}
	for value in owned_values {
		testing.expect_value(t, destroy_value(value), runtime.Allocator_Error.None)
	}
}

@(private)
add_expect_malformed_matrix :: proc(t: ^testing.T, malformed: ^Value, peers: []^Value) {
	storage: ^value_storage
	original_kind: Kind
	original_payload: ^payload
	original_length: int
	if malformed != nil && malformed^ != nil {
		storage = value_storage_of(malformed)
		original_kind = storage.kind
		original_payload = storage.owned_payload
		original_length = storage.array_length
	}
	operand_sides := [?]bool{true, false}
	for peer in peers {
		for malformed_on_left in operand_sides {
			probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
			left := peer
			right := malformed
			if malformed_on_left {
				left = malformed
				right = peer
			}
			result, err := value_add(left, right, probe_allocator(&probe))
			testing.expect_value(t, kind_of(&result), Kind.Invalid)
			testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Invalid_Operand)
			testing.expect_value(t, probe.allocations, 0)
			testing.expect_value(t, probe.frees, 0)
			if storage != nil {
				testing.expect_value(t, storage.kind, original_kind)
				testing.expect(t, storage.owned_payload == original_payload)
				testing.expect_value(t, storage.array_length, original_length)
			}
			testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
		}
	}
}

@(private)
add_expect_preflight_kind_without_result_allocator :: proc(
	t: ^testing.T,
	operand, peer: ^Value,
	expected: Value_Add_Error_Kind,
) {
	operand_sides := [?]bool{true, false}
	for malformed_on_left in operand_sides {
		left, right := peer, operand
		if malformed_on_left do left, right = operand, peer
		probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
		result, err := value_add(left, right, probe_allocator(&probe))
		testing.expect_value(t, kind_of(&result), Kind.Invalid)
		testing.expect_value(t, value_add_error_kind(&err), expected)
		testing.expect_value(t, probe.allocations, 0)
		testing.expect_value(t, probe.frees, 0)
		testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	}
}

@(test)
value_add_checks_handle_extent_before_payload_metadata_views :: proc(t: ^testing.T) {
	peer := boolean_value(true)
	defer destroy_value(&peer)

	string, string_error := string_value("abcd", context.allocator)
	testing.expect_value(t, constructor_error_kind(&string_error), Error.None)
	defer destroy_value(&string)
	string_storage := value_storage_of(&string)
	string_payload := string_storage.owned_payload
	string_bytes := string_payload.byte_count
	string_size := string_payload.allocation_size
	string_payload.byte_count = string_bytes - 1
	string_payload.allocation_size = string_size - 1
	add_expect_preflight_kind_without_result_allocator(
		t, &string, &peer, .Invalid_Operand,
	)
	string_payload.byte_count = string_bytes
	string_payload.allocation_size = string_size
	add_expect_preflight_kind_without_result_allocator(
		t, &string, &peer, .Invalid_Type_Pair,
	)
	string_payload.byte_count = string_bytes + 1
	string_payload.allocation_size = string_size + 1
	add_expect_preflight_kind_without_result_allocator(
		t, &string, &peer, .Invalid_Operand,
	)
	string_payload.byte_count = string_bytes
	string_payload.allocation_size = string_size
	string_payload.byte_count = max(int)
	add_expect_preflight_kind_without_result_allocator(
		t, &string, &peer, .Invalid_Operand,
	)
	string_payload.byte_count = string_bytes
	string_payload.allocation_size = string_size

	literal, literal_error := literal_number_value("12.5", context.allocator)
	testing.expect_value(t, constructor_error_kind(&literal_error), Error.None)
	defer destroy_value(&literal)
	literal_storage := value_storage_of(&literal)
	literal_payload := literal_storage.owned_payload
	literal_bytes := literal_payload.byte_count
	literal_coefficient := literal_payload.coefficient_len
	literal_size := literal_payload.allocation_size
	literal_payload.byte_count = literal_bytes - 1
	literal_payload.allocation_size = literal_size - 1
	add_expect_preflight_kind_without_result_allocator(
		t, &literal, &peer, .Invalid_Operand,
	)
	literal_payload.byte_count = literal_bytes
	literal_payload.allocation_size = literal_size
	add_expect_preflight_kind_without_result_allocator(
		t, &literal, &peer, .Invalid_Type_Pair,
	)
	literal_payload.byte_count = literal_bytes + 1
	literal_payload.allocation_size = literal_size + 1
	add_expect_preflight_kind_without_result_allocator(
		t, &literal, &peer, .Invalid_Operand,
	)
	literal_payload.byte_count = literal_bytes
	literal_payload.allocation_size = literal_size
	literal_payload.coefficient_len = max(int)
	add_expect_preflight_kind_without_result_allocator(
		t, &literal, &peer, .Invalid_Operand,
	)
	literal_payload.byte_count = literal_bytes
	literal_payload.coefficient_len = literal_coefficient
	literal_payload.allocation_size = literal_size

	array_payload, array_error := allocate_array_payload(17, context.allocator)
	testing.expect_value(t, array_error_kind(&array_error), Array_Error.None)
	array := value_from_payload(.Array, array_payload)
	defer destroy_value(&array)
	array_capacity := array_payload.array_capacity
	array_size := array_payload.allocation_size
	smaller_array_size, smaller_array_ok := array_allocation_size(array_capacity - 1)
	testing.expect(t, smaller_array_ok)
	array_payload.array_capacity = array_capacity - 1
	array_payload.allocation_size = smaller_array_size
	add_expect_preflight_kind_without_result_allocator(
		t, &array, &peer, .Invalid_Operand,
	)
	array_payload.array_capacity = array_capacity
	array_payload.allocation_size = array_size
	add_expect_preflight_kind_without_result_allocator(
		t, &array, &peer, .Invalid_Type_Pair,
	)
	larger_array_size, larger_array_ok := array_allocation_size(array_capacity + 1)
	testing.expect(t, larger_array_ok)
	array_payload.array_capacity = array_capacity + 1
	array_payload.allocation_size = larger_array_size
	add_expect_preflight_kind_without_result_allocator(
		t, &array, &peer, .Invalid_Operand,
	)
	array_payload.array_capacity = array_capacity
	array_payload.allocation_size = array_size
	array_payload.array_capacity = max(int)
	add_expect_preflight_kind_without_result_allocator(
		t, &array, &peer, .Invalid_Operand,
	)
	array_payload.array_capacity = array_capacity
	array_payload.allocation_size = array_size

	object, object_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	defer destroy_value(&object)
	object_storage := value_storage_of(&object)
	object_payload := object_storage.owned_payload
	object_capacity := object_payload.object_capacity
	object_size := object_payload.allocation_size
	object_storage.payload_allocation_bound = object_size - 1
	add_expect_preflight_kind_without_result_allocator(
		t, &object, &peer, .Invalid_Operand,
	)
	object_storage.payload_allocation_bound = object_size
	add_expect_preflight_kind_without_result_allocator(
		t, &object, &peer, .Invalid_Type_Pair,
	)
	object_storage.payload_allocation_bound = object_size + 1
	add_expect_preflight_kind_without_result_allocator(
		t, &object, &peer, .Invalid_Operand,
	)
	object_storage.payload_allocation_bound = object_size
	capacity_16_size, capacity_16_ok := object_allocation_size(16)
	testing.expect(t, capacity_16_ok)
	object_payload.object_capacity = 16
	object_payload.allocation_size = capacity_16_size
	add_expect_preflight_kind_without_result_allocator(
		t, &object, &peer, .Invalid_Operand,
	)
	object_payload.object_capacity = object_capacity
	object_payload.allocation_size = object_size
	object_payload.object_capacity = max(int)
	add_expect_preflight_kind_without_result_allocator(
		t, &object, &peer, .Invalid_Operand,
	)
	object_payload.object_capacity = object_capacity
	object_payload.allocation_size = object_size
}

@(test)
value_add_rejects_complete_malformed_representation_matrix_without_allocation :: proc(t: ^testing.T) {
	null := null_value()
	boolean := boolean_value(true)
	number := number_value(2)
	string, string_error := string_value("s", context.allocator)
	array, array_error := array_value(context.allocator)
	object, object_error := object_value(context.allocator)
	testing.expect_value(t, constructor_error_kind(&string_error), Error.None)
	testing.expect_value(t, array_error_kind(&array_error), Array_Error.None)
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	array_item := number_value(1)
	array_displaced, array_append_error := array_append_take(&array, &array_item)
	testing.expect_value(t, array_error_kind(&array_append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&array_displaced), runtime.Allocator_Error.None)
	add_object_put_value(t, &object, "member", number_value(1))
	peers := [?]^Value{&null, &boolean, &number, &string, &array, &object}

	invalid := invalid_value()
	add_expect_malformed_matrix(t, &invalid, peers[:])

	// Null, Boolean, and Number must reject a payload retained from a String.
	string_storage := value_storage_of(&string)
	forged_kinds := [?]Kind{.Null, .Boolean, .Number}
	for forged_kind in forged_kinds {
		string_storage.kind = forged_kind
		add_expect_malformed_matrix(t, &string, peers[:])
		string_storage.kind = .String
	}

	string_payload := string_storage.owned_payload
	string_storage.owned_payload = nil
	add_expect_malformed_matrix(t, &string, peers[:])
	string_storage.owned_payload = string_payload
	string_payload.kind = .Literal_Number
	add_expect_malformed_matrix(t, &string, peers[:])
	string_payload.kind = .String
	original_references := string_payload.references
	string_payload.references = 0
	add_expect_malformed_matrix(t, &string, peers[:])
	string_payload.references = max(int)
	add_expect_malformed_matrix(t, &string, peers[:])
	string_payload.references = original_references
	original_bytes := string_payload.byte_count
	string_payload.byte_count = -1
	add_expect_malformed_matrix(t, &string, peers[:])
	string_payload.byte_count = max(int)
	add_expect_malformed_matrix(t, &string, peers[:])
	string_payload.byte_count = original_bytes
	string_payload.coefficient_len = 1
	add_expect_malformed_matrix(t, &string, peers[:])
	string_payload.coefficient_len = 0
	original_allocation_size := string_payload.allocation_size
	string_payload.allocation_size += 1
	add_expect_malformed_matrix(t, &string, peers[:])
	string_payload.allocation_size = original_allocation_size

	literal, literal_error := literal_number_value("1.25", context.allocator)
	testing.expect_value(t, constructor_error_kind(&literal_error), Error.None)
	literal_payload := value_storage_of(&literal).owned_payload
	original_literal_kind := literal_payload.kind
	literal_payload.kind = .String
	add_expect_malformed_matrix(t, &literal, peers[:])
	literal_payload.kind = original_literal_kind
	original_literal_coefficient := literal_payload.coefficient_len
	literal_payload.coefficient_len = -1
	add_expect_malformed_matrix(t, &literal, peers[:])
	literal_payload.coefficient_len = max(int)
	add_expect_malformed_matrix(t, &literal, peers[:])
	literal_payload.coefficient_len = original_literal_coefficient
	original_literal_size := literal_payload.allocation_size
	literal_payload.allocation_size += 1
	add_expect_malformed_matrix(t, &literal, peers[:])
	literal_payload.allocation_size = original_literal_size

	array_storage := value_storage_of(&array)
	array_payload := array_storage.owned_payload
	array_storage.owned_payload = nil
	add_expect_malformed_matrix(t, &array, peers[:])
	array_storage.owned_payload = array_payload
	original_array_kind := array_payload.kind
	array_payload.kind = .Object
	add_expect_malformed_matrix(t, &array, peers[:])
	array_payload.kind = original_array_kind
	original_array_references := array_payload.references
	array_payload.references = 0
	add_expect_malformed_matrix(t, &array, peers[:])
	array_payload.references = max(int)
	add_expect_malformed_matrix(t, &array, peers[:])
	array_payload.references = original_array_references
	original_capacity := array_payload.array_capacity
	array_payload.array_capacity = -1
	add_expect_malformed_matrix(t, &array, peers[:])
	array_payload.array_capacity = original_capacity
	original_initialized := array_payload.array_initialized_length
	array_payload.array_initialized_length = -1
	add_expect_malformed_matrix(t, &array, peers[:])
	array_payload.array_initialized_length = original_capacity + 1
	add_expect_malformed_matrix(t, &array, peers[:])
	array_payload.array_initialized_length = original_initialized
	array_payload.array_retired_count = -1
	add_expect_malformed_matrix(t, &array, peers[:])
	array_payload.array_retired_count = max(int)
	add_expect_malformed_matrix(t, &array, peers[:])
	array_payload.array_retired_count = 0
	array_storage.array_length = -1
	add_expect_malformed_matrix(t, &array, peers[:])
	array_storage.array_length = original_initialized + 1
	add_expect_malformed_matrix(t, &array, peers[:])
	array_storage.array_length = 1
	original_array_size := array_payload.allocation_size
	array_payload.allocation_size += 1
	add_expect_malformed_matrix(t, &array, peers[:])
	array_payload.allocation_size = original_array_size
	array_element := &array_payload_values(array_payload)[0]
	array_element_storage := value_storage_of(array_element)
	original_element_kind := array_element_storage.kind
	array_element_storage.kind = .Invalid
	add_expect_malformed_matrix(t, &array, peers[:])
	array_element_storage.kind = original_element_kind
	array_payload.array_retiring = true
	add_expect_malformed_matrix(t, &array, peers[:])
	array_payload.array_retiring = false

	object_storage := value_storage_of(&object)
	object_payload := object_storage.owned_payload
	object_storage.owned_payload = nil
	add_expect_malformed_matrix(t, &object, peers[:])
	object_storage.owned_payload = object_payload
	original_object_kind := object_payload.kind
	object_payload.kind = .Array
	add_expect_malformed_matrix(t, &object, peers[:])
	object_payload.kind = original_object_kind
	original_object_references := object_payload.references
	object_payload.references = 0
	add_expect_malformed_matrix(t, &object, peers[:])
	object_payload.references = max(int)
	add_expect_malformed_matrix(t, &object, peers[:])
	object_payload.references = original_object_references
	original_object_capacity := object_payload.object_capacity
	object_payload.object_capacity = 3
	add_expect_malformed_matrix(t, &object, peers[:])
	object_payload.object_capacity = original_object_capacity
	original_next_free := object_payload.object_next_free
	object_payload.object_next_free = -1
	add_expect_malformed_matrix(t, &object, peers[:])
	object_payload.object_next_free = original_object_capacity + 1
	add_expect_malformed_matrix(t, &object, peers[:])
	object_payload.object_next_free = original_next_free
	original_object_length := object_payload.object_length
	object_payload.object_length = -1
	add_expect_malformed_matrix(t, &object, peers[:])
	object_payload.object_length = original_next_free + 1
	add_expect_malformed_matrix(t, &object, peers[:])
	object_payload.object_length = original_object_length
	original_object_size := object_payload.allocation_size
	object_payload.allocation_size += 1
	add_expect_malformed_matrix(t, &object, peers[:])
	object_payload.allocation_size = original_object_size
	object_slot := &object_payload_slots(object_payload)[0]
	object_key_payload := value_storage_of(&object_slot.key).owned_payload
	original_key_bytes := object_key_payload.byte_count
	object_key_payload.byte_count = max(int)
	add_expect_malformed_matrix(t, &object, peers[:])
	object_key_payload.byte_count = original_key_bytes
	original_hash := object_slot.hash
	object_slot.hash += 1
	add_expect_malformed_matrix(t, &object, peers[:])
	object_slot.hash = original_hash
	original_next := object_slot.next
	object_slot.next = original_next_free
	add_expect_malformed_matrix(t, &object, peers[:])
	object_slot.next = original_next
	buckets := object_payload_buckets(object_payload)
	bucket_index := int(object_slot.hash & u32(len(buckets) - 1))
	original_bucket := buckets[bucket_index]
	buckets[bucket_index] = -1
	add_expect_malformed_matrix(t, &object, peers[:])
	buckets[bucket_index] = original_bucket
	object_payload.object_retiring = true
	add_expect_malformed_matrix(t, &object, peers[:])
	object_payload.object_retiring = false

	// Restored operands remain healthy after every rejected pairing.
	for operand in peers {
		result := add_expect_success(t, &null, operand)
		testing.expect_value(t, kind_of(&result), kind_of(operand))
		testing.expect(t, values_equal(&result, operand))
		testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
	}
	for operand in peers {
		testing.expect_value(t, destroy_value(operand), runtime.Allocator_Error.None)
	}
	testing.expect_value(t, destroy_value(&literal), runtime.Allocator_Error.None)
}

@(private)
addition_rebuild_object_buckets :: proc(p: ^payload) {
	buckets := object_payload_buckets(p)
	for &bucket in buckets do bucket = -1
	slots := object_payload_slots(p)
	for i in 0..<p.object_next_free {
		if kind_of(&slots[i].key) != .String do continue
		key_text, key_ok := string_borrowed(&slots[i].key)
		assert(key_ok)
		slots[i].hash = object_hash(key_text)
		bucket := int(slots[i].hash & u32(len(buckets) - 1))
		slots[i].next = buckets[bucket]
		buckets[bucket] = i
	}
}

@(private)
addition_shared_owner_variant :: enum {
	Array_Child,
	Object_Key,
	Object_Value,
}

@(private)
addition_root_payload_kind :: enum {
	Array,
	Object,
	String,
}

@(private)
addition_make_root_payload :: proc(
	t: ^testing.T,
	kind: addition_root_payload_kind,
	allocator: runtime.Allocator,
) -> Value {
	switch kind {
	case .Array:
		result, err := array_value(allocator)
		testing.expect_value(t, array_error_kind(&err), Array_Error.None)
		return result
	case .Object:
		result, err := object_value(allocator)
		testing.expect_value(t, object_error_kind(&err), Object_Error.None)
		return result
	case .String:
		result, err := string_value("root-payload", allocator)
		testing.expect_value(t, constructor_error_kind(&err), Error.None)
		return result
	}
	return {}
}

@(private)
addition_append_take :: proc(t: ^testing.T, array, item: ^Value) {
	displaced, err := array_append_take(array, item)
	testing.expect_value(t, array_error_kind(&err), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
}

@(private)
addition_object_set_take :: proc(
	t: ^testing.T,
	object, key, item: ^Value,
) {
	duplicate, displaced, err := object_set_take(object, key, item)
	testing.expect_value(t, object_error_kind(&err), Object_Error.None)
	testing.expect_value(t, destroy_value(&duplicate), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
}

@(private)
addition_make_shared_owner_dag :: proc(
	t: ^testing.T,
	variant: addition_shared_owner_variant,
	allocator: runtime.Allocator,
	keep_external_owner := false,
) -> (root, external_owner: Value, shared_payload: ^payload) {
	switch variant {
	case .Array_Child, .Object_Value:
		shared, shared_error := array_value(allocator)
		testing.expect_value(t, array_error_kind(&shared_error), Array_Error.None)
		item := number_value(17)
		addition_append_take(t, &shared, &item)
		shared_payload = value_storage_of(&shared).owned_payload
		alias := clone_value(&shared)
		if keep_external_owner do external_owner = clone_value(&shared)

		if variant == .Array_Child {
			root_error: Array_Operation_Error
			root, root_error = array_value(allocator)
			testing.expect_value(t, array_error_kind(&root_error), Array_Error.None)
			addition_append_take(t, &root, &shared)
			addition_append_take(t, &root, &alias)
		} else {
			root_error: Object_Operation_Error
			root, root_error = object_value(allocator)
			testing.expect_value(t, object_error_kind(&root_error), Object_Error.None)
			first_key, first_key_error := string_value("first", allocator)
			second_key, second_key_error := string_value("second", allocator)
			testing.expect_value(t, constructor_error_kind(&first_key_error), Error.None)
			testing.expect_value(t, constructor_error_kind(&second_key_error), Error.None)
			addition_object_set_take(t, &root, &first_key, &shared)
			addition_object_set_take(t, &root, &second_key, &alias)
		}

	case .Object_Key:
		shared, shared_error := string_value("shared-key", allocator)
		testing.expect_value(t, constructor_error_kind(&shared_error), Error.None)
		shared_payload = value_storage_of(&shared).owned_payload
		alias := clone_value(&shared)
		if keep_external_owner do external_owner = clone_value(&shared)

		first, first_error := object_value(allocator)
		second, second_error := object_value(allocator)
		testing.expect_value(t, object_error_kind(&first_error), Object_Error.None)
		testing.expect_value(t, object_error_kind(&second_error), Object_Error.None)
		first_item := number_value(1)
		second_item := number_value(2)
		addition_object_set_take(t, &first, &shared, &first_item)
		addition_object_set_take(t, &second, &alias, &second_item)

		root_error: Array_Operation_Error
		root, root_error = array_value(allocator)
		testing.expect_value(t, array_error_kind(&root_error), Array_Error.None)
		addition_append_take(t, &root, &first)
		addition_append_take(t, &root, &second)
	}
	return
}

@(test)
value_add_rejects_reachable_payload_owner_undercount_before_result_allocation :: proc(
	t: ^testing.T,
) {
	variants := [?]addition_shared_owner_variant{.Array_Child, .Object_Key, .Object_Value}
	for variant in variants {
		source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
		root, external, shared_payload := addition_make_shared_owner_dag(
			t,
			variant,
			probe_allocator(&source_probe),
		)
		testing.expect_value(t, kind_of(&external), Kind.Invalid)
		testing.expect_value(t, shared_payload.references, 2)

		shared_payload.references = 1
		null := null_value()
		boolean := boolean_value(true)
		peers := [?]^Value{&null, &boolean}
		add_expect_malformed_matrix(t, &root, peers[:])
		testing.expect_value(t, shared_payload.references, 1)

		// Restore the true owner count before ordinary reference-counted teardown.
		shared_payload.references = 2
		testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&external), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&boolean), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
		testing.expect_value(t, source_probe.allocations, source_probe.frees)
		testing.expect_value(t, source_probe.live, 0)
		testing.expect(t, !source_probe.wrong_free_size)
	}
}

@(test)
value_add_accepts_exact_and_external_reachable_payload_owner_counts :: proc(t: ^testing.T) {
	variants := [?]addition_shared_owner_variant{.Array_Child, .Object_Key, .Object_Value}
	external_owner_cases := [?]bool{false, true}
	for variant in variants {
		for keep_external in external_owner_cases {
			source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
			root, external, shared_payload := addition_make_shared_owner_dag(
				t,
				variant,
				probe_allocator(&source_probe),
				keep_external,
			)
			expected_references := 2
			if keep_external do expected_references = 3
			testing.expect_value(t, shared_payload.references, expected_references)

			null := null_value()
			result := add_expect_success(t, &root, &null)
			testing.expect(t, values_equal(&result, &root))
			testing.expect_value(t, shared_payload.references, expected_references)
			testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
			testing.expect_value(t, shared_payload.references, expected_references)
			testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
			testing.expect_value(t, destroy_value(&external), runtime.Allocator_Error.None)
			testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
			testing.expect_value(t, source_probe.allocations, source_probe.frees)
			testing.expect_value(t, source_probe.live, 0)
			testing.expect(t, !source_probe.wrong_free_size)
		}
	}
}

@(test)
value_add_rejects_distinct_shallow_aliased_root_handles_before_result_allocation :: proc(
	t: ^testing.T,
) {
	kinds := [?]addition_root_payload_kind{.Array, .Object, .String}
	for kind in kinds {
		source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
		root := addition_make_root_payload(t, kind, probe_allocator(&source_probe))
		root_payload := value_storage_of(&root).owned_payload
		testing.expect_value(t, root_payload.references, 1)
		duplicate := root

		duplicate_on_left_cases := [?]bool{false, true}
		for duplicate_on_left in duplicate_on_left_cases {
			left, right := &root, &duplicate
			if duplicate_on_left do left, right = &duplicate, &root
			result_probe := allocator_probe{
				backing = context.allocator,
				fail_after = max(int),
			}
			result, err := value_add(left, right, probe_allocator(&result_probe))
			testing.expect_value(t, kind_of(&result), Kind.Invalid)
			testing.expect_value(
				t,
				value_add_error_kind(&err),
				Value_Add_Error_Kind.Invalid_Operand,
			)
			testing.expect_value(t, result_probe.allocations, 0)
			testing.expect_value(t, result_probe.frees, 0)
			testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
			testing.expect_value(t, root_payload.references, 1)
		}

		// Ordinary assignment did not retain. Neutralize the duplicate without
		// releasing the sole payload reference, then destroy the real owner once.
		duplicate = {}
		testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
		testing.expect_value(t, source_probe.allocations, source_probe.frees)
		testing.expect_value(t, source_probe.live, 0)
		testing.expect(t, !source_probe.wrong_free_size)
	}
}

@(test)
value_add_same_root_pointer_counts_one_borrowed_owner :: proc(t: ^testing.T) {
	kinds := [?]addition_root_payload_kind{.Array, .Object, .String}
	for kind in kinds {
		source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
		root := addition_make_root_payload(t, kind, probe_allocator(&source_probe))
		root_payload := value_storage_of(&root).owned_payload
		testing.expect_value(t, root_payload.references, 1)

		result := add_expect_success(t, &root, &root)
		testing.expect_value(t, kind_of(&result), kind_of(&root))
		testing.expect_value(t, root_payload.references, 1)
		testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
		testing.expect_value(t, root_payload.references, 1)
		testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
		testing.expect_value(t, source_probe.allocations, source_probe.frees)
		testing.expect_value(t, source_probe.live, 0)
		testing.expect(t, !source_probe.wrong_free_size)
	}
}

@(test)
value_add_distinct_cloned_root_handles_count_two_owners :: proc(t: ^testing.T) {
	kinds := [?]addition_root_payload_kind{.Array, .Object, .String}
	for kind in kinds {
		source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
		root := addition_make_root_payload(t, kind, probe_allocator(&source_probe))
		root_payload := value_storage_of(&root).owned_payload
		clone := clone_value(&root)
		testing.expect_value(t, root_payload.references, 2)

		result := add_expect_success(t, &root, &clone)
		testing.expect_value(t, kind_of(&result), kind_of(&root))
		testing.expect_value(t, root_payload.references, 2)
		testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
		testing.expect_value(t, root_payload.references, 2)
		testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
		testing.expect_value(t, root_payload.references, 1)
		testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
		testing.expect_value(t, source_probe.allocations, source_probe.frees)
		testing.expect_value(t, source_probe.live, 0)
		testing.expect(t, !source_probe.wrong_free_size)
	}
}

@(test)
value_add_validates_shared_payload_owners_jointly_between_operands :: proc(
	t: ^testing.T,
) {
	source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	allocator := probe_allocator(&source_probe)
	shared, shared_error := string_value("between-operands", allocator)
	testing.expect_value(t, constructor_error_kind(&shared_error), Error.None)
	shared_payload := value_storage_of(&shared).owned_payload
	alias := clone_value(&shared)
	left, left_error := array_value(allocator)
	right, right_error := array_value(allocator)
	testing.expect_value(t, array_error_kind(&left_error), Array_Error.None)
	testing.expect_value(t, array_error_kind(&right_error), Array_Error.None)
	addition_append_take(t, &left, &shared)
	addition_append_take(t, &right, &alias)
	testing.expect_value(t, shared_payload.references, 2)

	result := add_expect_success(t, &left, &right)
	testing.expect_value(t, shared_payload.references, 2)
	result_length, result_ok := array_length(&result)
	testing.expect(t, result_ok && result_length == 2)
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&left), runtime.Allocator_Error.None)
	testing.expect_value(t, shared_payload.references, 1)
	testing.expect_value(t, destroy_value(&right), runtime.Allocator_Error.None)
	testing.expect_value(t, source_probe.allocations, source_probe.frees)
	testing.expect_value(t, source_probe.live, 0)
	testing.expect(t, !source_probe.wrong_free_size)
}

@(test)
value_add_rejects_nested_malformed_metadata_before_dispatch_or_result_allocation :: proc(
	t: ^testing.T,
) {
	leaf, leaf_error := string_value("leaf", context.allocator)
	testing.expect_value(t, constructor_error_kind(&leaf_error), Error.None)
	leaf_payload := value_storage_of(&leaf).owned_payload
	shallow := wrap_array_take(t, &leaf, context.allocator)
	original_size := leaf_payload.allocation_size
	leaf_payload.allocation_size += 1
	null := null_value()
	boolean := boolean_value(true)
	peers := [?]^Value{&null, &boolean}
	add_expect_malformed_matrix(t, &shallow, peers[:])
	leaf_payload.allocation_size = original_size
	testing.expect_value(t, destroy_value(&shallow), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&boolean), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_deep_malformed_preflight_is_iterative_and_uses_independent_scratch :: proc(
	t: ^testing.T,
) {
	leaf, leaf_error := string_value("deep", context.allocator)
	testing.expect_value(t, constructor_error_kind(&leaf_error), Error.None)
	leaf_payload := value_storage_of(&leaf).owned_payload
	root := leaf
	for depth in 0..<4_000 {
		if depth & 1 == 0 {
			root = wrap_array_take(t, &root, context.allocator)
		} else {
			root = wrap_object_take(t, &root, context.allocator)
		}
	}
	original_size := leaf_payload.allocation_size
	leaf_payload.allocation_size += 1
	null := null_value()
	boolean := boolean_value(false)

	// This private entry point measures validation scratch separately from the
	// result allocator contract exercised below.
	scratch_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	validation_error := value_add_validate_operands_with_allocator(
		&root,
		&null,
		probe_allocator(&scratch_probe),
	)
	testing.expect_value(
		t,
		value_add_error_kind(&validation_error),
		Value_Add_Error_Kind.Invalid_Operand,
	)
	testing.expect(t, scratch_probe.allocations > 1)
	testing.expect_value(t, scratch_probe.allocations, scratch_probe.frees)
	testing.expect_value(t, scratch_probe.live, 0)
	testing.expect_value(
		t,
		destroy_value_add_error(&validation_error),
		runtime.Allocator_Error.None,
	)

	peers := [?]^Value{&null, &boolean}
	add_expect_malformed_matrix(t, &root, peers[:])
	leaf_payload.allocation_size = original_size
	testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&boolean), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_deep_shared_dag_is_valid_and_preserves_cow_operand_aliases :: proc(t: ^testing.T) {
	shared, shared_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&shared_error), Array_Error.None)
	item := number_value(17)
	displaced, append_error := array_append_take(&shared, &item)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	shared_payload := value_storage_of(&shared).owned_payload
	shared_alias := clone_value(&shared)
	dag_root, dag_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&dag_error), Array_Error.None)
	displaced, append_error = array_append_take(&dag_root, &shared)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	displaced, append_error = array_append_take(&dag_root, &shared_alias)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	testing.expect_value(t, shared_payload.references, 2)

	root := dag_root
	for depth in 0..<4_000 {
		if depth & 1 == 0 {
			root = wrap_array_take(t, &root, context.allocator)
		} else {
			root = wrap_object_take(t, &root, context.allocator)
		}
	}
	null := null_value()
	scratch_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	validation_error := value_add_validate_operands_with_allocator(
		&root,
		&null,
		probe_allocator(&scratch_probe),
	)
	testing.expect_value(t, value_add_error_kind(&validation_error), Value_Add_Error_Kind.None)
	testing.expect(t, scratch_probe.allocations > 1)
	// One fixed-capacity block serves each group of active frames/seen records.
	// Object keys are payload owners and therefore have seen records of their
	// own; shared completed payloads still do not retraverse descendants.
	testing.expect(t, scratch_probe.allocations <= 6_010 / VALUE_ADD_VALIDATION_BLOCK_CAPACITY + 2)
	testing.expect_value(t, scratch_probe.allocations, scratch_probe.frees)
	testing.expect_value(t, scratch_probe.live, 0)
	testing.expect_value(t, destroy_value_add_error(&validation_error), runtime.Allocator_Error.None)
	testing.expect_value(t, shared_payload.references, 2)

	result := add_expect_success(t, &null, &root)
	testing.expect_value(t, shared_payload.references, 2)
	cursor := clone_value(&result)
	for depth := 4_000 - 1; depth >= 0; depth -= 1 {
		child: Value
		found: bool
		if depth & 1 == 0 {
			child, found = array_element_copy(&cursor, 0)
		} else {
			child, found = object_get_copy(&cursor, "child")
		}
		testing.expect(t, found)
		testing.expect_value(t, destroy_value(&cursor), runtime.Allocator_Error.None)
		cursor = child
	}
	first, first_ok := array_element_copy(&cursor, 0)
	second, second_ok := array_element_copy(&cursor, 1)
	testing.expect(t, first_ok && second_ok && values_equal(&first, &second))
	testing.expect(t, value_storage_of(&first).owned_payload != shared_payload)
	testing.expect(t, value_storage_of(&second).owned_payload != shared_payload)
	testing.expect_value(t, array_number_at(t, &first, 0), 17)
	testing.expect_value(t, array_number_at(t, &second, 0), 17)
	testing.expect_value(t, destroy_value(&first), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&second), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&cursor), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
	testing.expect(t, kind_of(&result) == Kind.Array || kind_of(&result) == Kind.Object)
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_deep_reachable_payload_owner_undercount_is_iterative :: proc(t: ^testing.T) {
	root, external, shared_payload := addition_make_shared_owner_dag(
		t,
		.Array_Child,
		context.allocator,
	)
	testing.expect_value(t, kind_of(&external), Kind.Invalid)
	for depth in 0..<4_000 {
		if depth & 1 == 0 {
			root = wrap_array_take(t, &root, context.allocator)
		} else {
			root = wrap_object_take(t, &root, context.allocator)
		}
	}
	testing.expect_value(t, shared_payload.references, 2)
	shared_payload.references = 1

	null := null_value()
	scratch_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	validation_error := value_add_validate_operands_with_allocator(
		&root,
		&null,
		probe_allocator(&scratch_probe),
	)
	testing.expect_value(
		t,
		value_add_error_kind(&validation_error),
		Value_Add_Error_Kind.Invalid_Operand,
	)
	testing.expect(t, scratch_probe.allocations > 1)
	testing.expect(t, scratch_probe.allocations <= 6_020 / VALUE_ADD_VALIDATION_BLOCK_CAPACITY + 2)
	testing.expect_value(t, scratch_probe.allocations, scratch_probe.frees)
	testing.expect_value(t, scratch_probe.live, 0)
	testing.expect(t, !scratch_probe.wrong_free_size)
	testing.expect_value(
		t,
		destroy_value_add_error(&validation_error),
		runtime.Allocator_Error.None,
	)
	add_expect_preflight_kind_without_result_allocator(
		t,
		&root,
		&null,
		.Invalid_Operand,
	)
	testing.expect_value(t, shared_payload.references, 1)

	shared_payload.references = 2
	testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&external), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_rejects_duplicate_textual_object_keys_before_dispatch_or_allocation :: proc(
	t: ^testing.T,
) {
	object, object_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	add_object_put_value(t, &object, "first", number_value(1))
	add_object_put_value(t, &object, "second", number_value(2))
	p := value_storage_of(&object).owned_payload
	slots := object_payload_slots(p)
	original_second_key := take_value(&slots[1].key)
	duplicate_key, duplicate_error := string_value("first", context.allocator)
	testing.expect_value(t, constructor_error_kind(&duplicate_error), Error.None)
	slots[1].key = take_value(&duplicate_key)
	addition_rebuild_object_buckets(p)

	length, length_ok := object_length(&object)
	testing.expect(t, length_ok && length == 2)
	later, found := object_get_copy(&object, "first")
	later_number, later_ok := number_value_get(&later)
	testing.expect(t, found && later_ok && later_number == 2)
	testing.expect_value(t, destroy_value(&later), runtime.Allocator_Error.None)
	object_expect_order(t, &object, []string{"first", "first"})

	null := null_value()
	boolean := boolean_value(true)
	peers := [?]^Value{&null, &boolean}
	add_expect_malformed_matrix(t, &object, peers[:])

	malformed_key := take_value(&slots[1].key)
	slots[1].key = take_value(&original_second_key)
	addition_rebuild_object_buckets(p)
	testing.expect_value(t, destroy_value(&malformed_key), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&boolean), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_validation_scratch_failure_and_cleanup_are_retryable :: proc(t: ^testing.T) {
	root := null_value()
	for _ in 0..<64 do root = wrap_array_take(t, &root, context.allocator)
	null := null_value()
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = 1,
		free_failures_remaining = 1,
	}
	err := value_add_validate_operands_with_allocator(&root, &null, probe_allocator(&probe))
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, value_add_error_cause(&err), Value_Add_Error_Kind.Out_Of_Memory)
	testing.expect(t, value_add_error_needs_cleanup(&err))
	testing.expect_value(t, probe.allocations, 2)
	testing.expect_value(t, probe.live, 1)
	testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 2)
	testing.expect_value(t, probe.live, 0)
	testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_joint_validation_second_operand_scratch_failure_is_retryable :: proc(
	t: ^testing.T,
) {
	left := null_value()
	right := null_value()
	for _ in 0..<64 {
		left = wrap_array_take(t, &left, context.allocator)
		right = wrap_array_take(t, &right, context.allocator)
	}
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = 2,
		free_failures_remaining = 1,
	}

	// The first traversal fills one block's frames and seen entries and uses a
	// second block for its inline leaf. The retained seen state makes the third
	// allocation occur while traversing the distinct right operand.
	err := value_add_validate_operands_with_allocator(&left, &right, probe_allocator(&probe))
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, value_add_error_cause(&err), Value_Add_Error_Kind.Out_Of_Memory)
	testing.expect(t, value_add_error_needs_cleanup(&err))
	testing.expect_value(t, probe.allocations, 3)
	testing.expect_value(t, probe.live, 2)
	testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 3)
	testing.expect_value(t, probe.live, 0)
	testing.expect(t, !probe.wrong_free_size)
	testing.expect_value(t, destroy_value(&left), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&right), runtime.Allocator_Error.None)
}

@(test)
value_add_validation_scratch_allocation_and_retirement_fault_matrix :: proc(t: ^testing.T) {
	root := null_value()
	for _ in 0..<64 do root = wrap_array_take(t, &root, context.allocator)
	null := null_value()

	allocation_failures := [?]struct {
		allocator_error: runtime.Allocator_Error,
		expected:        Value_Add_Error_Kind,
	}{
		{.Out_Of_Memory, .Out_Of_Memory},
		{.Mode_Not_Implemented, .Allocator_Unsupported},
	}
	for test_case in allocation_failures {
		probe := allocator_probe{
			backing = context.allocator,
			fail_after = 0,
			failure_error = test_case.allocator_error,
		}
		err := value_add_validate_operands_with_allocator(&root, &null, probe_allocator(&probe))
		testing.expect_value(t, value_add_error_kind(&err), test_case.expected)
		testing.expect(t, !value_add_error_needs_cleanup(&err))
		testing.expect_value(t, probe.allocations, 1)
		testing.expect_value(t, probe.frees, 0)
		testing.expect_value(t, probe.live, 0)
		testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	}

	short_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
		free_failures_remaining = 1,
	}
	short_error := value_add_validate_operands_with_allocator(
		&root,
		&null,
		probe_allocator(&short_probe),
	)
	testing.expect_value(t, value_add_error_kind(&short_error), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, value_add_error_cause(&short_error), Value_Add_Error_Kind.Out_Of_Memory)
	testing.expect(t, value_add_error_needs_cleanup(&short_error))
	testing.expect_value(t, short_probe.allocations, 1)
	testing.expect_value(t, short_probe.live, 1)
	testing.expect_value(t, destroy_value_add_error(&short_error), runtime.Allocator_Error.None)
	testing.expect_value(t, short_probe.frees, 2)
	testing.expect_value(t, short_probe.live, 0)
	testing.expect(t, !short_probe.wrong_free_size)

	retirement_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 2,
	}
	retirement_error := value_add_validate_operands_with_allocator(
		&root,
		&null,
		probe_allocator(&retirement_probe),
	)
	testing.expect_value(
		t,
		value_add_error_kind(&retirement_error),
		Value_Add_Error_Kind.Cleanup_Failed,
	)
	testing.expect_value(t, value_add_error_cause(&retirement_error), Value_Add_Error_Kind.None)
	testing.expect(t, value_add_error_needs_cleanup(&retirement_error))
	cleanup_error := destroy_value_add_error(&retirement_error)
	testing.expect_value(t, cleanup_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect(t, value_add_error_needs_cleanup(&retirement_error))
	testing.expect_value(
		t,
		destroy_value_add_error(&retirement_error),
		runtime.Allocator_Error.None,
	)
	testing.expect_value(t, retirement_probe.live, 0)
	testing.expect(t, !retirement_probe.wrong_free_size)

	testing.expect_value(t, destroy_value(&root), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_invalid_operand_does_no_work_through_result_allocator :: proc(t: ^testing.T) {
	malformed, malformed_error := string_value("malformed", context.allocator)
	testing.expect_value(t, constructor_error_kind(&malformed_error), Error.None)
	p := value_storage_of(&malformed).owned_payload
	original_size := p.allocation_size
	p.allocation_size += 1
	null := null_value()
	result_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		retired = true,
	}
	result, err := value_add(&malformed, &null, probe_allocator(&result_probe))
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Invalid_Operand)
	testing.expect(t, !result_probe.called_retired)
	testing.expect_value(t, result_probe.allocations, 0)
	testing.expect_value(t, result_probe.frees, 0)
	testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	p.allocation_size = original_size
	testing.expect_value(t, destroy_value(&malformed), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_rejects_finite_literal_without_coefficient_before_null_identity_allocation :: proc(
	t: ^testing.T,
) {
	source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	malformed, malformed_error := literal_number_value(
		"12.5",
		probe_allocator(&source_probe),
	)
	testing.expect_value(t, constructor_error_kind(&malformed_error), Error.None)
	testing.expect_value(t, source_probe.allocations, 1)
	testing.expect_value(t, source_probe.live, 1)

	p := value_storage_of(&malformed).owned_payload
	original_coefficient_len := p.coefficient_len
	testing.expect(t, original_coefficient_len > 0 && !p.infinite)
	p.coefficient_len = 0
	null := null_value()
	malformed_on_left := [?]bool{false, true}
	for on_left in malformed_on_left {
		left, right := &null, &malformed
		if on_left do left, right = &malformed, &null
		result_probe := allocator_probe{
			backing = context.allocator,
			fail_after = max(int),
			retired = true,
		}
		result, err := value_add(left, right, probe_allocator(&result_probe))
		testing.expect_value(t, kind_of(&result), Kind.Invalid)
		testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Invalid_Operand)
		testing.expect(t, !value_add_error_needs_cleanup(&err))
		testing.expect(t, !result_probe.called_retired)
		testing.expect_value(t, result_probe.allocations, 0)
		testing.expect_value(t, result_probe.frees, 0)
		testing.expect_value(t, result_probe.live, 0)
		testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	}

	p.coefficient_len = original_coefficient_len
	testing.expect_value(t, destroy_value(&malformed), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_constructor_error(&malformed_error), runtime.Allocator_Error.None)
	testing.expect_value(t, source_probe.frees, 1)
	testing.expect_value(t, source_probe.live, 0)
	testing.expect(t, !source_probe.wrong_free_size)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_rejects_sum_preserving_literal_partition_shifts_before_allocation :: proc(
	t: ^testing.T,
) {
	spellings := [?]string{
		"12.5",
		"-0.00",
		"1.2300e+4",
		"123456789012345678901234567890.00",
	}
	for spelling in spellings {
		source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
		malformed, constructor_error := literal_number_value(
			spelling,
			probe_allocator(&source_probe),
		)
		testing.expect_value(t, constructor_error_kind(&constructor_error), Error.None)
		testing.expect_value(t, source_probe.allocations, 1)
		testing.expect_value(t, source_probe.live, 1)

		null := null_value()
		native := number_value(2.5)
		boolean := boolean_value(true)
		text, text_error := string_value("peer", context.allocator)
		testing.expect_value(t, constructor_error_kind(&text_error), Error.None)
		peers := [?]^Value{&null, &native, &boolean, &text}
		p := value_storage_of(&malformed).owned_payload
		original_byte_count := p.byte_count
		original_coefficient_len := p.coefficient_len
		original_logical_size := int(size_of(payload)) +
			original_byte_count + original_coefficient_len
		shifts := [?]int{-1, 1}
		for shift in shifts {
			shifted_bytes := original_byte_count + shift
			shifted_coefficient := original_coefficient_len - shift
			if shifted_bytes < 0 || shifted_coefficient < 0 do continue
			p.byte_count = shifted_bytes
			p.coefficient_len = shifted_coefficient
			testing.expect_value(
				t,
				int(size_of(payload)) + p.byte_count + p.coefficient_len,
				original_logical_size,
			)
			testing.expect(t, !literal_storage_valid(value_storage_of(&malformed)))
			add_expect_malformed_matrix(t, &malformed, peers[:])
			p.byte_count = original_byte_count
			p.coefficient_len = original_coefficient_len
			testing.expect(t, literal_storage_valid(value_storage_of(&malformed)))
		}

		testing.expect_value(t, destroy_value(&text), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_constructor_error(&text_error), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&boolean), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&native), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&malformed), runtime.Allocator_Error.None)
		testing.expect_value(
			t,
			destroy_constructor_error(&constructor_error),
			runtime.Allocator_Error.None,
		)
		testing.expect_value(t, source_probe.frees, 1)
		testing.expect_value(t, source_probe.live, 0)
		testing.expect(t, !source_probe.wrong_free_size)
	}
}

@(test)
value_add_rejects_literal_semantic_metadata_and_byte_disagreement :: proc(t: ^testing.T) {
	malformed, constructor_error := literal_number_value("+12.5e2", context.allocator)
	testing.expect_value(t, constructor_error_kind(&constructor_error), Error.None)
	null := null_value()
	native := number_value(1)
	boolean := boolean_value(false)
	peers := [?]^Value{&null, &native, &boolean}
	storage := value_storage_of(&malformed)
	p := storage.owned_payload

	spelling := payload_bytes(p)
	original_spelling_byte := spelling[1]
	spelling[1] = '9'
	add_expect_malformed_matrix(t, &malformed, peers[:])
	spelling[1] = original_spelling_byte

	coefficient := payload_coefficient(p)
	original_coefficient_byte := coefficient[1]
	coefficient[1] = 'x'
	add_expect_malformed_matrix(t, &malformed, peers[:])
	coefficient[1] = original_coefficient_byte

	original_negative := p.negative
	p.negative = !p.negative
	add_expect_malformed_matrix(t, &malformed, peers[:])
	p.negative = original_negative

	original_positive_sign := p.explicit_positive_sign
	p.explicit_positive_sign = !p.explicit_positive_sign
	add_expect_malformed_matrix(t, &malformed, peers[:])
	p.explicit_positive_sign = original_positive_sign

	original_exponent := p.exponent
	invalid_exponents := [?]i64{original_exponent + 1, min(i64), max(i64)}
	for invalid_exponent in invalid_exponents {
		p.exponent = invalid_exponent
		add_expect_malformed_matrix(t, &malformed, peers[:])
	}
	p.exponent = original_exponent

	original_infinite := p.infinite
	p.infinite = true
	add_expect_malformed_matrix(t, &malformed, peers[:])
	p.infinite = original_infinite

	original_cache := p.native_cache
	p.native_cache = toggle_f64_sign(p.native_cache)
	add_expect_malformed_matrix(t, &malformed, peers[:])
	p.native_cache = original_cache

	testing.expect(t, literal_storage_valid(storage))
	spelling_after, spelling_ok := literal_spelling_borrowed(&malformed)
	testing.expect(t, spelling_ok && spelling_after == "+12.5e2")
	testing.expect_value(t, destroy_value(&boolean), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&native), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&malformed), runtime.Allocator_Error.None)
	testing.expect_value(
		t,
		destroy_constructor_error(&constructor_error),
		runtime.Allocator_Error.None,
	)
}

@(test)
literal_storage_invariant_retains_finite_zero_and_infinite_representations :: proc(t: ^testing.T) {
	finite_zero_spellings := [?]string{"0", "-0.00", "0e999999999", "-0e-1147483647"}
	for spelling in finite_zero_spellings {
		value, err := literal_number_value(spelling, context.allocator)
		testing.expect_value(t, constructor_error_kind(&err), Error.None)
		storage := value_storage_of(&value)
		p := storage.owned_payload
		testing.expect(t, p != nil && !p.infinite && p.coefficient_len == 1)
		testing.expect(t, literal_storage_valid(storage))
		kind, kind_ok := number_kind(&value)
		testing.expect(t, kind_ok && kind == .Literal)
		testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_constructor_error(&err), runtime.Allocator_Error.None)
	}

	infinite_spellings := [?]string{"Infinity", "-Inf", "1e1000000000"}
	for spelling in infinite_spellings {
		value, err := literal_number_value(spelling, context.allocator)
		testing.expect_value(t, constructor_error_kind(&err), Error.None)
		storage := value_storage_of(&value)
		p := storage.owned_payload
		testing.expect(t, p != nil && p.infinite && p.coefficient_len == 0)
		coefficient_capacity := storage.payload_allocation_bound -
			int(size_of(payload)) - p.byte_count
		if spelling == "1e1000000000" {
			testing.expect(t, coefficient_capacity > 0)
		} else {
			testing.expect_value(t, coefficient_capacity, 0)
		}
		testing.expect(t, literal_storage_valid(storage))
		kind, kind_ok := number_kind(&value)
		testing.expect(t, kind_ok && kind == .Literal)
		testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_constructor_error(&err), runtime.Allocator_Error.None)
	}
}

@(private)
addition_expect_literal_clone :: proc(t: ^testing.T, result, source: ^Value) {
	result_storage := value_storage_of(result)
	source_storage := value_storage_of(source)
	result_payload := result_storage.owned_payload
	source_payload := source_storage.owned_payload
	result_capacity := result_storage.payload_allocation_bound -
		int(size_of(payload)) - result_payload.byte_count
	source_capacity := source_storage.payload_allocation_bound -
		int(size_of(payload)) - source_payload.byte_count
	testing.expect(t, result_payload != source_payload)
	testing.expect(t, literal_storage_valid(result_storage))
	testing.expect_value(t, result_storage.payload_allocation_bound, source_storage.payload_allocation_bound)
	testing.expect_value(t, result_capacity, source_capacity)
	testing.expect_value(t, result_payload.coefficient_len, source_payload.coefficient_len)
	testing.expect(
		t,
		string(literal_coefficient_capacity_borrowed(result_payload, result_capacity)) ==
			string(literal_coefficient_capacity_borrowed(source_payload, source_capacity)),
	)
	result_kind, result_kind_ok := number_kind(result)
	result_number, result_number_ok := number_value_get(result)
	source_number, source_number_ok := number_value_get(source)
	result_spelling, result_spelling_ok := literal_spelling_borrowed(result)
	source_spelling, source_spelling_ok := literal_spelling_borrowed(source)
	testing.expect(t, result_kind_ok && result_kind == .Literal)
	testing.expect(t, result_number_ok && source_number_ok)
	testing.expect_value(t, transmute(u64)result_number, transmute(u64)source_number)
	testing.expect(
		t,
		result_spelling_ok && source_spelling_ok && result_spelling == source_spelling,
	)
}

@(test)
value_add_null_identity_clones_every_valid_literal_capacity_exactly :: proc(t: ^testing.T) {
	spellings := [?]string{
		"1e1000000000",
		"-1e1000000000",
		"Infinity",
		"-Inf",
		"0",
		"-0.00",
		"12.5",
		"9e999999999",
		"1e-1147483647",
	}
	for spelling in spellings {
		source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
		source, constructor_error := literal_number_value(
			spelling,
			probe_allocator(&source_probe),
		)
		testing.expect_value(t, constructor_error_kind(&constructor_error), Error.None)
		testing.expect_value(t, source_probe.allocations, 1)
		testing.expect_value(t, source_probe.live, 1)
		null := null_value()
		operand_orders := [?]bool{false, true}
		for source_on_left in operand_orders {
			left, right := &null, &source
			if source_on_left do left, right = &source, &null
			result_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
			result, err := value_add(left, right, probe_allocator(&result_probe))
			testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.None)
			testing.expect_value(t, result_probe.allocations, 1)
			testing.expect_value(t, result_probe.live, 1)
			addition_expect_literal_clone(t, &result, &source)
			testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
			testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
			testing.expect_value(t, result_probe.frees, 1)
			testing.expect_value(t, result_probe.live, 0)
			testing.expect(t, !result_probe.wrong_free_size)
		}
		testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_constructor_error(&constructor_error), runtime.Allocator_Error.None)
		testing.expect_value(t, source_probe.frees, 1)
		testing.expect_value(t, source_probe.live, 0)
		testing.expect(t, !source_probe.wrong_free_size)
	}
}

@(test)
value_add_clones_overflowed_literal_through_array_slice_and_object_paths :: proc(t: ^testing.T) {
	overflow, overflow_error := literal_number_value("1e1000000000", context.allocator)
	testing.expect_value(t, constructor_error_kind(&overflow_error), Error.None)

	array, array_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&array_error), Array_Error.None)
	prefix := number_value(7)
	displaced, append_error := array_append_take(&array, &prefix)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	overflow_for_array := clone_value(&overflow)
	displaced, append_error = array_append_take(&array, &overflow_for_array)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	slice, slice_error := array_slice(&array, 1, 2, context.allocator)
	testing.expect_value(t, array_error_kind(&slice_error), Array_Error.None)
	empty_array, empty_array_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&empty_array_error), Array_Error.None)
	array_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	array_result, array_add_error := value_add(
		&slice,
		&empty_array,
		probe_allocator(&array_probe),
	)
	testing.expect_value(t, value_add_error_kind(&array_add_error), Value_Add_Error_Kind.None)
	array_child, array_child_ok := array_element_copy(&array_result, 0)
	testing.expect(t, array_child_ok)
	addition_expect_literal_clone(t, &array_child, &overflow)
	testing.expect_value(t, destroy_value(&array_child), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&array_result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value_add_error(&array_add_error), runtime.Allocator_Error.None)
	testing.expect_value(t, array_probe.live, 0)
	testing.expect(t, !array_probe.wrong_free_size)

	object, object_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	add_object_put_value(t, &object, "overflow", clone_value(&overflow))
	empty_object, empty_object_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&empty_object_error), Object_Error.None)
	object_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	object_result, object_add_error := value_add(
		&object,
		&empty_object,
		probe_allocator(&object_probe),
	)
	testing.expect_value(t, value_add_error_kind(&object_add_error), Value_Add_Error_Kind.None)
	object_child, object_child_ok := object_get_copy(&object_result, "overflow")
	testing.expect(t, object_child_ok)
	addition_expect_literal_clone(t, &object_child, &overflow)
	testing.expect_value(t, destroy_value(&object_child), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&object_result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value_add_error(&object_add_error), runtime.Allocator_Error.None)
	testing.expect_value(t, object_probe.live, 0)
	testing.expect(t, !object_probe.wrong_free_size)

	owned_values := [?]^Value{&empty_object, &object, &empty_array, &slice, &array, &overflow}
	for value in owned_values {
		testing.expect_value(t, destroy_value(value), runtime.Allocator_Error.None)
	}
	testing.expect_value(t, destroy_constructor_error(&overflow_error), runtime.Allocator_Error.None)
}

@(test)
value_add_rejects_corrupt_overflowed_literal_tail_before_result_allocation :: proc(t: ^testing.T) {
	source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	source, constructor_error := literal_number_value(
		"1e1000000000",
		probe_allocator(&source_probe),
	)
	testing.expect_value(t, constructor_error_kind(&constructor_error), Error.None)
	storage := value_storage_of(&source)
	p := storage.owned_payload
	capacity := storage.payload_allocation_bound - int(size_of(payload)) - p.byte_count
	testing.expect(t, p.infinite && p.coefficient_len == 0 && capacity > 0)
	coefficient := literal_coefficient_capacity_borrowed(p, capacity)
	original := coefficient[0]
	coefficient[0] = 'x'
	null := null_value()
	add_expect_preflight_kind_without_result_allocator(t, &source, &null, .Invalid_Operand)
	coefficient[0] = original
	testing.expect(t, literal_storage_valid(storage))
	addition_result := add_expect_success(t, &null, &source)
	addition_expect_literal_clone(t, &addition_result, &source)
	testing.expect_value(t, destroy_value(&addition_result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_constructor_error(&constructor_error), runtime.Allocator_Error.None)
	testing.expect_value(t, source_probe.frees, 1)
	testing.expect_value(t, source_probe.live, 0)
	testing.expect(t, !source_probe.wrong_free_size)
}

@(private)
empty_slot_boundary :: enum {
	Live_Value,
	Hash,
	Link,
}

@(test)
value_add_rejects_empty_object_slot_with_hidden_owner_on_both_sides :: proc(t: ^testing.T) {
	operand_sides := [?]bool{true, false}
	for malformed_on_left in operand_sides {
		source_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
		object, object_error := object_value(probe_allocator(&source_probe))
		testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
		hidden, hidden_error := string_value("hidden", probe_allocator(&source_probe))
		testing.expect_value(t, constructor_error_kind(&hidden_error), Error.None)
		p := value_storage_of(&object).owned_payload
		p.object_next_free = 1
		slot := &object_payload_slots(p)[0]
		slot.value = take_value(&hidden)
		testing.expect_value(t, source_probe.live, 2)

		null := null_value()
		left, right := &null, &object
		if malformed_on_left do left, right = &object, &null
		result_probe := allocator_probe{
			backing = context.allocator,
			fail_after = max(int),
			retired = true,
		}
		result, err := value_add(left, right, probe_allocator(&result_probe))
		testing.expect_value(t, kind_of(&result), Kind.Invalid)
		testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Invalid_Operand)
		testing.expect(t, !result_probe.called_retired)
		testing.expect_value(t, result_probe.allocations, 0)
		testing.expect_value(t, result_probe.frees, 0)
		testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.None)
		testing.expect_value(t, source_probe.live, 0)
		testing.expect(t, !source_probe.wrong_free_size)
	}
}

@(test)
value_add_rejects_each_noncanonical_empty_slot_field_without_result_allocation :: proc(
	t: ^testing.T,
) {
	boundaries := [?]empty_slot_boundary{.Live_Value, .Hash, .Link}
	for boundary in boundaries {
		object, object_error := object_value(context.allocator)
		testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
		p := value_storage_of(&object).owned_payload
		p.object_next_free = 1
		slot := &object_payload_slots(p)[0]
		switch boundary {
		case .Live_Value:
			slot.value = number_value(1)
		case .Hash:
			slot.hash = 1
		case .Link:
			slot.next = 0
		}
		null := null_value()
		add_expect_preflight_kind_without_result_allocator(
			t, &object, &null, .Invalid_Operand,
		)

		// These cases test preflight only. Restore the canonical hole before
		// ordinary teardown so no deliberately malformed state escapes the test.
		testing.expect_value(t, destroy_value(&slot.value), runtime.Allocator_Error.None)
		object_slot_set_empty(slot)
		testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.None)
	}
}

@(test)
malformed_empty_object_slot_cleanup_scans_unused_extent_and_retries :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	object, object_error := object_value(probe_allocator(&probe))
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	hidden, hidden_error := string_value("unused", probe_allocator(&probe))
	testing.expect_value(t, constructor_error_kind(&hidden_error), Error.None)
	p := value_storage_of(&object).owned_payload
	object_payload_slots(p)[p.object_next_free + 1].value = take_value(&hidden)
	testing.expect_value(t, probe.live, 2)

	null := null_value()
	add_expect_preflight_kind_without_result_allocator(t, &object, &null, .Invalid_Operand)
	probe.free_failures_remaining = 1
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, probe.live, 2)
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	testing.expect(t, !probe.wrong_free_size)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_rejects_cyclic_container_graph_without_mutating_borrowed_scratch :: proc(t: ^testing.T) {
	array, array_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&array_error), Array_Error.None)
	child := null_value()
	displaced, append_error := array_append_take(&array, &child)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	slot := &array_payload_values(value_storage_of(&array).owned_payload)[0]
	original_child := take_value(slot)
	slot^ = clone_value(&array)
	null := null_value()
	peers := [?]^Value{&null}
	add_expect_malformed_matrix(t, &array, peers[:])
	cycle_owner := take_value(slot)
	slot^ = take_value(&original_child)
	testing.expect_value(t, destroy_value(&cycle_owner), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_checked_size_helpers_reject_real_overflow_without_allocation :: proc(t: ^testing.T) {
	array_size, array_size_ok := array_allocation_size(ARRAY_INITIAL_CAPACITY)
	testing.expect(t, array_size_ok && array_size > int(size_of(payload)))
	array_capacity, array_capacity_ok := value_add_array_capacity(0)
	testing.expect(t, array_capacity_ok && array_capacity == ARRAY_INITIAL_CAPACITY)
	_, array_negative_ok := value_add_array_capacity(-1)
	testing.expect(t, !array_negative_ok)

	object_size, object_size_ok := object_allocation_size(OBJECT_INITIAL_CAPACITY)
	testing.expect(t, object_size_ok && object_size > int(size_of(payload)))
	object_capacity, object_capacity_ok := value_add_object_capacity(OBJECT_INITIAL_CAPACITY + 1)
	testing.expect(t, object_capacity_ok && object_capacity == OBJECT_INITIAL_CAPACITY * 2)
	_, object_overflow_ok := value_add_object_capacity(max(int))
	testing.expect(t, !object_overflow_ok)

	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	array, array_error := value_add_allocate_array(max(int), probe_allocator(&probe))
	testing.expect_value(t, kind_of(&array), Kind.Invalid)
	testing.expect_value(t, value_add_error_kind(&array_error), Value_Add_Error_Kind.Size_Overflow)
	testing.expect_value(t, probe.allocations, 0)
	testing.expect_value(t, destroy_value_add_error(&array_error), runtime.Allocator_Error.None)

	payload_result, constructor_error := allocate_payload(
		.String, max(int), 0, probe_allocator(&probe),
	)
	testing.expect(t, payload_result == nil)
	testing.expect_value(t, constructor_error_kind(&constructor_error), Error.Size_Overflow)
	testing.expect_value(t, probe.allocations, 0)
	testing.expect_value(t, destroy_constructor_error(&constructor_error), runtime.Allocator_Error.None)
}

@(test)
value_add_accepts_real_offset_overflow_slice_with_small_capacity :: proc(t: ^testing.T) {
	source, source_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&source_error), Array_Error.None)
	for i in 0..<65_537 {
		item := number_value(f64(i))
		append_error := append_take_no_displaced(&source, &item)
		testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	}
	slice, slice_error := array_slice(&source, 65_536, 65_537, context.allocator)
	testing.expect_value(t, array_error_kind(&slice_error), Array_Error.None)
	slice_storage := value_storage_of(&slice)
	testing.expect_value(t, slice_storage.array_length, 1)
	testing.expect_value(t, slice_storage.owned_payload.array_capacity, 1)
	testing.expect_value(t, array_number_at(t, &slice, 0), 65_536)

	null := null_value()
	left_identity := add_expect_success(t, &null, &slice)
	right_identity := add_expect_success(t, &slice, &null)
	tail := addition_singleton_array(t)
	concatenated := add_expect_success(t, &slice, &tail)
	result_payloads := [?]^payload{
		value_storage_of(&left_identity).owned_payload,
		value_storage_of(&right_identity).owned_payload,
		value_storage_of(&concatenated).owned_payload,
	}
	testing.expect(t, result_payloads[0] != slice_storage.owned_payload)
	testing.expect(t, result_payloads[1] != slice_storage.owned_payload)
	testing.expect(t, result_payloads[2] != slice_storage.owned_payload)
	testing.expect(t, result_payloads[0] != result_payloads[1])
	testing.expect(t, result_payloads[0] != result_payloads[2])
	testing.expect(t, result_payloads[1] != result_payloads[2])
	source_length, source_ok := array_length(&source)
	slice_length, slice_ok := array_length(&slice)
	tail_length, tail_ok := array_length(&tail)
	testing.expect(t, source_ok && source_length == 65_537)
	testing.expect(t, slice_ok && slice_length == 1)
	testing.expect(t, tail_ok && tail_length == 1)

	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&slice), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&tail), runtime.Allocator_Error.None)
	testing.expect_value(t, array_number_at(t, &left_identity, 0), 65_536)
	testing.expect_value(t, array_number_at(t, &right_identity, 0), 65_536)
	concatenated_length, concatenated_ok := array_length(&concatenated)
	testing.expect(t, concatenated_ok && concatenated_length == 2)
	testing.expect_value(t, array_number_at(t, &concatenated, 0), 65_536)
	testing.expect_value(t, array_number_at(t, &concatenated, 1), 1)
	testing.expect_value(t, destroy_value(&left_identity), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&right_identity), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&concatenated), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_scalar_allocator_modes_and_cleanup_remain_distinct :: proc(t: ^testing.T) {
	null := null_value()
	left_string, left_error := string_value("left", context.allocator)
	right_string, right_error := string_value("right", context.allocator)
	literal, literal_error := literal_number_value("1.25", context.allocator)
	testing.expect_value(t, constructor_error_kind(&left_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&right_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&literal_error), Error.None)

	operations := [?]struct {left, right: ^Value}{
		{&left_string, &right_string},
		{&null, &left_string},
		{&left_string, &null},
		{&null, &literal},
		{&literal, &null},
	}
	allocation_failures := [?]struct {
		allocator_error: runtime.Allocator_Error,
		expected:        Value_Add_Error_Kind,
	}{
		{.Mode_Not_Implemented, .Allocator_Unsupported},
		{.Out_Of_Memory, .Out_Of_Memory},
	}
	for failure in allocation_failures {
		for operation in operations {
			probe := allocator_probe{
				backing = context.allocator,
				fail_after = 0,
				failure_error = failure.allocator_error,
			}
			result, err := value_add(
				operation.left,
				operation.right,
				probe_allocator(&probe),
			)
			testing.expect_value(t, kind_of(&result), Kind.Invalid)
			testing.expect_value(t, value_add_error_kind(&err), failure.expected)
			testing.expect(t, !value_add_error_needs_cleanup(&err))
			testing.expect_value(t, probe.allocations, 1)
			testing.expect_value(t, probe.frees, 0)
			testing.expect_value(t, probe.live, 0)
			testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
		}
	}

	short_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
	}
	result, short_error := value_add(
		&left_string,
		&right_string,
		probe_allocator(&short_probe),
	)
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect_value(t, value_add_error_kind(&short_error), Value_Add_Error_Kind.Out_Of_Memory)
	testing.expect(t, !value_add_error_needs_cleanup(&short_error))
	testing.expect_value(t, short_probe.frees, 1)
	testing.expect_value(t, short_probe.live, 0)
	testing.expect(t, !short_probe.wrong_free_size)
	testing.expect_value(t, destroy_value_add_error(&short_error), runtime.Allocator_Error.None)

	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
		free_failures_remaining = 2,
	}
	retry_error: Value_Add_Error
	result, retry_error = value_add(
		&null,
		&literal,
		probe_allocator(&retry_probe),
	)
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect_value(t, value_add_error_kind(&retry_error), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, value_add_error_cause(&retry_error), Value_Add_Error_Kind.Out_Of_Memory)
	testing.expect(t, value_add_error_needs_cleanup(&retry_error))
	testing.expect_value(
		t,
		destroy_value_add_error(&retry_error),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect_value(t, value_add_error_kind(&retry_error), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect(t, value_add_error_needs_cleanup(&retry_error))
	testing.expect_value(t, destroy_value_add_error(&retry_error), runtime.Allocator_Error.None)
	testing.expect_value(t, retry_probe.live, 0)
	testing.expect(t, !retry_probe.wrong_free_size)

	left_text, left_ok := string_borrowed(&left_string)
	right_text, right_ok := string_borrowed(&right_string)
	literal_text, literal_ok := literal_spelling_borrowed(&literal)
	testing.expect(t, left_ok && left_text == "left")
	testing.expect(t, right_ok && right_text == "right")
	testing.expect(t, literal_ok && literal_text == "1.25")
	testing.expect_value(t, destroy_value(&literal), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&right_string), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&left_string), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_arrays_deep_clone_alias_and_lifetime_independence :: proc(t: ^testing.T) {
	nested_string, nested_error := string_value("owned", context.allocator)
	testing.expect_value(t, constructor_error_kind(&nested_error), Error.None)
	nested_object, object_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	add_object_put_value(t, &nested_object, "s", nested_string)
	array := add_array_of_two(t, number_value(1), nested_object)
	result := add_expect_success(t, &array, &array)
	length, length_ok := array_length(&result)
	testing.expect(t, length_ok && length == 4)
	testing.expect(t, value_storage_of(&result).owned_payload != value_storage_of(&array).owned_payload)
	nested_indices := [?]int{1, 3}
	for index in nested_indices {
		child, child_ok := array_element_copy(&result, index)
		source_child, source_ok := array_element_copy(&array, 1)
		testing.expect(t, child_ok && source_ok && values_equal(&child, &source_child))
		testing.expect(t, value_storage_of(&child).owned_payload != value_storage_of(&source_child).owned_payload)
		testing.expect_value(t, destroy_value(&child), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&source_child), runtime.Allocator_Error.None)
	}
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	result_length, result_ok := array_length(&result)
	testing.expect(t, result_ok && result_length == 4)
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)

	left := add_array_of_two(t, number_value(7), number_value(8))
	right := add_array_of_two(t, number_value(9), number_value(10))
	combined := add_expect_success(t, &left, &right)
	testing.expect_value(t, destroy_value(&combined), runtime.Allocator_Error.None)
	left_length, left_ok := array_length(&left)
	right_length, right_ok := array_length(&right)
	testing.expect(t, left_ok && left_length == 2)
	testing.expect(t, right_ok && right_length == 2)
	testing.expect_value(t, destroy_value(&left), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&right), runtime.Allocator_Error.None)
}

@(test)
value_add_objects_use_right_values_and_exact_jq_key_order :: proc(t: ^testing.T) {
	left, left_error := object_value(context.allocator)
	right, right_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&left_error), Object_Error.None)
	testing.expect_value(t, object_error_kind(&right_error), Object_Error.None)
	object_put_number(t, &left, "a", 1)
	object_put_number(t, &left, "b", 2)
	object_put_number(t, &left, "c", 3)
	object_delete_expected(t, &left, "b")
	object_put_number(t, &left, "d", 4)
	object_put_number(t, &right, "b", 5)
	object_put_number(t, &right, "a", 6)
	object_put_number(t, &right, "e", 7)
	result := add_expect_success(t, &left, &right)
	object_expect_order(t, &result, []string{"a", "c", "d", "b", "e"})
	keys := [?]string{"a", "b", "c", "d", "e"}
	expected_values := [?]f64{6, 5, 3, 4, 7}
	for key, index in keys {
		expected := expected_values[index]
		item, ok := object_get_copy(&result, key)
		number, number_ok := number_value_get(&item)
		testing.expect(t, ok && number_ok && number == expected)
		testing.expect_value(t, destroy_value(&item), runtime.Allocator_Error.None)
	}
	result_length, result_ok := object_length(&result)
	testing.expect(t, result_ok && result_length == 5)
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)

	same_owner := add_expect_success(t, &left, &left)
	object_expect_order(t, &same_owner, []string{"a", "c", "d"})
	testing.expect(t, values_equal(&same_owner, &left))
	testing.expect_value(t, destroy_value(&left), runtime.Allocator_Error.None)
	same_owner_length, same_owner_ok := object_length(&same_owner)
	testing.expect(t, same_owner_ok && same_owner_length == 3)
	testing.expect_value(t, destroy_value(&same_owner), runtime.Allocator_Error.None)
	right_length, right_ok := object_length(&right)
	testing.expect(t, right_ok && right_length == 3)
	testing.expect_value(t, destroy_value(&right), runtime.Allocator_Error.None)
}

@(test)
value_add_iterative_object_clone_attaches_each_slot_once :: proc(t: ^testing.T) {
	first_leaf := number_value(1)
	first_nested := wrap_array_take(t, &first_leaf, context.allocator)
	first_nested = wrap_object_take(t, &first_nested, context.allocator)
	second_leaf := number_value(2)
	second_nested := wrap_object_take(t, &second_leaf, context.allocator)
	second_nested = wrap_array_take(t, &second_nested, context.allocator)

	source, source_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&source_error), Object_Error.None)
	add_object_put_value(t, &source, "first", first_nested)
	add_object_put_value(t, &source, "hole", number_value(0))
	add_object_put_value(t, &source, "second", second_nested)
	add_object_put_value(t, &source, "third", number_value(3))
	object_delete_expected(t, &source, "hole")
	testing.expect_value(t, value_storage_of(&source).owned_payload.object_next_free, 4)

	null := null_value()
	result := add_expect_success(t, &null, &source)
	object_expect_order(t, &result, []string{"first", "second", "third"})
	result_payload := value_storage_of(&result).owned_payload
	testing.expect_value(t, result_payload.object_next_free, 3)
	testing.expect_value(t, result_payload.object_length, 3)
	testing.expect(t, values_equal(&result, &source))

	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	object_expect_order(t, &result, []string{"first", "second", "third"})
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_preserves_number_add_nan_infinity_and_signed_zero_contract :: proc(t: ^testing.T) {
	negative_zero := number_value(-0.0)
	positive_zero := number_value(0.0)
	negative_sum := add_expect_success(t, &negative_zero, &negative_zero)
	mixed_sum := add_expect_success(t, &negative_zero, &positive_zero)
	negative_number, _ := number_value_get(&negative_sum)
	mixed_number, _ := number_value_get(&mixed_sum)
	testing.expect(t, transmute(u64)negative_number >> 63 == 1)
	testing.expect(t, transmute(u64)mixed_number >> 63 == 0)
	positive_nan := number_value(transmute(f64)u64(0x7ff8000000000042))
	negative_nan := number_value(transmute(f64)u64(0xfff8000000000099))
	nan_sum := add_expect_success(t, &positive_nan, &negative_nan)
	nan_number, _ := number_value_get(&nan_sum)
	testing.expect_value(t, transmute(u64)nan_number, u64(0xfff8000000000099))
	positive_infinity := number_value(math.inf_f64(1))
	negative_infinity := number_value(math.inf_f64(-1))
	infinity_sum := add_expect_success(t, &positive_infinity, &negative_infinity)
	infinity_number, _ := number_value_get(&infinity_sum)
	testing.expect(t, math.is_nan(infinity_number))
	results := [?]^Value{&infinity_sum, &nan_sum, &mixed_sum, &negative_sum}
	for value in results {
		testing.expect_value(t, destroy_value(value), runtime.Allocator_Error.None)
	}
}

@(private)
addition_fault_operand :: proc(t: ^testing.T) -> Value {
	inner_array := add_array_of_two(t, number_value(2), number_value(3))
	inner_object, object_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	add_object_put_value(t, &inner_object, "nested", inner_array)
	text, text_error := string_value("bytes", context.allocator)
	testing.expect_value(t, constructor_error_kind(&text_error), Error.None)
	return add_array_of_two(t, inner_object, text)
}

@(test)
value_add_exhausts_every_allocation_boundary_and_retry_is_safe :: proc(t: ^testing.T) {
	operand := addition_fault_operand(t)
	baseline_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	baseline, baseline_error := value_add(&operand, &operand, probe_allocator(&baseline_probe))
	testing.expect_value(t, value_add_error_kind(&baseline_error), Value_Add_Error_Kind.None)
	allocation_count := baseline_probe.allocations
	testing.expect(t, allocation_count > 0)
	testing.expect_value(t, destroy_value(&baseline), runtime.Allocator_Error.None)
	testing.expect_value(t, baseline_probe.live, 0)

	for failure_at in 0..<allocation_count {
		probe := allocator_probe{backing = context.allocator, fail_after = failure_at}
		result, err := value_add(&operand, &operand, probe_allocator(&probe))
		testing.expect_value(t, kind_of(&result), Kind.Invalid)
		testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Out_Of_Memory)
		testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.live, 0)
		testing.expect(t, !probe.wrong_free_size)
		retry := add_expect_success(t, &operand, &operand)
		retry_length, retry_ok := array_length(&retry)
		testing.expect(t, retry_ok && retry_length == 4)
		testing.expect_value(t, destroy_value(&retry), runtime.Allocator_Error.None)
		operand_length, operand_ok := array_length(&operand)
		testing.expect(t, operand_ok && operand_length == 2)
	}
	testing.expect_value(t, destroy_value(&operand), runtime.Allocator_Error.None)
}

@(test)
value_add_cleanup_failure_precedes_allocation_cause_and_retries :: proc(t: ^testing.T) {
	operand := addition_fault_operand(t)
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = 3,
		free_failures_remaining = 6,
	}
	result, err := value_add(&operand, &operand, probe_allocator(&probe))
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, value_add_error_cause(&err), Value_Add_Error_Kind.Out_Of_Memory)
	testing.expect(t, value_add_error_needs_cleanup(&err))
	for value_add_error_kind(&err) != .None {
		cleanup_error := destroy_value_add_error(&err)
		if cleanup_error == nil do break
		testing.expect_value(t, cleanup_error, runtime.Allocator_Error.Invalid_Pointer)
	}
	testing.expect_value(t, probe.live, 0)
	testing.expect(t, !probe.wrong_free_size)
	retry := add_expect_success(t, &operand, &operand)
	testing.expect_value(t, destroy_value(&retry), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&operand), runtime.Allocator_Error.None)

	left, left_error := string_value("left", context.allocator)
	right, right_error := string_value("right", context.allocator)
	testing.expect_value(t, constructor_error_kind(&left_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&right_error), Error.None)
	mismatch_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
		free_failures_remaining = 1,
	}
	result, err = value_add(&left, &right, probe_allocator(&mismatch_probe))
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, value_add_error_cause(&err), Value_Add_Error_Kind.Out_Of_Memory)
	testing.expect(t, value_add_error_needs_cleanup(&err))
	testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, mismatch_probe.live, 0)
	testing.expect_value(t, destroy_value(&left), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&right), runtime.Allocator_Error.None)
}

@(test)
value_add_checked_overflow_guards_precede_allocation :: proc(t: ^testing.T) {
	array, array_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&array_error), Array_Error.None)
	one := number_value(1)
	displaced, append_error := array_append_take(&array, &one)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	storage := value_storage_of(&array)
	original_length := storage.array_length
	storage.array_length = max(int)
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	result, err := value_add(&array, &array, probe_allocator(&probe))
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Invalid_Operand)
	testing.expect_value(t, probe.allocations, 0)
	testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	storage.array_length = original_length
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)

	left, left_error := string_value("l", context.allocator)
	right, right_error := string_value("r", context.allocator)
	testing.expect_value(t, constructor_error_kind(&left_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&right_error), Error.None)
	left_payload := value_storage_of(&left).owned_payload
	original_bytes := left_payload.byte_count
	left_payload.byte_count = max(int)
	probe = allocator_probe{backing = context.allocator, fail_after = max(int)}
	result, err = value_add(&left, &right, probe_allocator(&probe))
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Invalid_Operand)
	testing.expect_value(t, probe.allocations, 0)
	testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	left_payload.byte_count = original_bytes
	testing.expect_value(t, destroy_value(&left), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&right), runtime.Allocator_Error.None)
}

@(test)
value_add_deep_mixed_construction_is_iterative :: proc(t: ^testing.T) {
	value := number_value(1)
	for depth in 0..<4_000 {
		if depth & 1 == 0 {
			value = wrap_array_take(t, &value, context.allocator)
		} else {
			value = wrap_object_take(t, &value, context.allocator)
		}
	}
	null := null_value()
	result := add_expect_success(t, &null, &value)
	testing.expect(t, kind_of(&result) == Kind.Array || kind_of(&result) == Kind.Object)
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)

	concat_source := wrap_array_take(t, &value, context.allocator)
	concat_result := add_expect_success(t, &concat_source, &concat_source)
	concat_length, concat_ok := array_length(&concat_result)
	testing.expect(t, concat_ok && concat_length == 2)
	testing.expect_value(t, destroy_value(&concat_source), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&concat_result), runtime.Allocator_Error.None)

	right_value := number_value(7)
	for depth in 0..<4_000 {
		if depth & 1 == 0 {
			right_value = wrap_object_take(t, &right_value, context.allocator)
		} else {
			right_value = wrap_array_take(t, &right_value, context.allocator)
		}
	}
	left_object, left_error := object_value(context.allocator)
	right_object, right_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&left_error), Object_Error.None)
	testing.expect_value(t, object_error_kind(&right_error), Object_Error.None)
	add_object_put_value(t, &left_object, "replace", number_value(1))
	right_key, right_key_error := string_value("replace", context.allocator)
	testing.expect_value(t, constructor_error_kind(&right_key_error), Error.None)
	duplicate, displaced, set_error := object_set_take(&right_object, &right_key, &right_value)
	testing.expect_value(t, object_error_kind(&set_error), Object_Error.None)
	testing.expect_value(t, destroy_value(&duplicate), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	object_result := add_expect_success(t, &left_object, &right_object)
	object_expect_order(t, &object_result, []string{"replace"})
	testing.expect_value(t, destroy_value(&right_object), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&object_result), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&left_object), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}

@(test)
value_add_cleanup_mappers_preserve_array_and_object_causes :: proc(t: ^testing.T) {
	array_cases := [?]Array_Error{.Out_Of_Memory, .Allocator_Unsupported, .Size_Overflow}
	expected := [?]Value_Add_Error_Kind{.Out_Of_Memory, .Allocator_Unsupported, .Size_Overflow}
	for source_cause, index in array_cases {
		cleanup: Constructor_Error
		source := make_array_cleanup_error(source_cause, &cleanup)
		testing.expect_value(t, array_error_kind(&source), Array_Error.Cleanup_Failed)
		testing.expect_value(t, array_error_cause(&source), source_cause)
		mapped := value_add_error_from_array(&source)
		testing.expect_value(t, value_add_error_kind(&mapped), Value_Add_Error_Kind.Cleanup_Failed)
		testing.expect_value(t, value_add_error_cause(&mapped), expected[index])
		testing.expect_value(t, destroy_value_add_error(&mapped), runtime.Allocator_Error.None)
	}
	object_cases := [?]Object_Error{.Out_Of_Memory, .Allocator_Unsupported, .Size_Overflow}
	for source_cause, index in object_cases {
		cleanup: Constructor_Error
		source := make_object_cleanup_error(source_cause, &cleanup)
		testing.expect_value(t, object_error_kind(&source), Object_Error.Cleanup_Failed)
		testing.expect_value(t, object_error_cause(&source), source_cause)
		mapped := value_add_error_from_object(&source)
		testing.expect_value(t, value_add_error_kind(&mapped), Value_Add_Error_Kind.Cleanup_Failed)
		testing.expect_value(t, value_add_error_cause(&mapped), expected[index])
		testing.expect_value(t, destroy_value_add_error(&mapped), runtime.Allocator_Error.None)
	}
}

@(private)
addition_frame_allocation_behavior :: enum u8 {
	Exact,
	Short,
}

@(private)
addition_frame_allocator_probe :: struct {
	base:     allocator_probe,
	behavior: addition_frame_allocation_behavior,
}

@(private)
addition_frame_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	probe := cast(^addition_frame_allocator_probe)data
	if (mode == .Alloc || mode == .Alloc_Non_Zeroed) &&
	   size == int(size_of(value_add_clone_frame)) && probe.behavior == .Short {
		previous := probe.base.short_success
		probe.base.short_success = true
		memory, err := allocator_probe_proc(
			&probe.base, mode, size, alignment, old_memory, old_size, location,
		)
		probe.base.short_success = previous
		return memory, err
	}
	return allocator_probe_proc(
		&probe.base, mode, size, alignment, old_memory, old_size, location,
	)
}

@(private)
addition_frame_allocator :: proc(probe: ^addition_frame_allocator_probe) -> runtime.Allocator {
	return {procedure = addition_frame_allocator_proc, data = probe}
}

@(private)
addition_singleton_array :: proc(t: ^testing.T) -> Value {
	result, create_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&create_error), Array_Error.None)
	one := number_value(1)
	displaced, append_error := array_append_take(&result, &one)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	return result
}

@(test)
value_add_construction_frame_resource_outcomes_and_cleanup_retry :: proc(t: ^testing.T) {
	source := addition_singleton_array(t)
	null := null_value()

	allocation_errors := [?]struct {
		allocator_error: runtime.Allocator_Error,
		expected:        Value_Add_Error_Kind,
	}{
		{.Out_Of_Memory, .Out_Of_Memory},
		{.Mode_Not_Implemented, .Allocator_Unsupported},
	}
	for test_case in allocation_errors {
		probe := allocator_probe{
			backing = context.allocator,
			fail_after = 1,
			failure_error = test_case.allocator_error,
		}
		result, err := value_add(&null, &source, probe_allocator(&probe))
		testing.expect_value(t, kind_of(&result), Kind.Invalid)
		testing.expect_value(t, value_add_error_kind(&err), test_case.expected)
		testing.expect(t, !value_add_error_needs_cleanup(&err))
		testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.live, 0)
		testing.expect(t, !probe.wrong_free_size)
	}

	short_probe := addition_frame_allocator_probe{
		base = {
			backing = context.allocator,
			fail_after = max(int),
			free_failures_remaining = 3,
		},
		behavior = .Short,
	}
	result, err := value_add(&null, &source, addition_frame_allocator(&short_probe))
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, value_add_error_cause(&err), Value_Add_Error_Kind.Out_Of_Memory)
	testing.expect(t, value_add_error_needs_cleanup(&err))
	cleanup_error := destroy_value_add_error(&err)
	testing.expect_value(t, cleanup_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, value_add_error_cause(&err), Value_Add_Error_Kind.Out_Of_Memory)
	testing.expect(t, value_add_error_needs_cleanup(&err))
	testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, short_probe.base.live, 0)
	testing.expect(t, !short_probe.base.wrong_free_size)

	release_probe := addition_frame_allocator_probe{
		base = {
			backing = context.allocator,
			fail_after = max(int),
			free_failures_remaining = 3,
		},
	}
	result, err = value_add(&null, &source, addition_frame_allocator(&release_probe))
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, value_add_error_cause(&err), Value_Add_Error_Kind.None)
	testing.expect(t, value_add_error_needs_cleanup(&err))
	cleanup_error = destroy_value_add_error(&err)
	testing.expect_value(t, cleanup_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, value_add_error_kind(&err), Value_Add_Error_Kind.Cleanup_Failed)
	testing.expect_value(t, value_add_error_cause(&err), Value_Add_Error_Kind.None)
	testing.expect(t, value_add_error_needs_cleanup(&err))
	testing.expect_value(t, destroy_value_add_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, release_probe.base.live, 0)
	testing.expect(t, !release_probe.base.wrong_free_size)

	arena: runtime.Arena
	init_error := runtime.arena_init(&arena, 4096, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error.None)
	if init_error == nil {
		bulk_probe := bulk_allocator_probe{backing = runtime.arena_allocator(&arena)}
		bulk_result, bulk_error := value_add(&null, &source, bulk_probe_allocator(&bulk_probe))
		testing.expect_value(t, value_add_error_kind(&bulk_error), Value_Add_Error_Kind.None)
		testing.expect_value(t, destroy_value(&bulk_result), runtime.Allocator_Error.None)
		testing.expect(t, bulk_probe.individual_free_requests >= 2)
		testing.expect_value(t, runtime.mem_free_all(bulk_probe_allocator(&bulk_probe)), runtime.Allocator_Error.None)
		testing.expect_value(t, bulk_probe.bulk_free_requests, 1)
		runtime.arena_destroy(&arena)
	}

	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
}
