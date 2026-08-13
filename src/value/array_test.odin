package value

import "base:runtime"
import "core:testing"

array_number_at :: proc(t: ^testing.T, array: ^Value, index: int) -> f64 {
	element, ok := array_element_copy(array, index)
	testing.expect(t, ok)
	result, number_ok := number_value_get(&element)
	testing.expect(t, number_ok)
	testing.expect_value(t, destroy_value(&element), runtime.Allocator_Error.None)
	return result
}

fill_array_to_initial_capacity :: proc(t: ^testing.T, array: ^Value) {
	length, ok := array_length(array)
	testing.expect(t, ok)
	for i in length..<ARRAY_INITIAL_CAPACITY {
		element := number_value(f64(i))
		append_error := append_take_no_displaced(array, &element)
		testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	}
}

append_take_no_displaced :: proc(array: ^Value, element: ^Value) -> Array_Operation_Error {
	displaced, err := array_append_take(array, element)
	assert(displaced == nil)
	return err
}

@(test)
array_replace_range_copy_preserves_source_and_splices :: proc(t: ^testing.T) {
	source, _ := array_value(context.allocator)
	for i in 0..<5 { item := number_value(f64(i)); append_take_no_displaced(&source, &item) }
	replacement, _ := array_value(context.allocator)
	for n in 0..<2 { item := number_value(88 + f64(n)); append_take_no_displaced(&replacement, &item) }
	result, err := array_replace_range_copy(&source, &replacement, 1, 3, context.allocator)
	defer destroy_value(&source); defer destroy_value(&replacement); defer destroy_value(&result)
	testing.expect_value(t, array_error_kind(&err), Array_Error.None)
	source_length, source_ok := array_length(&source); result_length, result_ok := array_length(&result)
	testing.expect(t, source_ok && source_length == 5); testing.expect(t, result_ok && result_length == 5)
	testing.expect_value(t, array_number_at(t, &result, 0), 0)
	testing.expect_value(t, array_number_at(t, &result, 1), 88)
	testing.expect_value(t, array_number_at(t, &result, 2), 89)
	testing.expect_value(t, array_number_at(t, &result, 4), 4)
}

@(test)
array_construct_append_lookup_growth_and_take :: proc(t: ^testing.T) {
	array, err := array_value(context.allocator)
	defer destroy_value(&array)
	testing.expect_value(t, array_error_kind(&err), Array_Error.None)
	length, ok := array_length(&array)
	testing.expect(t, ok && length == 0)
	_, missing := array_element_copy(&array, 0)
	testing.expect(t, !missing)

	for i in 0..<12 {
		element := number_value(f64(i))
		append_error := append_take_no_displaced(&array, &element)
		testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
		testing.expect_value(t, kind_of(&element), Kind.Invalid)
	}
	length, ok = array_length(&array)
	testing.expect(t, ok && length == 12)
	for i in 0..<12 {
		testing.expect_value(t, array_number_at(t, &array, i), f64(i))
	}

	p := value_storage_of(&array).owned_payload
	capacity := p.array_capacity
	if capacity > value_storage_of(&array).array_length {
		element := number_value(99)
		append_error := append_take_no_displaced(&array, &element)
		testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
		testing.expect(t, value_storage_of(&array).owned_payload == p)
	}
	shallow_alias := array
	testing.expect(t, value_storage_of(&shallow_alias).owned_payload == value_storage_of(&array).owned_payload)
	// This explicitly demonstrates why ordinary assignment is forbidden: the
	// alias did not retain. Invalidate it without releasing the sole reference.
	shallow_alias = {}
}

@(test)
array_clone_detaches_on_write_and_take_moves_handle :: proc(t: ^testing.T) {
	source, _ := array_value(context.allocator)
	source_element := number_value(41)
	append_take_no_displaced(&source, &source_element)
	survivor := clone_value(&source)
	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	testing.expect_value(t, array_number_at(t, &survivor, 0), 41)
	testing.expect_value(t, destroy_value(&survivor), runtime.Allocator_Error.None)

	original, _ := array_value(context.allocator)
	first := number_value(1)
	first_error := append_take_no_displaced(&original, &first)
	testing.expect_value(t, array_error_kind(&first_error), Array_Error.None)
	clone := clone_value(&original)
	original_payload := value_storage_of(&original).owned_payload
	second := number_value(2)
	second_error := append_take_no_displaced(&clone, &second)
	testing.expect_value(t, array_error_kind(&second_error), Array_Error.None)
	testing.expect(t, value_storage_of(&clone).owned_payload != original_payload)
	original_length, _ := array_length(&original)
	clone_length, _ := array_length(&clone)
	testing.expect_value(t, original_length, 1)
	testing.expect_value(t, clone_length, 2)
	testing.expect_value(t, array_number_at(t, &original, 0), 1)
	testing.expect_value(t, array_number_at(t, &clone, 1), 2)

	moved := take_value(&clone)
	testing.expect_value(t, kind_of(&clone), Kind.Invalid)
	testing.expect_value(t, kind_of(&moved), Kind.Array)
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&moved), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&moved), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&original), runtime.Allocator_Error.None)
}

@(test)
array_set_overwrite_gap_negative_and_alias_rejection :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	array, _ := array_value(context.allocator)
	old, old_error := string_value("old", probe_allocator(&probe))
	testing.expect_value(t, constructor_error_kind(&old_error), Error.None)
	append_error := append_take_no_displaced(&array, &old)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)

	replacement := number_value(7)
	displaced, set_error := array_set_take(&array, 0, &replacement)
	testing.expect_value(t, array_error_kind(&set_error), Array_Error.None)
	testing.expect_value(t, probe.frees, 0)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 1)
	testing.expect_value(t, kind_of(&replacement), Kind.Invalid)

	tail := boolean_value(true)
	displaced, set_error = array_set_take(&array, 3, &tail)
	testing.expect_value(t, array_error_kind(&set_error), Array_Error.None)
	testing.expect_value(t, kind_of(&displaced), Kind.Invalid)
	length, _ := array_length(&array)
	testing.expect_value(t, length, 4)
	for index in 1..<3 {
		element, ok := array_element_copy(&array, index)
		testing.expect(t, ok && kind_of(&element) == .Null)
		destroy_value(&element)
	}
	last := number_value(9)
	displaced, set_error = array_set_take(&array, -1, &last)
	testing.expect_value(t, array_error_kind(&set_error), Array_Error.None)
	destroy_value(&displaced)
	testing.expect_value(t, array_number_at(t, &array, 3), 9)

	out_of_bounds := number_value(11)
	displaced, set_error = array_set_take(&array, -5, &out_of_bounds)
	testing.expect_value(t, array_error_kind(&set_error), Array_Error.Invalid_Index)
	testing.expect_value(t, kind_of(&displaced), Kind.Invalid)
	testing.expect_value(t, kind_of(&out_of_bounds), Kind.Number)
	owned_copy, copy_ok := array_element_copy(&array, 0)
	testing.expect(t, copy_ok)
	copy_append_error := append_take_no_displaced(&array, &owned_copy)
	testing.expect_value(t, array_error_kind(&copy_append_error), Array_Error.None)
	self_error := append_take_no_displaced(&array, &array)
	testing.expect_value(t, array_error_kind(&self_error), Array_Error.Aliased_Operand)

	destroy_value(&out_of_bounds)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 1)
}

check_array_set_ceiling :: proc(
	t: ^testing.T,
	index: int,
	expected: Array_Error,
	expected_allocation_attempts: int,
) {
	backing_probe := array_growth_probe{backing = context.allocator, behavior = .Exact}
	array, constructor_error := array_value(array_growth_allocator(&backing_probe))
	testing.expect_value(t, array_error_kind(&constructor_error), Array_Error.None)
	seed := number_value(1)
	seed_error := append_take_no_displaced(&array, &seed)
	testing.expect_value(t, array_error_kind(&seed_error), Array_Error.None)
	original_payload := value_storage_of(&array).owned_payload
	allocations_before := backing_probe.allocations
	backing_probe.reject_growth_before_backing = true

	incoming_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	incoming, incoming_error := string_value("incoming", probe_allocator(&incoming_probe))
	testing.expect_value(t, constructor_error_kind(&incoming_error), Error.None)
	displaced, set_error := array_set_take(&array, index, &incoming)
	testing.expect_value(t, array_error_kind(&set_error), expected)
	testing.expect_value(t, kind_of(&displaced), Kind.Invalid)
	testing.expect(t, value_storage_of(&array).owned_payload == original_payload)
	testing.expect_value(t, array_number_at(t, &array, 0), 1)
	testing.expect_value(t, kind_of(&incoming), Kind.String)
	testing.expect_value(
		t,
		backing_probe.allocations,
		allocations_before + expected_allocation_attempts,
	)
	testing.expect_value(t, destroy_array_error(&set_error), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&incoming), runtime.Allocator_Error.None)
	testing.expect_value(t, incoming_probe.live, 0)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, backing_probe.live, 0)
	testing.expect_value(t, backing_probe.resize_calls, 0)
}

@(test)
array_set_enforces_jq_upper_index_ceiling_before_allocation :: proc(t: ^testing.T) {
	check_array_set_ceiling(t, min(int), .Invalid_Index, 0)
	check_array_set_ceiling(t, -2, .Invalid_Index, 0)
	check_array_set_ceiling(t, JQ_ARRAY_INDEX_MAX - 1, .Out_Of_Memory, 1)
	check_array_set_ceiling(t, JQ_ARRAY_INDEX_MAX, .Out_Of_Memory, 1)
	check_array_set_ceiling(t, JQ_ARRAY_INDEX_MAX + 1, .Index_Too_Large, 0)
	check_array_set_ceiling(t, max(int), .Index_Too_Large, 0)
}

@(test)
array_slice_offset_controls_ceiling_and_write_transitions :: proc(t: ^testing.T) {
	probe := array_growth_probe{backing = context.allocator, behavior = .Exact}
	source, source_error := array_value(array_growth_allocator(&probe))
	testing.expect_value(t, array_error_kind(&source_error), Array_Error.None)
	for i in 0..<4 {
		element := number_value(f64(i))
		append_error := append_take_no_displaced(&source, &element)
		testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	}

	slice, slice_error := array_slice(&source, 1, 4, array_growth_allocator(&probe))
	testing.expect_value(t, array_error_kind(&slice_error), Array_Error.None)
	testing.expect_value(t, value_storage_of(&slice).array_offset, u16(1))
	nested, nested_error := array_slice(&slice, 1, 3, array_growth_allocator(&probe))
	testing.expect_value(t, array_error_kind(&nested_error), Array_Error.None)
	testing.expect_value(t, value_storage_of(&nested).array_offset, u16(2))
	testing.expect(t, value_storage_of(&source).owned_payload == value_storage_of(&slice).owned_payload)
	testing.expect(t, value_storage_of(&slice).owned_payload == value_storage_of(&nested).owned_payload)

	// With source and slice still live, the nested view's first write takes COW
	// and resets the jq offset even though the old backing had spare capacity.
	allocations_before_cow := probe.allocations
	replacement := number_value(20)
	displaced, set_error := array_set_take(&nested, 0, &replacement)
	testing.expect_value(t, array_error_kind(&set_error), Array_Error.None)
	testing.expect_value(t, probe.allocations, allocations_before_cow + 1)
	testing.expect_value(t, value_storage_of(&nested).array_offset, u16(0))
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)

	// The detached handle now uses the base ceiling.
	probe.reject_growth_before_backing = true
	allocations_before_guard := probe.allocations
	base_ceiling := number_value(21)
	base_displaced, base_error := array_set_take(&nested, JQ_ARRAY_INDEX_MAX, &base_ceiling)
	testing.expect_value(t, array_error_kind(&base_error), Array_Error.Out_Of_Memory)
	testing.expect_value(t, kind_of(&base_displaced), Kind.Invalid)
	testing.expect_value(t, probe.allocations, allocations_before_guard + 1)
	testing.expect_value(t, kind_of(&base_ceiling), Kind.Number)
	probe.reject_growth_before_backing = false

	// Consuming the source leaves the ordinary slice as the unique backing
	// owner. Its in-capacity first write preserves offset one and allocates none.
	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	allocations_before_unique := probe.allocations
	unique_replacement := number_value(30)
	unique_displaced, unique_error := array_set_take(&slice, 0, &unique_replacement)
	testing.expect_value(t, array_error_kind(&unique_error), Array_Error.None)
	testing.expect_value(t, probe.allocations, allocations_before_unique)
	testing.expect_value(t, value_storage_of(&slice).array_offset, u16(1))
	testing.expect_value(t, destroy_value(&unique_displaced), runtime.Allocator_Error.None)

	probe.reject_growth_before_backing = true
	allocations_before_guard = probe.allocations
	offset_rejected := number_value(31)
	offset_displaced, offset_error := array_set_take(&slice, JQ_ARRAY_INDEX_MAX, &offset_rejected)
	testing.expect_value(t, array_error_kind(&offset_error), Array_Error.Index_Too_Large)
	testing.expect_value(t, kind_of(&offset_displaced), Kind.Invalid)
	testing.expect_value(t, probe.allocations, allocations_before_guard)
	testing.expect_value(t, kind_of(&offset_rejected), Kind.Number)

	testing.expect_value(t, destroy_value(&base_ceiling), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&offset_rejected), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&nested), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&slice), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	testing.expect_value(t, probe.resize_calls, 0)
}

@(test)
array_slice_offset_resets_on_growth_and_sixteen_bit_overflow :: proc(t: ^testing.T) {
	base, base_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&base_error), Array_Error.None)
	defer destroy_value(&base)
	last := null_value()
	displaced, extend_error := array_set_take(&base, 65536, &last)
	testing.expect_value(t, array_error_kind(&extend_error), Array_Error.None)
	testing.expect_value(t, kind_of(&displaced), Kind.Invalid)

	tail, tail_error := array_slice(&base, 65535, 65537, context.allocator)
	testing.expect_value(t, array_error_kind(&tail_error), Array_Error.None)
	testing.expect_value(t, value_storage_of(&tail).array_offset, u16(65535))

	probe := array_growth_probe{backing = context.allocator, behavior = .Exact}
	overflowed, overflow_error := array_slice(
		&tail,
		1,
		2,
		array_growth_allocator(&probe),
	)
	testing.expect_value(t, array_error_kind(&overflow_error), Array_Error.None)
	testing.expect_value(t, value_storage_of(&overflowed).array_offset, u16(0))

	// A slice at the end of a full backing has no spare capacity. Its append
	// therefore forces replacement and resets the offset.
	full, full_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&full_error), Array_Error.None)
	for i in 0..<ARRAY_INITIAL_CAPACITY {
		element := number_value(f64(i))
		append_error := append_take_no_displaced(&full, &element)
		testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	}
	growth, growth_error := array_slice(
		&full,
		ARRAY_INITIAL_CAPACITY - 1,
		ARRAY_INITIAL_CAPACITY,
		array_growth_allocator(&probe),
	)
	testing.expect_value(t, array_error_kind(&growth_error), Array_Error.None)
	testing.expect_value(
		t,
		value_storage_of(&growth).array_offset,
		u16(ARRAY_INITIAL_CAPACITY - 1),
	)
	testing.expect_value(t, value_storage_of(&growth).owned_payload.array_capacity, ARRAY_INITIAL_CAPACITY)
	appended := null_value()
	append_error := append_take_no_displaced(&growth, &appended)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, value_storage_of(&growth).array_offset, u16(0))

	probe.reject_growth_before_backing = true
	allocations_before_guard := probe.allocations
	incoming := number_value(1)
	guard_displaced, set_error := array_set_take(&overflowed, JQ_ARRAY_INDEX_MAX, &incoming)
	testing.expect_value(t, array_error_kind(&set_error), Array_Error.Out_Of_Memory)
	testing.expect_value(t, kind_of(&guard_displaced), Kind.Invalid)
	testing.expect_value(t, probe.allocations, allocations_before_guard + 1)
	testing.expect_value(t, kind_of(&incoming), Kind.Number)

	testing.expect_value(t, destroy_value(&incoming), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&tail), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&overflowed), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&growth), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&full), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	testing.expect_value(t, probe.resize_calls, 0)
}

@(test)
spare_capacity_slice_append_preserves_offset_and_oracle_ceiling :: proc(t: ^testing.T) {
	probe := array_growth_probe{backing = context.allocator, behavior = .Exact}
	source, source_error := array_value(array_growth_allocator(&probe))
	testing.expect_value(t, array_error_kind(&source_error), Array_Error.None)
	for i in 0..<2 {
		element := number_value(f64(i))
		append_error := append_take_no_displaced(&source, &element)
		testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	}
	slice, slice_error := array_slice(&source, 1, 2, array_growth_allocator(&probe))
	testing.expect_value(t, array_error_kind(&slice_error), Array_Error.None)
	testing.expect_value(t, value_storage_of(&slice).array_offset, u16(1))
	testing.expect_value(
		t,
		value_storage_of(&slice).owned_payload.array_capacity,
		ARRAY_INITIAL_CAPACITY,
	)
	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)

	allocations_before_append := probe.allocations
	appended := number_value(2)
	append_error := append_take_no_displaced(&slice, &appended)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, probe.allocations, allocations_before_append)
	testing.expect_value(t, value_storage_of(&slice).array_offset, u16(1))

	allocations_before_guard := probe.allocations
	guarded := number_value(0)
	displaced, guard_error := array_set_take(&slice, JQ_ARRAY_INDEX_MAX, &guarded)
	testing.expect_value(t, array_error_kind(&guard_error), Array_Error.Index_Too_Large)
	testing.expect_value(t, kind_of(&displaced), Kind.Invalid)
	testing.expect_value(t, probe.allocations, allocations_before_guard)
	testing.expect_value(t, kind_of(&guarded), Kind.Number)
	testing.expect_value(t, destroy_value(&guarded), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&slice), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	testing.expect_value(t, probe.resize_calls, 0)
}

@(test)
failed_slice_growth_preserves_offset_capacity_and_retry_owner :: proc(t: ^testing.T) {
	probe := array_growth_probe{backing = context.allocator, behavior = .Exact}
	source, source_error := array_value(array_growth_allocator(&probe))
	testing.expect_value(t, array_error_kind(&source_error), Array_Error.None)
	for i in 0..<ARRAY_INITIAL_CAPACITY {
		element := number_value(f64(i))
		append_error := append_take_no_displaced(&source, &element)
		testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	}
	slice, slice_error := array_slice(
		&source,
		ARRAY_INITIAL_CAPACITY - 1,
		ARRAY_INITIAL_CAPACITY,
		array_growth_allocator(&probe),
	)
	testing.expect_value(t, array_error_kind(&slice_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	original_payload := value_storage_of(&slice).owned_payload
	original_capacity := original_payload.array_capacity
	original_offset := value_storage_of(&slice).array_offset
	testing.expect_value(t, original_capacity, ARRAY_INITIAL_CAPACITY)
	testing.expect_value(t, original_offset, u16(ARRAY_INITIAL_CAPACITY - 1))

	// The old backing Free and the immediate replacement cleanup both fail.
	// The error owns only the duplicate raw allocation; the slice stays live.
	probe.free_failures_remaining = 2
	incoming := number_value(4)
	failed_error := append_take_no_displaced(&slice, &incoming)
	testing.expect_value(t, array_error_kind(&failed_error), Array_Error.Cleanup_Failed)
	testing.expect(t, array_error_needs_cleanup(&failed_error))
	testing.expect(t, value_storage_of(&slice).owned_payload == original_payload)
	testing.expect_value(t, original_payload.array_capacity, original_capacity)
	testing.expect_value(t, value_storage_of(&slice).array_offset, original_offset)
	testing.expect_value(t, value_storage_of(&slice).array_length, 1)
	testing.expect_value(t, array_number_at(t, &slice, 0), f64(ARRAY_INITIAL_CAPACITY - 1))
	testing.expect_value(t, kind_of(&incoming), Kind.Number)

	allocations_before_guard := probe.allocations
	guarded := number_value(5)
	displaced, guard_error := array_set_take(&slice, JQ_ARRAY_INDEX_MAX, &guarded)
	testing.expect_value(t, array_error_kind(&guard_error), Array_Error.Index_Too_Large)
	testing.expect_value(t, kind_of(&displaced), Kind.Invalid)
	testing.expect_value(t, probe.allocations, allocations_before_guard)
	testing.expect_value(t, array_number_at(t, &slice, 0), f64(ARRAY_INITIAL_CAPACITY - 1))
	testing.expect_value(t, destroy_value(&guarded), runtime.Allocator_Error.None)

	moved_error := take_array_error(&failed_error)
	testing.expect_value(t, array_error_kind(&failed_error), Array_Error.None)
	testing.expect_value(t, destroy_array_error(&moved_error), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_array_error(&moved_error), runtime.Allocator_Error.None)
	retry_error := append_take_no_displaced(&slice, &incoming)
	testing.expect_value(t, array_error_kind(&retry_error), Array_Error.None)
	testing.expect_value(t, kind_of(&incoming), Kind.Invalid)
	testing.expect_value(t, value_storage_of(&slice).array_offset, u16(0))
	testing.expect_value(t, value_storage_of(&slice).array_length, 2)
	testing.expect_value(t, destroy_value(&slice), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	testing.expect_value(t, probe.resize_calls, 0)
	testing.expect(t, !probe.wrong_free_size)
}

@(test)
array_slice_shares_backing_with_jq_boundaries :: proc(t: ^testing.T) {
	source, _ := array_value(context.allocator)
	for i in 0..<5 {
		element := number_value(f64(i))
		append_take_no_displaced(&source, &element)
	}
	middle, middle_error := array_slice(&source, 1, -1, context.allocator)
	empty, empty_error := array_slice(&source, 4, 2, context.allocator)
	clamped, clamped_error := array_slice(&source, -99, 99, context.allocator)
	defer destroy_value(&source)
	defer destroy_value(&middle)
	defer destroy_value(&empty)
	defer destroy_value(&clamped)
	testing.expect_value(t, array_error_kind(&middle_error), Array_Error.None)
	testing.expect_value(t, array_error_kind(&empty_error), Array_Error.None)
	testing.expect_value(t, array_error_kind(&clamped_error), Array_Error.None)
	testing.expect(t, value_storage_of(&source).owned_payload == value_storage_of(&middle).owned_payload)
	middle_length, _ := array_length(&middle)
	empty_length, _ := array_length(&empty)
	clamped_length, _ := array_length(&clamped)
	testing.expect_value(t, middle_length, 3)
	testing.expect_value(t, empty_length, 0)
	testing.expect_value(t, value_storage_of(&empty).array_offset, u16(0))
	testing.expect_value(t, clamped_length, 5)
	testing.expect_value(t, array_number_at(t, &middle, 0), 1)
	testing.expect_value(t, array_number_at(t, &middle, 2), 3)
	testing.expect(t, values_equal(&source, &clamped))

	replacement := number_value(88)
	displaced, set_error := array_set_take(&middle, 0, &replacement)
	testing.expect_value(t, array_error_kind(&set_error), Array_Error.None)
	destroy_value(&displaced)
	testing.expect_value(t, array_number_at(t, &source, 1), 1)
	testing.expect_value(t, array_number_at(t, &middle, 0), 88)
}

@(test)
unique_slice_gap_write_exposes_initialized_hidden_suffix :: proc(t: ^testing.T) {
	first_source, _ := array_value(context.allocator)
	for i in 0..<4 {
		element := number_value(f64(i))
		append_take_no_displaced(&first_source, &element)
	}
	first, first_slice_error := array_slice(&first_source, 1, 2, context.allocator)
	testing.expect_value(t, array_error_kind(&first_slice_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&first_source), runtime.Allocator_Error.None)
	first_incoming := number_value(9)
	first_displaced, first_error := array_set_take(&first, 2, &first_incoming)
	testing.expect_value(t, array_error_kind(&first_error), Array_Error.None)
	testing.expect_value(t, array_number_at(t, &first, 0), 1)
	testing.expect_value(t, array_number_at(t, &first, 1), 2)
	testing.expect_value(t, array_number_at(t, &first, 2), 9)
	testing.expect_value(t, destroy_value(&first_displaced), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&first), runtime.Allocator_Error.None)

	second_source, _ := array_value(context.allocator)
	for i in 0..<4 {
		element := number_value(f64(i))
		append_take_no_displaced(&second_source, &element)
	}
	second, second_slice_error := array_slice(&second_source, 1, 2, context.allocator)
	testing.expect_value(t, array_error_kind(&second_slice_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&second_source), runtime.Allocator_Error.None)
	second_incoming := number_value(9)
	second_displaced, second_error := array_set_take(&second, 3, &second_incoming)
	testing.expect_value(t, array_error_kind(&second_error), Array_Error.None)
	testing.expect_value(t, kind_of(&second_displaced), Kind.Invalid)
	testing.expect_value(t, array_number_at(t, &second, 0), 1)
	testing.expect_value(t, array_number_at(t, &second, 1), 2)
	testing.expect_value(t, array_number_at(t, &second, 2), 3)
	testing.expect_value(t, array_number_at(t, &second, 3), 9)
	testing.expect_value(t, destroy_value(&second), runtime.Allocator_Error.None)

	append_source, _ := array_value(context.allocator)
	for i in 0..<4 {
		element := number_value(f64(i))
		append_take_no_displaced(&append_source, &element)
	}
	appended, append_slice_error := array_slice(&append_source, 1, 2, context.allocator)
	testing.expect_value(t, array_error_kind(&append_slice_error), Array_Error.None)
	destroy_value(&append_source)
	append_incoming := number_value(9)
	append_displaced, append_error := array_append_take(&appended, &append_incoming)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, array_number_at(t, &appended, 0), 1)
	testing.expect_value(t, array_number_at(t, &appended, 1), 9)
	displaced_number, displaced_ok := number_value_get(&append_displaced)
	testing.expect(t, displaced_ok)
	testing.expect_value(t, displaced_number, 2)
	destroy_value(&append_displaced)
	destroy_value(&appended)
}

@(test)
array_capacity_matches_jq_initial_and_replacement_thresholds :: proc(t: ^testing.T) {
	probe := array_growth_probe{backing = context.allocator, behavior = .Exact}
	array, constructor_error := array_value(array_growth_allocator(&probe))
	testing.expect_value(t, array_error_kind(&constructor_error), Array_Error.None)
	testing.expect_value(t, probe.allocations, 1)
	testing.expect_value(t, value_storage_of(&array).owned_payload.array_capacity, 16)

	fill_array_to_initial_capacity(t, &array)
	testing.expect_value(t, probe.allocations, 1)
	seventeenth := number_value(16)
	seventeenth_error := append_take_no_displaced(&array, &seventeenth)
	testing.expect_value(t, array_error_kind(&seventeenth_error), Array_Error.None)
	testing.expect_value(t, probe.allocations, 2)
	testing.expect_value(t, value_storage_of(&array).owned_payload.array_capacity, 25)
	for i in 17..<25 {
		element := number_value(f64(i))
		append_take_no_displaced(&array, &element)
	}
	testing.expect_value(t, probe.allocations, 2)
	twenty_sixth := number_value(25)
	twenty_sixth_error := append_take_no_displaced(&array, &twenty_sixth)
	testing.expect_value(t, array_error_kind(&twenty_sixth_error), Array_Error.None)
	testing.expect_value(t, probe.allocations, 3)
	testing.expect_value(t, value_storage_of(&array).owned_payload.array_capacity, 39)
	testing.expect_value(t, probe.resize_calls, 0)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)

	cow_probe := array_growth_probe{backing = context.allocator, behavior = .Exact}
	shared, _ := array_value(array_growth_allocator(&cow_probe))
	for i in 0..<4 {
		element := number_value(f64(i))
		append_take_no_displaced(&shared, &element)
	}
	detached := clone_value(&shared)
	incoming := number_value(4)
	append_take_no_displaced(&detached, &incoming)
	testing.expect_value(t, value_storage_of(&detached).owned_payload.array_capacity, 7)
	testing.expect_value(t, cow_probe.allocations, 2)
	destroy_value(&shared)
	destroy_value(&detached)
	testing.expect_value(t, cow_probe.live, 0)
}

@(test)
array_owned_getter_prevents_interior_cycle_and_self_append_is_cow :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	child, _ := array_value(probe_allocator(&probe))
	outer, _ := array_value(probe_allocator(&probe))
	append_take_no_displaced(&outer, &child)
	outer_copy := clone_value(&outer)
	child_copy, get_ok := array_element_copy(&outer, 0)
	testing.expect(t, get_ok)
	child_append_error := append_take_no_displaced(&child_copy, &outer_copy)
	testing.expect_value(t, array_error_kind(&child_append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&outer), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&child_copy), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	testing.expect(t, !probe.wrong_free_size)

	self, _ := array_value(probe_allocator(&probe))
	one := number_value(1)
	append_take_no_displaced(&self, &one)
	self_copy := clone_value(&self)
	old_backing := value_storage_of(&self).owned_payload
	self_error := append_take_no_displaced(&self, &self_copy)
	testing.expect_value(t, array_error_kind(&self_error), Array_Error.None)
	testing.expect(t, value_storage_of(&self).owned_payload != old_backing)
	nested, nested_ok := array_element_copy(&self, 1)
	testing.expect(t, nested_ok)
	testing.expect_value(t, array_number_at(t, &nested, 0), 1)
	testing.expect_value(t, destroy_value(&nested), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&self), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
}

@(test)
multiple_array_views_release_backing_in_either_order :: proc(t: ^testing.T) {
	orders := [2]bool{false, true}
	for reverse in orders {
		probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
		source, _ := array_value(probe_allocator(&probe))
		for i in 0..<4 {
			element := number_value(f64(i))
			append_take_no_displaced(&source, &element)
		}
		first, first_error := array_slice(&source, 1, 4, context.allocator)
		second, second_error := array_slice(&source, 2, 4, context.allocator)
		testing.expect_value(t, array_error_kind(&first_error), Array_Error.None)
		testing.expect_value(t, array_error_kind(&second_error), Array_Error.None)
		testing.expect(t, value_storage_of(&source).owned_payload == value_storage_of(&first).owned_payload)
		testing.expect(t, value_storage_of(&first).owned_payload == value_storage_of(&second).owned_payload)
		if reverse {
			destroy_value(&second)
			destroy_value(&source)
			destroy_value(&first)
		} else {
			destroy_value(&source)
			destroy_value(&first)
			destroy_value(&second)
		}
		testing.expect_value(t, probe.live, 0)
		testing.expect(t, !probe.wrong_free_size)
	}
}

@(test)
same_backing_different_views_compare_by_visible_elements :: proc(t: ^testing.T) {
	source, _ := array_value(context.allocator)
	zero := number_value(0)
	one := number_value(1)
	append_take_no_displaced(&source, &zero)
	append_take_no_displaced(&source, &one)
	first, first_error := array_slice(&source, 0, 1, context.allocator)
	second, second_error := array_slice(&source, 1, 2, context.allocator)
	testing.expect_value(t, array_error_kind(&first_error), Array_Error.None)
	testing.expect_value(t, array_error_kind(&second_error), Array_Error.None)
	testing.expect(t, value_storage_of(&first).owned_payload == value_storage_of(&second).owned_payload)
	testing.expect(t, !values_equal(&first, &second))
	first_clone := clone_value(&first)
	testing.expect(t, values_equal(&first, &first_clone))
	destroy_value(&source)
	destroy_value(&first)
	destroy_value(&second)
	destroy_value(&first_clone)
}

@(test)
failed_unique_slice_growth_retries_and_retires_hidden_owners :: proc(t: ^testing.T) {
	backing_probe := array_growth_probe{backing = context.allocator, behavior = .Exact}
	element_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	source, source_error := array_value(array_growth_allocator(&backing_probe))
	testing.expect_value(t, array_error_kind(&source_error), Array_Error.None)
	names := [4]string{"zero", "one", "two", "three"}
	for name in names {
		element, element_error := string_value(name, probe_allocator(&element_probe))
		testing.expect_value(t, constructor_error_kind(&element_error), Error.None)
		append_take_no_displaced(&source, &element)
	}
	slice, slice_error := array_slice(&source, 1, 2, context.allocator)
	testing.expect_value(t, array_error_kind(&slice_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	original_backing := value_storage_of(&slice).owned_payload
	original_offset := value_storage_of(&slice).array_offset
	incoming, incoming_error := string_value("incoming", probe_allocator(&element_probe))
	testing.expect_value(t, constructor_error_kind(&incoming_error), Error.None)

	backing_probe.free_failures_remaining = 2
	failed_displaced, failed_error := array_set_take(&slice, 15, &incoming)
	testing.expect_value(t, array_error_kind(&failed_error), Array_Error.Cleanup_Failed)
	testing.expect_value(t, kind_of(&failed_displaced), Kind.Invalid)
	testing.expect(t, array_error_needs_cleanup(&failed_error))
	testing.expect(t, value_storage_of(&slice).owned_payload == original_backing)
	testing.expect_value(t, original_backing.array_initialized_length, 4)
	testing.expect_value(t, value_storage_of(&slice).array_offset, original_offset)
	testing.expect_value(t, value_storage_of(&slice).array_length, 1)
	testing.expect_value(t, kind_of(&incoming), Kind.String)
	one, one_ok := array_element_copy(&slice, 0)
	one_text, one_text_ok := string_borrowed(&one)
	testing.expect(t, one_ok && one_text_ok && one_text == "one")
	destroy_value(&one)

	allocations_before_ceiling := backing_probe.allocations
	guarded := number_value(1)
	guarded_displaced, guarded_error := array_set_take(&slice, JQ_ARRAY_INDEX_MAX, &guarded)
	testing.expect_value(t, array_error_kind(&guarded_error), Array_Error.Index_Too_Large)
	testing.expect_value(t, kind_of(&guarded_displaced), Kind.Invalid)
	testing.expect_value(t, backing_probe.allocations, allocations_before_ceiling)
	destroy_value(&guarded)

	moved_error := take_array_error(&failed_error)
	testing.expect_value(t, destroy_array_error(&moved_error), runtime.Allocator_Error.None)
	backing_probe.behavior = .Exact
	retry_displaced, retry_error := array_set_take(&slice, 15, &incoming)
	testing.expect_value(t, array_error_kind(&retry_error), Array_Error.None)
	testing.expect_value(t, kind_of(&retry_displaced), Kind.Invalid)
	testing.expect_value(t, value_storage_of(&slice).array_offset, u16(0))
	testing.expect_value(t, value_storage_of(&slice).array_length, 16)
	testing.expect_value(t, value_storage_of(&slice).owned_payload.array_retired_count, 3)
	testing.expect_value(t, destroy_value(&slice), runtime.Allocator_Error.None)
	testing.expect_value(t, element_probe.live, 0)
	testing.expect_value(t, backing_probe.live, 0)
	testing.expect(t, !backing_probe.wrong_free_size)
}

@(test)
array_recursive_equality_and_deep_cleanup :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	inner, _ := array_value(probe_allocator(&probe))
	leaf, _ := string_value("leaf", probe_allocator(&probe))
	append_take_no_displaced(&inner, &leaf)
	outer, _ := array_value(probe_allocator(&probe))
	append_take_no_displaced(&outer, &inner)
	clone := clone_value(&outer)
	testing.expect(t, values_equal(&outer, &clone))

	replacement := null_value()
	inner_owned, inner_ok := array_element_copy(&clone, 0)
	testing.expect(t, inner_ok)
	displaced_leaf, leaf_set_error := array_set_take(&inner_owned, 0, &replacement)
	testing.expect_value(t, array_error_kind(&leaf_set_error), Array_Error.None)
	destroy_value(&displaced_leaf)
	displaced_inner, inner_set_error := array_set_take(&clone, 0, &inner_owned)
	testing.expect_value(t, array_error_kind(&inner_set_error), Array_Error.None)
	destroy_value(&displaced_inner)
	testing.expect(t, !values_equal(&outer, &clone))

	testing.expect_value(t, destroy_value(&outer), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.allocations, probe.frees)
}

@(test)
array_element_retention_has_no_partial_allocation_site :: proc(t: ^testing.T) {
	element_probe := allocator_probe{backing = context.allocator, fail_after = 1}
	array, _ := array_value(context.allocator)
	element, element_error := string_value("retained", probe_allocator(&element_probe))
	testing.expect_value(t, constructor_error_kind(&element_error), Error.None)
	append_take_no_displaced(&array, &element)
	clone := clone_value(&array)
	incoming := null_value()
	append_error := append_take_no_displaced(&clone, &incoming)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	slice, slice_error := array_slice(&array, 0, 1, context.allocator)
	testing.expect_value(t, array_error_kind(&slice_error), Array_Error.None)
	// clone, COW, and slice retain the string payload; none asks its allocator
	// for element-by-element storage, so fail_after=1 is never reached.
	testing.expect_value(t, element_probe.allocations, 1)
	destroy_value(&array)
	destroy_value(&clone)
	destroy_value(&slice)
	testing.expect_value(t, element_probe.frees, 1)
}

array_failure_probe :: struct {
	backing: runtime.Allocator,
	operation: int,
	fail_at: int,
	allocations: int,
	frees: int,
}

array_failure_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	probe := cast(^array_failure_probe)data
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
		current := probe.operation
		probe.operation += 1
		if current == probe.fail_at {
			return nil, .Out_Of_Memory
		}
		if mode == .Alloc || mode == .Alloc_Non_Zeroed {
			probe.allocations += 1
		}
	case .Free:
		probe.frees += 1
	}
	return probe.backing.procedure(
		probe.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

array_failure_allocator :: proc(probe: ^array_failure_probe) -> runtime.Allocator {
	return {procedure = array_failure_allocator_proc, data = probe}
}

array_growth_behavior :: enum {
	Exact,
	Nil_Success,
	Short_Success,
	Out_Of_Memory,
	Mode_Not_Implemented,
}

array_growth_probe :: struct {
	backing:                      runtime.Allocator,
	behavior:                     array_growth_behavior,
	resize_calls:                 int,
	allocations:                  int,
	frees:                        int,
	live:                         int,
	free_failures_remaining:      int,
	wrong_free_size:              bool,
	reject_growth_before_backing: bool,
	tracked_pointers:             [16]rawptr,
	tracked_sizes:                [16]int,
	tracked_count:                int,
}

array_growth_probe_track :: proc(probe: ^array_growth_probe, memory: []byte) {
	if len(memory) == 0 {
		return
	}
	assert(probe.tracked_count < len(probe.tracked_pointers))
	probe.tracked_pointers[probe.tracked_count] = raw_data(memory)
	probe.tracked_sizes[probe.tracked_count] = len(memory)
	probe.tracked_count += 1
	probe.live += 1
}

array_growth_probe_find :: proc(probe: ^array_growth_probe, pointer: rawptr) -> int {
	for i in 0..<probe.tracked_count {
		if probe.tracked_pointers[i] == pointer {
			return i
		}
	}
	return -1
}

array_growth_probe_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	probe := cast(^array_growth_probe)data
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		probe.allocations += 1
		request_size := size
		if probe.allocations > 1 {
			if probe.reject_growth_before_backing {
				return nil, .Out_Of_Memory
			}
			switch probe.behavior {
			case .Nil_Success:
				return nil, nil
			case .Mode_Not_Implemented:
				return nil, .Mode_Not_Implemented
			case .Short_Success:
				request_size -= 1
			case .Exact, .Out_Of_Memory:
			}
		}
		memory, err := probe.backing.procedure(
			probe.backing.data,
			mode,
			request_size,
			alignment,
			old_memory,
			old_size,
			location,
		)
		if err == nil && len(memory) > 0 {
			array_growth_probe_track(probe, memory)
		}
		if probe.allocations > 1 && probe.behavior == .Out_Of_Memory && err == nil {
			return memory, .Out_Of_Memory
		}
		return memory, err
	case .Resize, .Resize_Non_Zeroed:
		probe.resize_calls += 1
		return nil, .Mode_Not_Implemented
	case .Free:
		probe.frees += 1
		at := array_growth_probe_find(probe, old_memory)
		if at < 0 || probe.tracked_sizes[at] != old_size {
			probe.wrong_free_size = true
		}
		if probe.free_failures_remaining > 0 {
			probe.free_failures_remaining -= 1
			return nil, .Invalid_Pointer
		}
		memory, err := probe.backing.procedure(
			probe.backing.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			location,
		)
		if err == nil && at >= 0 {
			last := probe.tracked_count - 1
			probe.tracked_pointers[at] = probe.tracked_pointers[last]
			probe.tracked_sizes[at] = probe.tracked_sizes[last]
			probe.tracked_count = last
			probe.live -= 1
		}
		return memory, err
	}
	return probe.backing.procedure(
		probe.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

array_growth_allocator :: proc(probe: ^array_growth_probe) -> runtime.Allocator {
	return {procedure = array_growth_probe_proc, data = probe}
}

check_failed_growth_is_retryable :: proc(
	t: ^testing.T,
	behavior: array_growth_behavior,
	expected: Array_Error,
) {
	probe := array_growth_probe{backing = context.allocator, behavior = behavior}
	array, constructor_error := array_value(array_growth_allocator(&probe))
	testing.expect_value(t, array_error_kind(&constructor_error), Array_Error.None)
	fill_array_to_initial_capacity(t, &array)
	original_payload := value_storage_of(&array).owned_payload
	incoming := number_value(7)
	mutation_error := append_take_no_displaced(&array, &incoming)
	testing.expect_value(t, array_error_kind(&mutation_error), expected)
	testing.expect(t, value_storage_of(&array).owned_payload == original_payload)
	length, length_ok := array_length(&array)
	testing.expect(t, length_ok && length == ARRAY_INITIAL_CAPACITY)
	testing.expect_value(t, kind_of(&incoming), Kind.Number)
	testing.expect_value(t, destroy_array_error(&mutation_error), runtime.Allocator_Error.None)

	probe.behavior = .Exact
	retry_error := append_take_no_displaced(&array, &incoming)
	testing.expect_value(t, array_error_kind(&retry_error), Array_Error.None)
	testing.expect_value(t, kind_of(&incoming), Kind.Invalid)
	testing.expect_value(t, array_number_at(t, &array, ARRAY_INITIAL_CAPACITY), 7)
	testing.expect(t, value_storage_of(&array).owned_payload != original_payload)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	testing.expect_value(t, probe.resize_calls, 0)
	testing.expect(t, !probe.wrong_free_size)
}

@(test)
array_growth_failure_modes_preserve_operands_and_retry :: proc(t: ^testing.T) {
	check_failed_growth_is_retryable(t, .Nil_Success, .Out_Of_Memory)
	check_failed_growth_is_retryable(t, .Short_Success, .Out_Of_Memory)
	check_failed_growth_is_retryable(t, .Out_Of_Memory, .Out_Of_Memory)
	check_failed_growth_is_retryable(t, .Mode_Not_Implemented, .Allocator_Unsupported)
}

@(test)
failed_nonempty_unique_growth_preserves_every_owner_and_retries :: proc(t: ^testing.T) {
	backing_probe := array_growth_probe{backing = context.allocator, behavior = .Exact}
	element_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	incoming_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	array, constructor_error := array_value(array_growth_allocator(&backing_probe))
	testing.expect_value(t, array_error_kind(&constructor_error), Array_Error.None)

	expected := [4]string{"zero", "one", "two", "three"}
	for name in expected {
		element, element_error := string_value(name, probe_allocator(&element_probe))
		testing.expect_value(t, constructor_error_kind(&element_error), Error.None)
		append_error := append_take_no_displaced(&array, &element)
		testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	}
	fill_array_to_initial_capacity(t, &array)
	original_payload := value_storage_of(&array).owned_payload
	testing.expect_value(t, value_storage_of(&array).array_length, ARRAY_INITIAL_CAPACITY)
	testing.expect_value(t, original_payload.array_capacity, ARRAY_INITIAL_CAPACITY)

	incoming, incoming_error := string_value("incoming", probe_allocator(&incoming_probe))
	testing.expect_value(t, constructor_error_kind(&incoming_error), Error.None)
	backing_probe.behavior = .Short_Success
	backing_probe.free_failures_remaining = 1
	failed_error := append_take_no_displaced(&array, &incoming)
	testing.expect_value(t, array_error_kind(&failed_error), Array_Error.Cleanup_Failed)
	testing.expect_value(t, array_error_cause(&failed_error), Array_Error.Out_Of_Memory)
	testing.expect(t, array_error_needs_cleanup(&failed_error))
	testing.expect(t, value_storage_of(&array).owned_payload == original_payload)
	testing.expect_value(t, backing_probe.live, 2)
	testing.expect_value(t, element_probe.live, 4)
	testing.expect_value(t, incoming_probe.live, 1)
	for name, i in expected {
		element, ok := array_element_copy(&array, i)
		view, string_ok := string_borrowed(&element)
		testing.expect(t, ok && string_ok && view == name)
		destroy_value(&element)
	}
	incoming_view, incoming_ok := string_borrowed(&incoming)
	testing.expect(t, incoming_ok && incoming_view == "incoming")

	moved_error := take_array_error(&failed_error)
	testing.expect_value(t, array_error_kind(&failed_error), Array_Error.None)
	testing.expect_value(t, destroy_array_error(&moved_error), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_array_error(&moved_error), runtime.Allocator_Error.None)
	testing.expect_value(t, backing_probe.live, 1)

	backing_probe.behavior = .Exact
	retry_error := append_take_no_displaced(&array, &incoming)
	testing.expect_value(t, array_error_kind(&retry_error), Array_Error.None)
	testing.expect_value(t, kind_of(&incoming), Kind.Invalid)
	testing.expect(t, value_storage_of(&array).owned_payload != original_payload)
	retried_length, retried_ok := array_length(&array)
	testing.expect(t, retried_ok && retried_length == ARRAY_INITIAL_CAPACITY + 1)
	last, last_ok := array_element_copy(&array, ARRAY_INITIAL_CAPACITY)
	last_view, last_string_ok := string_borrowed(&last)
	testing.expect(t, last_ok && last_string_ok && last_view == "incoming")
	destroy_value(&last)

	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, element_probe.live, 0)
	testing.expect_value(t, incoming_probe.live, 0)
	testing.expect_value(t, backing_probe.live, 0)
	testing.expect_value(t, backing_probe.resize_calls, 0)
	testing.expect(t, !backing_probe.wrong_free_size)
}

@(test)
array_growth_relocation_and_cleanup_owner_are_exact :: proc(t: ^testing.T) {
	relocated_probe := array_growth_probe{
		backing = context.allocator,
		behavior = .Exact,
	}
	relocated, relocated_constructor_error := array_value(array_growth_allocator(&relocated_probe))
	testing.expect_value(t, array_error_kind(&relocated_constructor_error), Array_Error.None)
	fill_array_to_initial_capacity(t, &relocated)
	original_payload := value_storage_of(&relocated).owned_payload
	relocated_element := number_value(1)
	relocated_error := append_take_no_displaced(&relocated, &relocated_element)
	testing.expect_value(t, array_error_kind(&relocated_error), Array_Error.None)
	testing.expect(t, value_storage_of(&relocated).owned_payload != original_payload)
	testing.expect_value(t, relocated_probe.resize_calls, 0)
	testing.expect_value(t, relocated_probe.frees, 1)
	testing.expect_value(t, destroy_value(&relocated), runtime.Allocator_Error.None)
	testing.expect_value(t, relocated_probe.frees, 2)
	testing.expect_value(t, relocated_probe.live, 0)
	testing.expect(t, !relocated_probe.wrong_free_size)

	cleanup_probe := array_growth_probe{
		backing = context.allocator,
		behavior = .Exact,
		free_failures_remaining = 2,
	}
	array, constructor_error := array_value(array_growth_allocator(&cleanup_probe))
	testing.expect_value(t, array_error_kind(&constructor_error), Array_Error.None)
	fill_array_to_initial_capacity(t, &array)
	old_payload := value_storage_of(&array).owned_payload
	incoming := number_value(2)
	cleanup_error := append_take_no_displaced(&array, &incoming)
	testing.expect_value(t, array_error_kind(&cleanup_error), Array_Error.Cleanup_Failed)
	testing.expect(t, array_error_needs_cleanup(&cleanup_error))
	testing.expect(t, value_storage_of(&array).owned_payload == old_payload)
	length, length_ok := array_length(&array)
	testing.expect(t, length_ok && length == ARRAY_INITIAL_CAPACITY)
	testing.expect_value(t, kind_of(&incoming), Kind.Number)
	moved_error := take_array_error(&cleanup_error)
	testing.expect_value(t, array_error_kind(&cleanup_error), Array_Error.None)
	testing.expect_value(t, destroy_array_error(&moved_error), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_array_error(&moved_error), runtime.Allocator_Error.None)
	testing.expect_value(t, cleanup_probe.live, 1)
	retry_error := append_take_no_displaced(&array, &incoming)
	testing.expect_value(t, array_error_kind(&retry_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, cleanup_probe.live, 0)
	testing.expect_value(t, cleanup_probe.resize_calls, 0)
	testing.expect_value(t, cleanup_probe.frees, 5)
	testing.expect(t, !cleanup_probe.wrong_free_size)
}

@(test)
array_constructor_exactness_uses_owning_cleanup_contract :: proc(t: ^testing.T) {
	nil_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		nil_success = true,
	}
	nil_array, nil_error := array_value(probe_allocator(&nil_probe))
	testing.expect_value(t, kind_of(&nil_array), Kind.Invalid)
	testing.expect_value(t, array_error_kind(&nil_error), Array_Error.Out_Of_Memory)
	testing.expect(t, !array_error_needs_cleanup(&nil_error))
	testing.expect_value(t, nil_probe.frees, 0)

	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
		free_failures_remaining = 1,
	}
	retry_array, retry_error := array_value(probe_allocator(&retry_probe))
	testing.expect_value(t, kind_of(&retry_array), Kind.Invalid)
	testing.expect_value(t, array_error_kind(&retry_error), Array_Error.Cleanup_Failed)
	testing.expect_value(t, array_error_cause(&retry_error), Array_Error.Out_Of_Memory)
	testing.expect(t, array_error_needs_cleanup(&retry_error))
	testing.expect_value(t, retry_probe.live, 1)
	moved_error := take_array_error(&retry_error)
	testing.expect_value(t, array_error_kind(&retry_error), Array_Error.None)
	testing.expect_value(t, destroy_array_error(&moved_error), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_array_error(&moved_error), runtime.Allocator_Error.None)
	testing.expect_value(t, retry_probe.live, 0)

	arena: runtime.Arena
	init_error := runtime.arena_init(&arena, 4096, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error.None)
	if init_error == nil {
		bulk_probe := allocator_probe{
			backing = runtime.arena_allocator(&arena),
			fail_after = max(int),
			short_success = true,
		}
		bulk_array, bulk_error := array_value(probe_allocator(&bulk_probe))
		testing.expect_value(t, kind_of(&bulk_array), Kind.Invalid)
		testing.expect_value(t, array_error_kind(&bulk_error), Array_Error.Out_Of_Memory)
		testing.expect(t, !array_error_needs_cleanup(&bulk_error))
		testing.expect_value(t, bulk_probe.frees, 1)
		runtime.arena_destroy(&arena)
	}
}

@(test)
array_growth_cow_and_slice_transfer_failed_allocation_cleanup :: proc(t: ^testing.T) {
	growth_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	growing, constructor_error := array_value(probe_allocator(&growth_probe))
	testing.expect_value(t, array_error_kind(&constructor_error), Array_Error.None)
	fill_array_to_initial_capacity(t, &growing)
	growth_probe.short_success = true
	growth_probe.free_failures_remaining = 1
	growth_incoming := number_value(1)
	growth_error := append_take_no_displaced(&growing, &growth_incoming)
	testing.expect_value(t, array_error_kind(&growth_error), Array_Error.Cleanup_Failed)
	testing.expect_value(t, array_error_cause(&growth_error), Array_Error.Out_Of_Memory)
	testing.expect(t, array_error_needs_cleanup(&growth_error))
	growing_length, growing_ok := array_length(&growing)
	testing.expect(t, growing_ok && growing_length == ARRAY_INITIAL_CAPACITY)
	testing.expect_value(t, kind_of(&growth_incoming), Kind.Number)
	testing.expect_value(t, destroy_array_error(&growth_error), runtime.Allocator_Error.None)
	growth_probe.short_success = false
	growth_retry_error := append_take_no_displaced(&growing, &growth_incoming)
	testing.expect_value(t, array_error_kind(&growth_retry_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&growing), runtime.Allocator_Error.None)
	testing.expect_value(t, growth_probe.live, 0)

	cow_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	shared, shared_constructor_error := array_value(probe_allocator(&cow_probe))
	testing.expect_value(t, array_error_kind(&shared_constructor_error), Array_Error.None)
	first := number_value(1)
	first_error := append_take_no_displaced(&shared, &first)
	testing.expect_value(t, array_error_kind(&first_error), Array_Error.None)
	shared_clone := clone_value(&shared)
	cow_probe.short_success = true
	cow_probe.free_failures_remaining = 1
	cow_incoming := number_value(2)
	cow_error := append_take_no_displaced(&shared_clone, &cow_incoming)
	testing.expect_value(t, array_error_kind(&cow_error), Array_Error.Cleanup_Failed)
	testing.expect_value(t, array_error_cause(&cow_error), Array_Error.Out_Of_Memory)
	testing.expect(t, array_error_needs_cleanup(&cow_error))
	testing.expect(t, values_equal(&shared, &shared_clone))
	testing.expect_value(t, kind_of(&cow_incoming), Kind.Number)
	testing.expect_value(t, destroy_array_error(&cow_error), runtime.Allocator_Error.None)
	cow_probe.short_success = false
	allocations_before_ceiling := cow_probe.allocations
	guarded := number_value(3)
	guarded_displaced, guarded_error := array_set_take(
		&shared_clone,
		JQ_ARRAY_INDEX_MAX + 1,
		&guarded,
	)
	testing.expect_value(t, array_error_kind(&guarded_error), Array_Error.Index_Too_Large)
	testing.expect_value(t, kind_of(&guarded_displaced), Kind.Invalid)
	testing.expect_value(t, cow_probe.allocations, allocations_before_ceiling)
	destroy_value(&guarded)
	cow_retry_error := append_take_no_displaced(&shared_clone, &cow_incoming)
	testing.expect_value(t, array_error_kind(&cow_retry_error), Array_Error.None)
	testing.expect_value(t, array_number_at(t, &shared_clone, 1), 2)
	testing.expect_value(t, array_number_at(t, &shared, 0), 1)
	testing.expect_value(t, destroy_value(&shared), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&shared_clone), runtime.Allocator_Error.None)
	testing.expect_value(t, cow_probe.live, 0)

	source, source_error := array_value(context.allocator)
	testing.expect_value(t, array_error_kind(&source_error), Array_Error.None)
	source_element := number_value(3)
	source_append_error := append_take_no_displaced(&source, &source_element)
	testing.expect_value(t, array_error_kind(&source_append_error), Array_Error.None)
	slice_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
		free_failures_remaining = 1,
	}
	slice, slice_error := array_slice(&source, 0, 0, probe_allocator(&slice_probe))
	testing.expect_value(t, kind_of(&slice), Kind.Invalid)
	testing.expect_value(t, array_error_kind(&slice_error), Array_Error.Cleanup_Failed)
	testing.expect_value(t, array_error_cause(&slice_error), Array_Error.Out_Of_Memory)
	testing.expect(t, array_error_needs_cleanup(&slice_error))
	testing.expect_value(t, array_number_at(t, &source, 0), 3)
	testing.expect_value(t, destroy_array_error(&slice_error), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	testing.expect_value(t, slice_probe.live, 0)
}

@(test)
array_allocation_failures_leave_operands_unchanged :: proc(t: ^testing.T) {
	constructor_probe := array_failure_probe{backing = context.allocator, fail_at = 0}
	failed, constructor_error := array_value(array_failure_allocator(&constructor_probe))
	testing.expect_value(t, array_error_kind(&constructor_error), Array_Error.Out_Of_Memory)
	testing.expect_value(t, kind_of(&failed), Kind.Invalid)

	growth_probe := array_failure_probe{backing = context.allocator, fail_at = 1}
	growing, growing_error := array_value(array_failure_allocator(&growth_probe))
	testing.expect_value(t, array_error_kind(&growing_error), Array_Error.None)
	fill_array_to_initial_capacity(t, &growing)
	incoming := number_value(1)
	growth_error := append_take_no_displaced(&growing, &incoming)
	testing.expect_value(t, array_error_kind(&growth_error), Array_Error.Out_Of_Memory)
	growing_length, _ := array_length(&growing)
	testing.expect_value(t, growing_length, ARRAY_INITIAL_CAPACITY)
	testing.expect_value(t, kind_of(&incoming), Kind.Number)
	destroy_value(&incoming)
	destroy_value(&growing)

	cow_probe := array_failure_probe{backing = context.allocator, fail_at = 1}
	shared, _ := array_value(array_failure_allocator(&cow_probe))
	first := number_value(1)
	append_take_no_displaced(&shared, &first)
	shared_clone := clone_value(&shared)
	cow_incoming := number_value(2)
	cow_error := append_take_no_displaced(&shared_clone, &cow_incoming)
	testing.expect_value(t, array_error_kind(&cow_error), Array_Error.Out_Of_Memory)
	testing.expect(t, values_equal(&shared, &shared_clone))
	testing.expect_value(t, kind_of(&cow_incoming), Kind.Number)
	destroy_value(&cow_incoming)
	destroy_value(&shared)
	destroy_value(&shared_clone)

	slice_probe := array_failure_probe{backing = context.allocator, fail_at = 0}
	source, _ := array_value(context.allocator)
	source_element := number_value(3)
	append_take_no_displaced(&source, &source_element)
	slice, slice_error := array_slice(&source, 0, 0, array_failure_allocator(&slice_probe))
	testing.expect_value(t, array_error_kind(&slice_error), Array_Error.Out_Of_Memory)
	testing.expect_value(t, kind_of(&slice), Kind.Invalid)
	testing.expect_value(t, array_number_at(t, &source, 0), 3)
	destroy_value(&slice)
	destroy_value(&source)
}

@(test)
array_allocator_provenance_and_retirement :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	array, _ := array_value(probe_allocator(&probe))
	element := number_value(1)
	append_take_no_displaced(&array, &element)
	saved_allocator := context.allocator
	context.allocator = runtime.Allocator{}
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	context.allocator = saved_allocator
	testing.expect_value(t, probe.allocations, probe.frees)
	testing.expect(t, !probe.wrong_free_size)
	probe.retired = true
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect(t, !probe.called_retired)

	arena: runtime.Arena
	init_error := runtime.arena_init(&arena, 4096, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error.None)
	if init_error == nil {
		arena_array, _ := array_value(runtime.arena_allocator(&arena))
		arena_element := number_value(1)
		append_take_no_displaced(&arena_array, &arena_element)
		testing.expect_value(t, destroy_value(&arena_array), runtime.Allocator_Error.None)
		runtime.arena_destroy(&arena)
		testing.expect_value(t, destroy_value(&arena_array), runtime.Allocator_Error.None)
	}
}

@(test)
nested_release_error_is_retryable_without_double_destroy :: proc(t: ^testing.T) {
	leaf_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	array, _ := array_value(context.allocator)
	leaf, _ := string_value("retry", probe_allocator(&leaf_probe))
	append_take_no_displaced(&array, &leaf)
	first_error := destroy_value(&array)
	testing.expect_value(t, first_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, kind_of(&array), Kind.Array)
	retiring_clone := clone_value(&array)
	testing.expect_value(t, kind_of(&retiring_clone), Kind.Invalid)
	_, accessible := array_length(&array)
	testing.expect(t, !accessible)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&array), Kind.Invalid)
	testing.expect_value(t, leaf_probe.frees, 2)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, leaf_probe.frees, 2)
}

@(test)
multi_element_retirement_resumes_through_element_and_backing_failures :: proc(t: ^testing.T) {
	backing_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	first_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	second_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	third_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	array, constructor_error := array_value(probe_allocator(&backing_probe))
	testing.expect_value(t, array_error_kind(&constructor_error), Array_Error.None)
	first, first_error := string_value("first", probe_allocator(&first_probe))
	second, second_error := string_value("second", probe_allocator(&second_probe))
	third, third_error := string_value("third", probe_allocator(&third_probe))
	testing.expect_value(t, constructor_error_kind(&first_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&second_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&third_error), Error.None)
	first_append_error := append_take_no_displaced(&array, &first)
	second_append_error := append_take_no_displaced(&array, &second)
	third_append_error := append_take_no_displaced(&array, &third)
	testing.expect_value(t, array_error_kind(&first_append_error), Array_Error.None)
	testing.expect_value(t, array_error_kind(&second_append_error), Array_Error.None)
	testing.expect_value(t, array_error_kind(&third_append_error), Array_Error.None)

	// The first leaf retires, the second initially fails, the retry then
	// retires the second and third before the backing Free itself fails.
	second_probe.free_failures_remaining = 1
	backing_probe.free_failures_remaining = 1
	backing_frees_before := backing_probe.frees
	first_destroy_error := destroy_value(&array)
	testing.expect_value(t, first_destroy_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, first_probe.frees, 1)
	testing.expect_value(t, second_probe.frees, 1)
	testing.expect_value(t, third_probe.frees, 0)
	second_destroy_error := destroy_value(&array)
	testing.expect_value(t, second_destroy_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, first_probe.frees, 1)
	testing.expect_value(t, second_probe.frees, 2)
	testing.expect_value(t, third_probe.frees, 1)
	testing.expect_value(t, backing_probe.frees, backing_frees_before + 1)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, first_probe.frees, 1)
	testing.expect_value(t, second_probe.frees, 2)
	testing.expect_value(t, third_probe.frees, 1)
	testing.expect_value(t, backing_probe.frees, backing_frees_before + 2)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, backing_probe.live, 0)
}

@(test)
array_backing_free_error_preserves_retryable_cleanup_owner :: proc(t: ^testing.T) {
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	array, err := array_value(probe_allocator(&probe))
	testing.expect_value(t, array_error_kind(&err), Array_Error.None)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, kind_of(&array), Kind.Array)
	_, accessible := array_length(&array)
	testing.expect(t, !accessible)
	testing.expect_value(t, destroy_value(&array), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&array), Kind.Invalid)
	testing.expect_value(t, probe.frees, 2)
}
