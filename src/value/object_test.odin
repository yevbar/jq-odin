package value

import "base:runtime"
import "core:fmt"
import "core:testing"

@(private)
expect_destroyed :: proc(t: ^testing.T, value: ^Value) {
	testing.expect_value(t, destroy_value(value), runtime.Allocator_Error.None)
}

@(private)
object_put_number :: proc(t: ^testing.T, object: ^Value, key_text: string, number: f64) {
	key, key_error := string_value(key_text, context.allocator)
	testing.expect_value(t, constructor_error_kind(&key_error), Error.None)
	value := number_value(number)
	duplicate, displaced, set_error := object_set_take(object, &key, &value)
	testing.expect_value(t, object_error_kind(&set_error), Object_Error.None)
	testing.expect_value(t, kind_of(&key), Kind.Invalid)
	testing.expect_value(t, kind_of(&value), Kind.Invalid)
	expect_destroyed(t, &duplicate)
	expect_destroyed(t, &displaced)
}

@(private)
object_expect_order :: proc(t: ^testing.T, object: ^Value, expected: []string) {
	iterator := object_iterator()
	for text in expected {
		key, value, ok := object_iter_next_copy(object, &iterator)
		view, view_ok := string_borrowed(&key)
		testing.expect(t, ok && view_ok && view == text)
		expect_destroyed(t, &key)
		expect_destroyed(t, &value)
	}
	key, value, ok := object_iter_next_copy(object, &iterator)
	testing.expect(t, !ok)
	testing.expect_value(t, kind_of(&key), Kind.Invalid)
	testing.expect_value(t, kind_of(&value), Kind.Invalid)
	expect_destroyed(t, &key)
	expect_destroyed(t, &value)
	key, value, ok = object_iter_next_copy(object, &iterator)
	testing.expect(t, !ok)
	expect_destroyed(t, &key)
	expect_destroyed(t, &value)
}

@(private)
object_delete_expected :: proc(t: ^testing.T, object: ^Value, key: string) {
	removed_key, removed_value, found, err := object_delete_take(object, key)
	testing.expect(t, found)
	testing.expect_value(t, object_error_kind(&err), Object_Error.None)
	view, view_ok := string_borrowed(&removed_key)
	testing.expect(t, view_ok && view == key)
	expect_destroyed(t, &removed_key)
	expect_destroyed(t, &removed_value)
}

@(private)
object_allocation_failure_mode :: enum {
	Allocator_Error,
	Nil,
	Short_With_Cleanup_Failure,
}

@(private)
exercise_object_allocation_failure :: proc(
	t: ^testing.T,
	mode: object_allocation_failure_mode,
	cow: bool,
) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	object, create_error := object_value(probe_allocator(&probe))
	testing.expect_value(t, object_error_kind(&create_error), Object_Error.None)
	for i in 0..<OBJECT_INITIAL_CAPACITY {
		object_put_number(t, &object, fmt.tprintf("m%d", i), f64(i))
	}
	operand := &object
	alias: Value
	if cow {
		alias = clone_value(&object)
		operand = &alias
	}
	starting_allocations := probe.allocations
	starting_frees := probe.frees
	testing.expect_value(t, probe.live, 1)

	#partial switch mode {
	case .Allocator_Error:
		probe.fail_after = probe.allocations
	case .Nil:
		probe.nil_success = true
	case .Short_With_Cleanup_Failure:
		probe.short_success = true
		// One failure occurs while rejecting the short result and the next
		// occurs during the explicit cleanup retry below.
		probe.free_failures_remaining = 2
	}
	key_text := "new"
	if cow do key_text = "m0"
	key, _ := string_value(key_text, context.allocator)
	value := number_value(100)
	duplicate, displaced, err := object_set_take(operand, &key, &value)
	expected_kind := Object_Error.Out_Of_Memory
	if mode == .Short_With_Cleanup_Failure do expected_kind = .Cleanup_Failed
	testing.expect_value(t, object_error_kind(&err), expected_kind)
	if expected_kind == .Cleanup_Failed {
		testing.expect_value(t, object_error_cause(&err), Object_Error.Out_Of_Memory)
	}
	testing.expect_value(t, kind_of(&key), Kind.String)
	key_view, key_ok := string_borrowed(&key)
	testing.expect(t, key_ok && key_view == key_text)
	number, number_ok := number_value_get(&value)
	testing.expect(t, number_ok && number == 100)
	testing.expect_value(t, probe.allocations, starting_allocations + 1)
	expect_destroyed(t, &duplicate)
	expect_destroyed(t, &displaced)

	length, length_ok := object_length(operand)
	testing.expect(t, length_ok && length == OBJECT_INITIAL_CAPACITY)
	got, found := object_get_copy(operand, "m0")
	stored_number, stored_ok := number_value_get(&got)
	testing.expect(t, found && stored_ok && stored_number == 0)
	expect_destroyed(t, &got)
	if !cow {
		got, found = object_get_copy(operand, "new")
		testing.expect(t, !found && kind_of(&got) == .Invalid)
	}
	if cow do testing.expect(t, values_equal(&object, &alias))

	if mode == .Short_With_Cleanup_Failure {
		testing.expect(t, object_error_needs_cleanup(&err))
		testing.expect_value(t, probe.live, 2)
		testing.expect_value(t, probe.frees, starting_frees + 1)
		moved_error := take_object_error(&err)
		testing.expect_value(t, object_error_kind(&err), Object_Error.None)
		testing.expect(t, object_error_needs_cleanup(&moved_error))
		testing.expect_value(t, destroy_object_error(&err), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.frees, starting_frees + 1)
		testing.expect_value(
			t,
			destroy_object_error(&moved_error),
			runtime.Allocator_Error.Invalid_Pointer,
		)
		testing.expect(t, object_error_needs_cleanup(&moved_error))
		testing.expect_value(t, probe.live, 2)
		testing.expect_value(t, probe.frees, starting_frees + 2)
		testing.expect_value(t, destroy_object_error(&moved_error), runtime.Allocator_Error.None)
		testing.expect_value(t, object_error_kind(&moved_error), Object_Error.None)
		testing.expect_value(t, probe.live, 1)
		testing.expect_value(t, probe.frees, starting_frees + 3)
		testing.expect_value(t, destroy_object_error(&moved_error), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.frees, starting_frees + 3)
	} else {
		testing.expect(t, !object_error_needs_cleanup(&err))
		testing.expect_value(t, probe.live, 1)
		testing.expect_value(t, probe.frees, starting_frees)
		testing.expect_value(t, destroy_object_error(&err), runtime.Allocator_Error.None)
	}

	expect_destroyed(t, &key)
	expect_destroyed(t, &value)
	if cow {
		expect_destroyed(t, &alias)
		testing.expect_value(t, probe.live, 1)
	}
	expect_destroyed(t, &object)
	testing.expect_value(t, probe.live, 0)
	expected_frees := starting_frees + 1
	if mode == .Short_With_Cleanup_Failure do expected_frees += 3
	testing.expect_value(t, probe.frees, expected_frees)
	testing.expect(t, !probe.wrong_free_size)
}

@(private)
expect_unusable_object_handle :: proc(t: ^testing.T, object: ^Value, expected_clone_kind: Kind) {
	length, length_ok := object_length(object)
	testing.expect(t, !length_ok && length == 0)
	got, found := object_get_copy(object, "missing")
	testing.expect(t, !found && kind_of(&got) == .Invalid)
	expect_destroyed(t, &got)

	key, _ := string_value("new", context.allocator)
	value := number_value(9)
	duplicate, displaced, set_error := object_set_take(object, &key, &value)
	testing.expect_value(t, object_error_kind(&set_error), Object_Error.Wrong_Kind)
	testing.expect_value(t, kind_of(&key), Kind.String)
	key_view, key_ok := string_borrowed(&key)
	testing.expect(t, key_ok && key_view == "new")
	number, number_ok := number_value_get(&value)
	testing.expect(t, number_ok && number == 9)
	expect_destroyed(t, &duplicate)
	expect_destroyed(t, &displaced)
	testing.expect_value(t, destroy_object_error(&set_error), runtime.Allocator_Error.None)

	removed_key, removed_value, deleted, delete_error := object_delete_take(object, "key")
	testing.expect(t, !deleted)
	testing.expect_value(t, object_error_kind(&delete_error), Object_Error.Wrong_Kind)
	expect_destroyed(t, &removed_key)
	expect_destroyed(t, &removed_value)
	testing.expect_value(t, destroy_object_error(&delete_error), runtime.Allocator_Error.None)

	iterator := object_iterator()
	iter_key, iter_value, iter_ok := object_iter_next_copy(object, &iterator)
	testing.expect(t, !iter_ok)
	expect_destroyed(t, &iter_key)
	expect_destroyed(t, &iter_value)
	comparison, _ := object_value(context.allocator)
	testing.expect(t, !values_equal(object, &comparison))
	testing.expect(t, !values_equal(&comparison, object))
	clone := clone_value(object)
	testing.expect_value(t, kind_of(&clone), expected_clone_kind)
	expect_destroyed(t, &clone)
	expect_destroyed(t, &comparison)
	expect_destroyed(t, &key)
	expect_destroyed(t, &value)
}

@(test)
object_empty_insert_replace_lookup_and_order :: proc(t: ^testing.T) {
	object, error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&error), Object_Error.None)
	defer expect_destroyed(t, &object)
	length, ok := object_length(&object)
	testing.expect(t, ok)
	testing.expect_value(t, length, 0)

	object_put_number(t, &object, "b", 1)
	object_put_number(t, &object, "a", 2)
	object_put_number(t, &object, "c", 3)
	object_put_number(t, &object, "a", 20)
	length, ok = object_length(&object)
	testing.expect(t, ok)
	testing.expect_value(t, length, 3)

	got, found := object_get_copy(&object, "a")
	testing.expect(t, found)
	number, number_ok := number_value_get(&got)
	testing.expect(t, number_ok && number == 20)
	expect_destroyed(t, &got)
	missing, missing_found := object_get_copy(&object, "missing")
	testing.expect(t, !missing_found && kind_of(&missing) == .Invalid)

	expected := [3]string{"b", "a", "c"}
	iterator := object_iterator()
	for text, index in expected {
		key, value, next_ok := object_iter_next_copy(&object, &iterator)
		testing.expect(t, next_ok)
		view, view_ok := string_borrowed(&key)
		testing.expect(t, view_ok && view == text)
		got_number, got_ok := number_value_get(&value)
		expected_number := [3]f64{1, 20, 3}
		testing.expect(t, got_ok && got_number == expected_number[index])
		expect_destroyed(t, &key)
		expect_destroyed(t, &value)
	}
	key, value, next_ok := object_iter_next_copy(&object, &iterator)
	testing.expect(t, !next_ok)
	expect_destroyed(t, &key)
	expect_destroyed(t, &value)
}

@(test)
object_allocation_delete_and_cow_preserve_canonical_empty_slots :: proc(t: ^testing.T) {
	object, object_error := object_value(context.allocator)
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	p := value_storage_of(&object).owned_payload
	for &slot in object_payload_slots(p) {
		testing.expect(t, object_slot_is_canonical_empty(&slot))
	}

	object_put_number(t, &object, "removed", 1)
	object_delete_expected(t, &object, "removed")
	testing.expect(t, object_slot_is_canonical_empty(&object_payload_slots(p)[0]))

	alias := clone_value(&object)
	object_put_number(t, &alias, "kept", 2)
	alias_payload := value_storage_of(&alias).owned_payload
	testing.expect(t, alias_payload != p)
	testing.expect(t, object_slot_is_canonical_empty(&object_payload_slots(alias_payload)[0]))
	for i in alias_payload.object_next_free..<alias_payload.object_capacity {
		testing.expect(t, object_slot_is_canonical_empty(&object_payload_slots(alias_payload)[i]))
	}
	testing.expect_value(t, destroy_value(&alias), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.None)
}

@(test)
object_duplicate_key_returns_incoming_owner :: proc(t: ^testing.T) {
	object, _ := object_value(context.allocator)
	defer expect_destroyed(t, &object)
	object_put_number(t, &object, "same", 1)
	key, _ := string_value("same", context.allocator)
	value := boolean_value(true)
	duplicate, displaced, error := object_set_take(&object, &key, &value)
	testing.expect_value(t, object_error_kind(&error), Object_Error.None)
	view, view_ok := string_borrowed(&duplicate)
	testing.expect(t, view_ok && view == "same")
	old, old_ok := number_value_get(&displaced)
	testing.expect(t, old_ok && old == 1)
	expect_destroyed(t, &duplicate)
	expect_destroyed(t, &displaced)
}

@(test)
object_delete_preserves_slot_order_and_cow_alias :: proc(t: ^testing.T) {
	original, _ := object_value(context.allocator)
	defer expect_destroyed(t, &original)
	initial := [4]string{"a", "b", "c", "d"}
	for text, index in initial {
		object_put_number(t, &original, text, f64(index))
	}
	alias := clone_value(&original)
	defer expect_destroyed(t, &alias)
	removed_key, removed_value, found, error := object_delete_take(&alias, "b")
	testing.expect(t, found)
	testing.expect_value(t, object_error_kind(&error), Object_Error.None)
	expect_destroyed(t, &removed_key)
	expect_destroyed(t, &removed_value)
	object_put_number(t, &alias, "e", 4)

	original_b, original_has_b := object_get_copy(&original, "b")
	testing.expect(t, original_has_b)
	expect_destroyed(t, &original_b)
	alias_b, alias_has_b := object_get_copy(&alias, "b")
	testing.expect(t, !alias_has_b)
	expect_destroyed(t, &alias_b)
	expected := [4]string{"a", "c", "d", "e"}
	iterator := object_iterator()
	for text in expected {
		key, value, ok := object_iter_next_copy(&alias, &iterator)
		view, view_ok := string_borrowed(&key)
		testing.expect(t, ok && view_ok && view == text)
		expect_destroyed(t, &key)
		expect_destroyed(t, &value)
	}
}

@(test)
object_delete_reinsert_growth_holes_and_collision_chains :: proc(t: ^testing.T) {
	reinserted, _ := object_value(context.allocator)
	defer expect_destroyed(t, &reinserted)
	initial := [3]string{"a", "b", "c"}
	for text, index in initial {
		object_put_number(t, &reinserted, text, f64(index))
	}
	object_delete_expected(t, &reinserted, "b")
	object_put_number(t, &reinserted, "d", 3)
	object_put_number(t, &reinserted, "b", 20)
	length, length_ok := object_length(&reinserted)
	testing.expect(t, length_ok && length == 4)
	reinserted_order := [4]string{"a", "c", "d", "b"}
	object_expect_order(t, &reinserted, reinserted_order[:])

	grown, _ := object_value(context.allocator)
	defer expect_destroyed(t, &grown)
	for i in 0..<OBJECT_INITIAL_CAPACITY {
		object_put_number(t, &grown, fmt.tprintf("k%d", i), f64(i))
	}
	object_delete_expected(t, &grown, "k1")
	object_delete_expected(t, &grown, "k4")
	for i in OBJECT_INITIAL_CAPACITY..<OBJECT_INITIAL_CAPACITY + 5 {
		object_put_number(t, &grown, fmt.tprintf("k%d", i), f64(i))
	}
	length, length_ok = object_length(&grown)
	testing.expect(t, length_ok && length == 11)
	grown_order := [11]string{
		"k0", "k2", "k3", "k5", "k6", "k7",
		"k8", "k9", "k10", "k11", "k12",
	}
	object_expect_order(t, &grown, grown_order[:])

	// These keys share an initial-capacity bucket. Insertion creates the chain
	// c40 -> c31 -> c22 -> c0, so c40 is the head and c22 is interior.
	colliding_keys := [4]string{"c0", "c22", "c31", "c40"}
	for text in colliding_keys {
		testing.expect_value(
			t,
			object_hash(text) & u32(OBJECT_INITIAL_CAPACITY * 2 - 1),
			object_hash("c0") & u32(OBJECT_INITIAL_CAPACITY * 2 - 1),
		)
	}
	colliding, _ := object_value(context.allocator)
	defer expect_destroyed(t, &colliding)
	for text, index in colliding_keys {
		object_put_number(t, &colliding, text, f64(index))
	}
	object_delete_expected(t, &colliding, "c40")
	object_delete_expected(t, &colliding, "c22")
	remaining_keys := [2]string{"c0", "c31"}
	remaining_numbers := [2]f64{0, 2}
	for text, index in remaining_keys {
		got, found := object_get_copy(&colliding, text)
		number, number_ok := number_value_get(&got)
		testing.expect(t, found && number_ok && number == remaining_numbers[index])
		expect_destroyed(t, &got)
	}
	deleted_keys := [2]string{"c22", "c40"}
	for text in deleted_keys {
		got, found := object_get_copy(&colliding, text)
		testing.expect(t, !found && kind_of(&got) == .Invalid)
		expect_destroyed(t, &got)
	}
	length, length_ok = object_length(&colliding)
	testing.expect(t, length_ok && length == 2)
	collision_order := [2]string{"c0", "c31"}
	object_expect_order(t, &colliding, collision_order[:])
}

@(test)
object_growth_compacts_deletions_and_preserves_order :: proc(t: ^testing.T) {
	object, _ := object_value(context.allocator)
	defer expect_destroyed(t, &object)
	for i in 0..<64 {
		key_text := fmt.tprintf("k%02d", i)
		object_put_number(t, &object, key_text, f64(i))
	}
	for i in 0..<64 {
		key_text := fmt.tprintf("k%02d", i)
		got, found := object_get_copy(&object, key_text)
		number, ok := number_value_get(&got)
		testing.expect(t, found && ok && number == f64(i))
		expect_destroyed(t, &got)
	}
	length, ok := object_length(&object)
	testing.expect(t, ok && length == 64)
}

@(test)
object_equality_ignores_insertion_order_and_is_recursive :: proc(t: ^testing.T) {
	left, _ := object_value(context.allocator)
	right, _ := object_value(context.allocator)
	defer expect_destroyed(t, &left)
	defer expect_destroyed(t, &right)
	object_put_number(t, &left, "a", 1)
	object_put_number(t, &left, "b", 2)
	object_put_number(t, &right, "b", 2)
	object_put_number(t, &right, "a", 1)
	testing.expect(t, values_equal(&left, &right))
	object_put_number(t, &right, "a", 3)
	testing.expect(t, !values_equal(&left, &right))

	nested_left, _ := object_value(context.allocator)
	nested_right, _ := object_value(context.allocator)
	key_left, _ := string_value("nested", context.allocator)
	key_right, _ := string_value("nested", context.allocator)
	_, _, left_error := object_set_take(&nested_left, &key_left, &left)
	_, _, right_error := object_set_take(&nested_right, &key_right, &right)
	testing.expect_value(t, object_error_kind(&left_error), Object_Error.None)
	testing.expect_value(t, object_error_kind(&right_error), Object_Error.None)
	testing.expect(t, !values_equal(&nested_left, &nested_right))
	expect_destroyed(t, &nested_left)
	expect_destroyed(t, &nested_right)
}

@(test)
object_recursive_equality_accepts_nested_objects_and_arrays :: proc(t: ^testing.T) {
	inner_left, _ := object_value(context.allocator)
	object_put_number(t, &inner_left, "a", 1)
	object_put_number(t, &inner_left, "hole", 99)
	object_put_number(t, &inner_left, "b", 2)
	object_delete_expected(t, &inner_left, "hole")

	inner_right, _ := object_value(context.allocator)
	object_put_number(t, &inner_right, "discard", 88)
	object_put_number(t, &inner_right, "b", 2)
	object_put_number(t, &inner_right, "a", 1)
	object_delete_expected(t, &inner_right, "discard")
	testing.expect(t, values_equal(&inner_left, &inner_right))

	array_left, _ := array_value(context.allocator)
	array_right, _ := array_value(context.allocator)
	_, left_append_error := array_append_take(&array_left, &inner_left)
	_, right_append_error := array_append_take(&array_right, &inner_right)
	testing.expect_value(t, array_error_kind(&left_append_error), Array_Error.None)
	testing.expect_value(t, array_error_kind(&right_append_error), Array_Error.None)
	left_tail := number_value(7)
	right_tail := number_value(7)
	_, left_append_error = array_append_take(&array_left, &left_tail)
	_, right_append_error = array_append_take(&array_right, &right_tail)
	testing.expect_value(t, array_error_kind(&left_append_error), Array_Error.None)
	testing.expect_value(t, array_error_kind(&right_append_error), Array_Error.None)

	outer_left, _ := object_value(context.allocator)
	outer_right, _ := object_value(context.allocator)
	defer expect_destroyed(t, &outer_left)
	defer expect_destroyed(t, &outer_right)
	left_key, _ := string_value("items", context.allocator)
	right_key, _ := string_value("items", context.allocator)
	_, _, left_set_error := object_set_take(&outer_left, &left_key, &array_left)
	_, _, right_set_error := object_set_take(&outer_right, &right_key, &array_right)
	testing.expect_value(t, object_error_kind(&left_set_error), Object_Error.None)
	testing.expect_value(t, object_error_kind(&right_set_error), Object_Error.None)
	testing.expect(t, values_equal(&outer_left, &outer_right))

	right_items, found := object_get_copy(&outer_right, "items")
	testing.expect(t, found)
	unequal_tail := number_value(8)
	displaced, set_error := array_set_take(&right_items, 1, &unequal_tail)
	testing.expect_value(t, array_error_kind(&set_error), Array_Error.None)
	expect_destroyed(t, &displaced)
	replacement_key, _ := string_value("items", context.allocator)
	duplicate, old_items, replace_error := object_set_take(
		&outer_right,
		&replacement_key,
		&right_items,
	)
	testing.expect_value(t, object_error_kind(&replace_error), Object_Error.None)
	expect_destroyed(t, &duplicate)
	expect_destroyed(t, &old_items)
	testing.expect(t, !values_equal(&outer_left, &outer_right))
}

@(test)
object_nested_array_string_number_and_object_teardown :: proc(t: ^testing.T) {
	outer, _ := object_value(context.allocator)
	array, _ := array_value(context.allocator)
	inner, _ := object_value(context.allocator)
	inner_key, _ := string_value("literal", context.allocator)
	literal, _ := literal_number_value("9007199254740993", context.allocator)
	_, _, inner_error := object_set_take(&inner, &inner_key, &literal)
	testing.expect_value(t, object_error_kind(&inner_error), Object_Error.None)
	_, append_error := array_append_take(&array, &inner)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	text, _ := string_value("bytes\x00ok", context.allocator)
	_, append_error = array_append_take(&array, &text)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	outer_key, _ := string_value("items", context.allocator)
	_, _, outer_error := object_set_take(&outer, &outer_key, &array)
	testing.expect_value(t, object_error_kind(&outer_error), Object_Error.None)
	expect_destroyed(t, &outer)
}

@(test)
object_allocation_failure_is_atomic_for_cow_and_growth :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	object, create_error := object_value(probe_allocator(&probe))
	testing.expect_value(t, object_error_kind(&create_error), Object_Error.None)
	defer expect_destroyed(t, &object)
	for i in 0..<OBJECT_INITIAL_CAPACITY {
		object_put_number(t, &object, fmt.tprintf("%d", i), f64(i))
	}
	key, _ := string_value("growth", context.allocator)
	value := number_value(9)
	probe.fail_after = probe.allocations
	duplicate, displaced, growth_error := object_set_take(&object, &key, &value)
	testing.expect_value(t, object_error_kind(&growth_error), Object_Error.Out_Of_Memory)
	testing.expect_value(t, kind_of(&key), Kind.String)
	testing.expect_value(t, kind_of(&value), Kind.Number)
	length, ok := object_length(&object)
	testing.expect(t, ok && length == OBJECT_INITIAL_CAPACITY)
	expect_destroyed(t, &duplicate)
	expect_destroyed(t, &displaced)
	expect_destroyed(t, &key)
	expect_destroyed(t, &value)

	alias := clone_value(&object)
	defer expect_destroyed(t, &alias)
	key, _ = string_value("0", context.allocator)
	value = number_value(100)
	probe.fail_after = probe.allocations
	_, _, cow_error := object_set_take(&alias, &key, &value)
	testing.expect_value(t, object_error_kind(&cow_error), Object_Error.Out_Of_Memory)
	got, found := object_get_copy(&alias, "0")
	number, number_ok := number_value_get(&got)
	testing.expect(t, found && number_ok && number == 0)
	expect_destroyed(t, &got)
	expect_destroyed(t, &key)
	expect_destroyed(t, &value)
	probe.fail_after = probe.allocations
	removed_key, removed_value, delete_found, delete_error := object_delete_take(&alias, "0")
	testing.expect(t, !delete_found)
	testing.expect_value(t, object_error_kind(&delete_error), Object_Error.Out_Of_Memory)
	got, found = object_get_copy(&alias, "0")
	number, number_ok = number_value_get(&got)
	testing.expect(t, found && number_ok && number == 0)
	expect_destroyed(t, &got)
	expect_destroyed(t, &removed_key)
	expect_destroyed(t, &removed_value)
}

@(test)
object_cow_and_growth_allocation_failure_cleanup_matrix :: proc(t: ^testing.T) {
	modes := [3]object_allocation_failure_mode{
		.Allocator_Error,
		.Nil,
		.Short_With_Cleanup_Failure,
	}
	for mode in modes {
		exercise_object_allocation_failure(t, mode, true)
		exercise_object_allocation_failure(t, mode, false)
	}
}

@(test)
object_growth_combined_old_and_temporary_free_failures_transfer_cleanup :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	object, create_error := object_value(probe_allocator(&probe))
	testing.expect_value(t, object_error_kind(&create_error), Object_Error.None)
	for i in 0..<OBJECT_INITIAL_CAPACITY {
		object_put_number(t, &object, fmt.tprintf("f%d", i), f64(i))
	}
	testing.expect_value(t, probe.live, 1)
	testing.expect_value(t, probe.frees, 0)
	key, _ := string_value("next", context.allocator)
	value := number_value(9)
	// Old-table retirement fails, replacement-temporary retirement fails, and
	// the first explicit cleanup retry fails. The fourth Free succeeds.
	probe.free_failures_remaining = 3
	duplicate, displaced, err := object_set_take(&object, &key, &value)
	testing.expect_value(t, object_error_kind(&err), Object_Error.Cleanup_Failed)
	testing.expect(t, object_error_needs_cleanup(&err))
	testing.expect_value(t, kind_of(&key), Kind.String)
	number, number_ok := number_value_get(&value)
	testing.expect(t, number_ok && number == 9)
	length, length_ok := object_length(&object)
	testing.expect(t, length_ok && length == OBJECT_INITIAL_CAPACITY)
	got, found := object_get_copy(&object, "next")
	testing.expect(t, !found && kind_of(&got) == .Invalid)
	for i in 0..<OBJECT_INITIAL_CAPACITY {
		got, found = object_get_copy(&object, fmt.tprintf("f%d", i))
		stored, stored_ok := number_value_get(&got)
		testing.expect(t, found && stored_ok && stored == f64(i))
		expect_destroyed(t, &got)
	}
	testing.expect_value(t, probe.allocations, 2)
	testing.expect_value(t, probe.frees, 2)
	testing.expect_value(t, probe.live, 2)
	expect_destroyed(t, &duplicate)
	expect_destroyed(t, &displaced)

	moved_error := take_object_error(&err)
	testing.expect_value(t, object_error_kind(&err), Object_Error.None)
	testing.expect_value(
		t,
		destroy_object_error(&moved_error),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect(t, object_error_needs_cleanup(&moved_error))
	testing.expect_value(t, probe.frees, 3)
	testing.expect_value(t, probe.live, 2)
	testing.expect_value(t, destroy_object_error(&moved_error), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 4)
	testing.expect_value(t, probe.live, 1)
	testing.expect_value(t, destroy_object_error(&moved_error), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 4)
	expect_destroyed(t, &key)
	expect_destroyed(t, &value)
	expect_destroyed(t, &object)
	testing.expect_value(t, probe.frees, 5)
	testing.expect_value(t, probe.live, 0)
	testing.expect(t, !probe.wrong_free_size)
}

@(test)
object_exact_allocation_and_growth_cleanup_failures_are_owned :: proc(t: ^testing.T) {
	nil_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		nil_success = true,
	}
	nil_object, nil_error := object_value(probe_allocator(&nil_probe))
	testing.expect_value(t, kind_of(&nil_object), Kind.Invalid)
	testing.expect_value(t, object_error_kind(&nil_error), Object_Error.Out_Of_Memory)
	testing.expect(t, !object_error_needs_cleanup(&nil_error))

	short_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
		free_failures_remaining = 1,
	}
	short_object, short_error := object_value(probe_allocator(&short_probe))
	testing.expect_value(t, kind_of(&short_object), Kind.Invalid)
	testing.expect_value(t, object_error_kind(&short_error), Object_Error.Cleanup_Failed)
	testing.expect_value(t, object_error_cause(&short_error), Object_Error.Out_Of_Memory)
	testing.expect(t, object_error_needs_cleanup(&short_error))
	testing.expect_value(t, short_probe.live, 1)
	testing.expect_value(t, destroy_object_error(&short_error), runtime.Allocator_Error.None)
	testing.expect_value(t, short_probe.live, 0)

	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	object, create_error := object_value(probe_allocator(&probe))
	testing.expect_value(t, object_error_kind(&create_error), Object_Error.None)
	defer expect_destroyed(t, &object)
	for i in 0..<OBJECT_INITIAL_CAPACITY {
		object_put_number(t, &object, fmt.tprintf("g%d", i), f64(i))
	}
	key, _ := string_value("next", context.allocator)
	value := number_value(8)
	probe.free_failures_remaining = 1
	duplicate, displaced, growth_error := object_set_take(&object, &key, &value)
	testing.expect_value(t, object_error_kind(&growth_error), Object_Error.Cleanup_Failed)
	testing.expect(t, !object_error_needs_cleanup(&growth_error))
	testing.expect_value(t, kind_of(&key), Kind.String)
	testing.expect_value(t, kind_of(&value), Kind.Number)
	length, ok := object_length(&object)
	testing.expect(t, ok && length == OBJECT_INITIAL_CAPACITY)
	testing.expect_value(t, probe.live, 1)
	expect_destroyed(t, &duplicate)
	expect_destroyed(t, &displaced)
	expect_destroyed(t, &key)
	expect_destroyed(t, &value)
}

@(test)
object_shared_full_second_phase_growth_failure_is_logically_atomic :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	object, _ := object_value(probe_allocator(&probe))
	defer expect_destroyed(t, &object)
	for i in 0..<OBJECT_INITIAL_CAPACITY {
		object_put_number(t, &object, fmt.tprintf("s%d", i), f64(i))
	}
	alias := clone_value(&object)
	defer expect_destroyed(t, &alias)
	key, _ := string_value("new", context.allocator)
	value := number_value(99)
	// The equal-capacity COW allocation succeeds; the subsequent doubling
	// allocation is the injected failure.
	probe.fail_after = probe.allocations + 1
	duplicate, displaced, error := object_set_take(&alias, &key, &value)
	testing.expect_value(t, object_error_kind(&error), Object_Error.Out_Of_Memory)
	testing.expect_value(t, kind_of(&key), Kind.String)
	testing.expect_value(t, kind_of(&value), Kind.Number)
	testing.expect(t, values_equal(&object, &alias))
	length, ok := object_length(&alias)
	testing.expect(t, ok && length == OBJECT_INITIAL_CAPACITY)
	expect_destroyed(t, &duplicate)
	expect_destroyed(t, &displaced)
	expect_destroyed(t, &key)
	expect_destroyed(t, &value)
}

@(test)
object_final_backing_free_failure_is_retryable :: proc(t: ^testing.T) {
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	object, error := object_value(probe_allocator(&probe))
	testing.expect_value(t, object_error_kind(&error), Object_Error.None)
	first_error := destroy_value(&object)
	testing.expect_value(t, first_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, kind_of(&object), Kind.Object)
	testing.expect_value(t, probe.live, 1)
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	probe.retired = true
	length, ok := object_length(&object)
	testing.expect(t, !ok && length == 0)
	testing.expect(t, !probe.called_retired)
}

@(test)
object_retirement_resumes_value_then_backing_without_double_free :: proc(t: ^testing.T) {
	object_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	key_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	value_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	object, _ := object_value(probe_allocator(&object_probe))
	key, _ := string_value("key", probe_allocator(&key_probe))
	value, _ := string_value("value", probe_allocator(&value_probe))
	_, _, set_error := object_set_take(&object, &key, &value)
	testing.expect_value(t, object_error_kind(&set_error), Object_Error.None)
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, key_probe.frees, 1)
	testing.expect_value(t, key_probe.live, 0)
	testing.expect_value(t, value_probe.frees, 1)
	testing.expect_value(t, value_probe.live, 1)
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, key_probe.frees, 1)
	testing.expect_value(t, value_probe.frees, 2)
	testing.expect_value(t, value_probe.live, 0)
	testing.expect_value(t, object_probe.frees, 1)
	testing.expect_value(t, object_probe.live, 1)
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.None)
	testing.expect_value(t, key_probe.frees, 1)
	testing.expect_value(t, value_probe.frees, 2)
	testing.expect_value(t, object_probe.frees, 2)
	testing.expect_value(t, object_probe.live, 0)
}

@(test)
object_allocator_provenance_and_retryable_nested_free :: proc(t: ^testing.T) {
	object_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	child_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	object, _ := object_value(probe_allocator(&object_probe))
	key, _ := string_value("key", probe_allocator(&child_probe))
	value, _ := string_value("value", context.allocator)
	_, _, error := object_set_take(&object, &key, &value)
	testing.expect_value(t, object_error_kind(&error), Object_Error.None)
	first_error := destroy_value(&object)
	testing.expect_value(t, first_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, kind_of(&object), Kind.Object)
	_, length_ok := object_length(&object)
	testing.expect(t, !length_ok)
	holder, _ := object_value(context.allocator)
	holder_key, _ := string_value("retiring", context.allocator)
	_, _, insert_error := object_set_take(&holder, &holder_key, &object)
	testing.expect_value(t, object_error_kind(&insert_error), Object_Error.Wrong_Kind)
	array, _ := array_value(context.allocator)
	_, append_error := array_append_take(&array, &object)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.Wrong_Kind)
	expect_destroyed(t, &holder_key)
	expect_destroyed(t, &holder)
	expect_destroyed(t, &array)
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.None)
	testing.expect_value(t, object_probe.live, 0)
	testing.expect_value(t, child_probe.live, 0)
}

@(test)
object_bulk_allocator_retirement_and_invalid_handles :: proc(t: ^testing.T) {
	arena: runtime.Arena
	init_error := runtime.arena_init(&arena, 8192, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error.None)
	if init_error != nil do return
	object, error := object_value(runtime.arena_allocator(&arena))
	testing.expect_value(t, object_error_kind(&error), Object_Error.None)
	object_put_number(t, &object, "a", 1)
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&object), Kind.Invalid)
	length, ok := object_length(&object)
	testing.expect(t, !ok && length == 0)
	iterator := object_iterator()
	key, value, next_ok := object_iter_next_copy(&object, &iterator)
	testing.expect(t, !next_ok)
	expect_destroyed(t, &key)
	expect_destroyed(t, &value)
	runtime.arena_destroy(&arena)
}

@(test)
object_public_unusable_handle_matrix_is_atomic_and_cleanup_safe :: proc(t: ^testing.T) {
	nil_value: Value
	taken_from, _ := object_value(context.allocator)
	taken_owner := take_value(&taken_from)
	destroyed, _ := object_value(context.allocator)
	expect_destroyed(t, &destroyed)
	wrong_kind := number_value(42)
	handles := [5]^Value{nil, &nil_value, &taken_from, &destroyed, &wrong_kind}
	expected_clone_kinds := [5]Kind{.Invalid, .Invalid, .Invalid, .Invalid, .Number}
	for handle, index in handles {
		expect_unusable_object_handle(t, handle, expected_clone_kinds[index])
	}
	wrong_number, wrong_ok := number_value_get(&wrong_kind)
	testing.expect(t, wrong_ok && wrong_number == 42)
	expect_destroyed(t, &taken_owner)
	expect_destroyed(t, &wrong_kind)

	object_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	child_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	retiring, _ := object_value(probe_allocator(&object_probe))
	retiring_key, _ := string_value("key", probe_allocator(&child_probe))
	retiring_value := number_value(1)
	_, _, set_error := object_set_take(&retiring, &retiring_key, &retiring_value)
	testing.expect_value(t, object_error_kind(&set_error), Object_Error.None)
	testing.expect_value(t, destroy_value(&retiring), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, kind_of(&retiring), Kind.Object)
	testing.expect_value(t, object_probe.live, 1)
	testing.expect_value(t, child_probe.live, 1)
	expect_unusable_object_handle(t, &retiring, .Invalid)
	testing.expect_value(t, object_probe.live, 1)
	testing.expect_value(t, child_probe.live, 1)
	testing.expect_value(t, child_probe.frees, 1)
	testing.expect_value(t, destroy_value(&retiring), runtime.Allocator_Error.None)
	testing.expect_value(t, object_probe.live, 0)
	testing.expect_value(t, child_probe.live, 0)
	testing.expect_value(t, child_probe.frees, 2)
	testing.expect_value(t, destroy_value(&retiring), runtime.Allocator_Error.None)
	testing.expect_value(t, object_probe.frees, 1)
	testing.expect_value(t, child_probe.frees, 2)
}

@(test)
object_rejects_wrong_and_aliased_operands_without_assertions :: proc(t: ^testing.T) {
	object, _ := object_value(context.allocator)
	defer expect_destroyed(t, &object)
	non_string := number_value(1)
	value := null_value()
	_, _, wrong_error := object_set_take(&object, &non_string, &value)
	testing.expect_value(t, object_error_kind(&wrong_error), Object_Error.Wrong_Kind)
	key, _ := string_value("self", context.allocator)
	_, _, alias_error := object_set_take(&object, &key, &object)
	testing.expect_value(t, object_error_kind(&alias_error), Object_Error.Aliased_Operand)
	expect_destroyed(t, &non_string)
	expect_destroyed(t, &value)
	expect_destroyed(t, &key)
}
