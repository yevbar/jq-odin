package value

import "base:runtime"
import "core:math"
import "core:mem"
import "core:testing"

TRACKING_MEMORY : bool : #config(ODIN_TEST_TRACK_MEMORY, true)

@(test)
scalar_tags_and_inline_values :: proc(t: ^testing.T) {
	invalid := invalid_value()
	null := null_value()
	f := boolean_value(false)
	truth := boolean_value(true)
	number := number_value(2.5)
	defer destroy_value(&invalid)
	defer destroy_value(&null)
	defer destroy_value(&f)
	defer destroy_value(&truth)
	defer destroy_value(&number)

	testing.expect_value(t, kind_of(&invalid), Kind.Invalid)
	testing.expect_value(t, kind_of(&null), Kind.Null)
	testing.expect_value(t, kind_of(&f), Kind.Boolean)
	testing.expect_value(t, kind_of(&number), Kind.Number)
	testing.expect(t, Kind.Array != Kind.Object)
	testing.expect(t, Kind.Invalid != Kind.Null)
	testing.expect(t, values_equal(&null, &null))
	testing.expect(t, !values_equal(&invalid, &invalid))
	got_false, false_ok := boolean_value_get(&f)
	got_true, true_ok := boolean_value_get(&truth)
	testing.expect(t, false_ok && !got_false)
	testing.expect(t, true_ok && got_true)
	got_number, number_ok := number_value_get(&number)
	testing.expect(t, number_ok && got_number == 2.5)
}

@(test)
strings_are_owned_and_length_delimited :: proc(t: ^testing.T) {
	empty, empty_error := string_value("", context.allocator)
	embedded, embedded_error := string_value("a\x00b", context.allocator)
	utf8, utf8_error := string_value("λ", context.allocator)
	defer destroy_value(&empty)
	defer destroy_value(&embedded)
	defer destroy_value(&utf8)

	testing.expect_value(t, constructor_error_kind(&empty_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&embedded_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&utf8_error), Error.None)
	empty_view, empty_ok := string_borrowed(&empty)
	embedded_view, embedded_ok := string_borrowed(&embedded)
	utf8_view, utf8_ok := string_borrowed(&utf8)
	testing.expect(t, empty_ok && len(empty_view) == 0)
	testing.expect(t, embedded_ok && len(embedded_view) == 3)
	testing.expect(t, embedded_view[1] == 0)
	testing.expect(t, utf8_ok && len(utf8_view) == 2)
}

@(test)
clone_take_and_destroy_lifecycle :: proc(t: ^testing.T) {
	original, err := string_value("owned", context.allocator)
	testing.expect_value(t, constructor_error_kind(&err), Error.None)
	clone_a := clone_value(&original)
	clone_b := clone_value(&clone_a)
	testing.expect_value(t, destroy_value(&original), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&original), Kind.Invalid)
	view, ok := string_borrowed(&clone_b)
	testing.expect(t, ok && view == "owned")

	moved := take_value(&clone_a)
	testing.expect_value(t, kind_of(&clone_a), Kind.Invalid)
	second_move := take_value(&clone_a)
	testing.expect_value(t, kind_of(&second_move), Kind.Invalid)
	testing.expect_value(t, destroy_value(&clone_a), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&clone_a), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&moved), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&clone_b), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&moved), Kind.Invalid)
	testing.expect_value(t, kind_of(&clone_b), Kind.Invalid)
}

@(test)
opaque_handle_preserves_public_value_api :: proc(t: ^testing.T) {
	testing.expect(t, size_of(Value) >= size_of(value_storage))
	testing.expect(t, align_of(Value) >= align_of(value_storage))

	invalid := invalid_value()
	null := null_value()
	boolean := boolean_value(true)
	native := number_value(2.5)
	string_owned, string_error := string_value("owned", context.allocator)
	literal, literal_error := literal_number_value("2.50", context.allocator)
	testing.expect_value(t, constructor_error_kind(&string_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&literal_error), Error.None)

	testing.expect_value(t, kind_of(&invalid), Kind.Invalid)
	testing.expect_value(t, kind_of(&null), Kind.Null)
	boolean_result, boolean_ok := boolean_value_get(&boolean)
	testing.expect(t, boolean_ok && boolean_result)
	native_kind, native_kind_ok := number_kind(&native)
	literal_kind, literal_kind_ok := number_kind(&literal)
	testing.expect(t, native_kind_ok && native_kind == .Native)
	testing.expect(t, literal_kind_ok && literal_kind == .Literal)
	native_result, native_ok := number_value_get(&native)
	testing.expect(t, native_ok && native_result == 2.5)
	string_result, string_ok := string_borrowed(&string_owned)
	literal_result, literal_ok := literal_spelling_borrowed(&literal)
	testing.expect(t, string_ok && string_result == "owned")
	testing.expect(t, literal_ok && literal_result == "2.50")
	testing.expect(t, values_equal(&null, &null))
	comparison, comparison_ok := compare_numbers(&native, &literal)
	testing.expect(t, comparison_ok && comparison == 0)

	clone := clone_value(&string_owned)
	moved := take_value(&clone)
	testing.expect_value(t, kind_of(&clone), Kind.Invalid)
	testing.expect_value(t, destroy_value(&string_owned), runtime.Allocator_Error.None)
	moved_result, moved_ok := string_borrowed(&moved)
	testing.expect(t, moved_ok && moved_result == "owned")

	testing.expect_value(t, destroy_value(&invalid), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&null), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&boolean), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&native), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&literal), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&moved), runtime.Allocator_Error.None)
}

allocator_probe :: struct {
	backing:       runtime.Allocator,
	allocations:   int,
	frees:         int,
	live:          int,
	fail_after:    int,
	retired:       bool,
	called_retired: bool,
	wrong_free_size: bool,
	last_size:     int,
	free_failures_remaining: int,
	nil_success:   bool,
	short_success: bool,
}

allocator_probe_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	probe := cast(^allocator_probe)data
	if probe.retired {
		probe.called_retired = true
		return nil, .Invalid_Argument
	}
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		if probe.allocations == probe.fail_after {
			probe.allocations += 1
			return nil, .Out_Of_Memory
		}
		probe.allocations += 1
		if probe.nil_success {
			return nil, nil
		}
		request_size := size
		if probe.short_success {
			request_size = max(size - 1, 0)
		}
		result, err := probe.backing.procedure(
			probe.backing.data,
			mode,
			request_size,
			alignment,
			old_memory,
			old_size,
			location,
		)
		if err == nil && len(result) > 0 {
			probe.live += 1
			probe.last_size = len(result)
		}
		return result, err
	case .Free:
		probe.frees += 1
		if old_size != probe.last_size {
			probe.wrong_free_size = true
		}
		if probe.free_failures_remaining > 0 {
			probe.free_failures_remaining -= 1
			return nil, .Invalid_Pointer
		}
		result, err := probe.backing.procedure(
			probe.backing.data,
			mode,
			size,
			alignment,
			old_memory,
			old_size,
			location,
		)
		if err == nil {
			probe.live -= 1
		}
		return result, err
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

@(test)
constructor_allocation_requires_exact_length_and_preserves_failed_cleanup :: proc(t: ^testing.T) {
	nil_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		nil_success = true,
	}
	nil_value, nil_error := string_value("nil", probe_allocator(&nil_probe))
	testing.expect_value(t, kind_of(&nil_value), Kind.Invalid)
	testing.expect_value(t, constructor_error_kind(&nil_error), Error.Out_Of_Memory)
	testing.expect(t, !constructor_error_needs_cleanup(&nil_error))
	testing.expect_value(t, nil_probe.frees, 0)

	short_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
	}
	short_value, short_error := literal_number_value("1.25", probe_allocator(&short_probe))
	testing.expect_value(t, kind_of(&short_value), Kind.Invalid)
	testing.expect_value(t, constructor_error_kind(&short_error), Error.Out_Of_Memory)
	testing.expect(t, !constructor_error_needs_cleanup(&short_error))
	testing.expect_value(t, short_probe.frees, 1)
	testing.expect_value(t, short_probe.live, 0)

	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
		short_success = true,
	}
	retry_value, retry_error := string_value("retry", probe_allocator(&retry_probe))
	testing.expect_value(t, kind_of(&retry_value), Kind.Invalid)
	testing.expect_value(t, constructor_error_kind(&retry_error), Error.Out_Of_Memory)
	testing.expect(t, constructor_error_needs_cleanup(&retry_error))
	testing.expect_value(t, retry_probe.live, 1)
	testing.expect_value(t, destroy_constructor_error(&retry_error), runtime.Allocator_Error.None)
	testing.expect_value(t, constructor_error_kind(&retry_error), Error.None)
	testing.expect_value(t, retry_probe.frees, 2)
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
		bulk_value, bulk_error := literal_number_value("2.5", probe_allocator(&bulk_probe))
		testing.expect_value(t, kind_of(&bulk_value), Kind.Invalid)
		testing.expect_value(t, constructor_error_kind(&bulk_error), Error.Out_Of_Memory)
		testing.expect(t, !constructor_error_needs_cleanup(&bulk_error))
		testing.expect_value(t, bulk_probe.frees, 1)
		runtime.arena_destroy(&arena)
	}
}

probe_allocator :: proc(probe: ^allocator_probe) -> runtime.Allocator {
	return {procedure = allocator_probe_proc, data = probe}
}

bulk_allocator_probe :: struct {
	backing:                  runtime.Allocator,
	calls:                    int,
	individual_free_requests: int,
	bulk_free_requests:       int,
	retired:                  bool,
	called_retired:           bool,
}

bulk_allocator_probe_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	probe := cast(^bulk_allocator_probe)data
	if probe.retired {
		probe.called_retired = true
		return nil, .Invalid_Argument
	}
	probe.calls += 1
	#partial switch mode {
	case .Free:
		probe.individual_free_requests += 1
		return nil, .Mode_Not_Implemented
	case .Free_All:
		probe.bulk_free_requests += 1
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

bulk_probe_allocator :: proc(probe: ^bulk_allocator_probe) -> runtime.Allocator {
	return {procedure = bulk_allocator_probe_proc, data = probe}
}

@(test)
final_free_error_is_observable_and_retryable :: proc(t: ^testing.T) {
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	value, err := string_value("retryable", probe_allocator(&probe))
	testing.expect_value(t, constructor_error_kind(&err), Error.None)

	first_destroy_error := destroy_value(&value)
	testing.expect_value(t, first_destroy_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, kind_of(&value), Kind.String)
	view, ok := string_borrowed(&value)
	testing.expect(t, ok && view == "retryable")

	clone := clone_value(&value)
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&clone), Kind.Invalid)
	testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&value), Kind.Invalid)
	testing.expect_value(t, probe.allocations, 1)
	testing.expect_value(t, probe.frees, 2)
	testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 2)
}

@(test)
allocator_provenance_and_exact_size_free :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	value, err := string_value("provenance", probe_allocator(&probe))
	testing.expect_value(t, constructor_error_kind(&err), Error.None)
	clone := clone_value(&value)
	saved_allocator := context.allocator
	context.allocator = runtime.Allocator{}
	testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 0)
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
	context.allocator = saved_allocator
	testing.expect_value(t, probe.allocations, 1)
	testing.expect_value(t, probe.frees, 1)
	testing.expect(t, !probe.wrong_free_size)

	literal, literal_error := literal_number_value("1.00", probe_allocator(&probe))
	testing.expect_value(t, constructor_error_kind(&literal_error), Error.None)
	testing.expect_value(t, destroy_value(&literal), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.allocations, 2)
	testing.expect_value(t, probe.frees, 2)
	testing.expect(t, !probe.wrong_free_size)
	probe.retired = true
	testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
	testing.expect(t, !probe.called_retired)
}

@(test)
arena_values_retire_before_bulk_teardown :: proc(t: ^testing.T) {
	arena: runtime.Arena
	init_error := runtime.arena_init(&arena, 4096, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error.None)
	if init_error != nil {
		return
	}

	value, err := string_value("arena-owned", runtime.arena_allocator(&arena))
	testing.expect_value(t, constructor_error_kind(&err), Error.None)
	clone := clone_value(&value)
	testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&value), Kind.Invalid)
	view, ok := string_borrowed(&clone)
	testing.expect(t, ok && view == "arena-owned")
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
	testing.expect_value(t, kind_of(&clone), Kind.Invalid)

	// Arena .Free is intentionally unsupported. Final handle retirement must
	// complete before the arena releases its backing blocks in bulk.
	runtime.arena_destroy(&arena)
	testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
}

@(test)
non_freeing_allocator_retires_handles_without_false_free :: proc(t: ^testing.T) {
	arena: runtime.Arena
	init_error := runtime.arena_init(&arena, 4096, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error.None)
	if init_error != nil {
		return
	}
	probe := bulk_allocator_probe{backing = runtime.arena_allocator(&arena)}
	allocator := bulk_probe_allocator(&probe)

	value, err := literal_number_value("1.00", allocator)
	testing.expect_value(t, constructor_error_kind(&err), Error.None)
	clone := clone_value(&value)
	testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.individual_free_requests, 0)
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.individual_free_requests, 1)
	testing.expect_value(t, kind_of(&value), Kind.Invalid)
	testing.expect_value(t, kind_of(&clone), Kind.Invalid)

	calls_after_retirement := probe.calls
	testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.calls, calls_after_retirement)
	testing.expect_value(t, probe.bulk_free_requests, 0)

	bulk_error := runtime.mem_free_all(allocator)
	testing.expect_value(t, bulk_error, runtime.Allocator_Error.None)
	testing.expect_value(t, probe.bulk_free_requests, 1)
	runtime.arena_destroy(&arena)
	probe.retired = true
	testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
	testing.expect(t, !probe.called_retired)
}

@(test)
all_constructor_allocation_failures_are_inert :: proc(t: ^testing.T) {
	string_probe := allocator_probe{backing = context.allocator, fail_after = 0}
	string_result, string_error := string_value("x", probe_allocator(&string_probe))
	testing.expect_value(t, constructor_error_kind(&string_error), Error.Out_Of_Memory)
	testing.expect_value(t, kind_of(&string_result), Kind.Invalid)
	destroy_value(&string_result)

	number_probe := allocator_probe{backing = context.allocator, fail_after = 0}
	number_result, number_error := literal_number_value("1.00", probe_allocator(&number_probe))
	testing.expect_value(t, constructor_error_kind(&number_error), Error.Out_Of_Memory)
	testing.expect_value(t, kind_of(&number_result), Kind.Invalid)
	destroy_value(&number_result)
	testing.expect_value(t, string_probe.frees, 0)
	testing.expect_value(t, number_probe.frees, 0)

	overflow_probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	overflow_payload, overflow_error := allocate_payload(
		.String,
		max(int),
		1,
		probe_allocator(&overflow_probe),
	)
	testing.expect(t, overflow_payload == nil)
	testing.expect_value(t, constructor_error_kind(&overflow_error), Error.Size_Overflow)
	testing.expect_value(t, overflow_probe.allocations, 0)
}

@(test)
literal_decimal_identity_and_mixed_fallback :: proc(t: ^testing.T) {
	one, one_error := literal_number_value("1", context.allocator)
	one_dot_zero, one_dot_zero_error := literal_number_value("1.0", context.allocator)
	one_dot_zero_zero, one_dot_zero_zero_error := literal_number_value("1.00", context.allocator)
	big_a, big_a_error := literal_number_value("9007199254740992", context.allocator)
	big_b, big_b_error := literal_number_value("9007199254740993", context.allocator)
	native_big := number_value(9007199254740992.0)
	defer destroy_value(&one)
	defer destroy_value(&one_dot_zero)
	defer destroy_value(&one_dot_zero_zero)
	defer destroy_value(&big_a)
	defer destroy_value(&big_b)
	defer destroy_value(&native_big)

	testing.expect_value(t, constructor_error_kind(&one_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&one_dot_zero_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&one_dot_zero_zero_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&big_a_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&big_b_error), Error.None)
	testing.expect(t, values_equal(&one, &one_dot_zero))
	testing.expect(t, values_equal(&one_dot_zero, &one_dot_zero_zero))
	testing.expect(t, !values_equal(&big_a, &big_b))
	testing.expect(t, values_equal(&big_b, &native_big))
	big_order, big_order_ok := compare_numbers(&big_a, &big_b)
	testing.expect(t, big_order_ok && big_order < 0)
	literal_values := [3]^Value{&one, &one_dot_zero, &one_dot_zero_zero}
	for value in literal_values {
		kind, ok := number_kind(value)
		testing.expect(t, ok && kind == .Literal)
	}
	spelling_a, _ := literal_spelling_borrowed(&one)
	spelling_b, _ := literal_spelling_borrowed(&one_dot_zero)
	spelling_c, _ := literal_spelling_borrowed(&one_dot_zero_zero)
	testing.expect(t, spelling_a == "1")
	testing.expect(t, spelling_b == "1.0")
	testing.expect(t, spelling_c == "1.00")
}

@(test)
literal_binary64_cache_matches_jq_reduction :: proc(t: ^testing.T) {
	// jq 1.8.1 USE_DECNUM reduces the finalized decimal to 17 digits under
	// DEC_INIT_DECIMAL64 (half-even), regenerates it, then calls jvp_strtod.
	// Oracle: [., .+0, . == (.+0)] for this token reports true, and the
	// computed value has binary64 bits 0x23424d729ee9bdec.
	literal, err := literal_number_value(
		"7684633156201539.548165e-154",
		context.allocator,
	)
	native := number_value(transmute(f64)u64(0x23424d729ee9bdec))
	defer destroy_value(&literal)
	defer destroy_value(&native)

	testing.expect_value(t, constructor_error_kind(&err), Error.None)
	cached, ok := number_value_get(&literal)
	testing.expect(t, ok)
	testing.expect_value(t, transmute(u64)cached, u64(0x23424d729ee9bdec))
	testing.expect(t, values_equal(&literal, &native))
	order, order_ok := compare_numbers(&literal, &native)
	testing.expect(t, order_ok && order == 0)
}

@(test)
literal_comparison_normalizes_decimal_forms :: proc(t: ^testing.T) {
	forms := [4]string{"1", "100e-2", "1e+0", "0.0001e4"}
	values: [4]Value
	for literal, i in forms {
		err: Constructor_Error
		values[i], err = literal_number_value(literal, context.allocator)
		testing.expect_value(t, constructor_error_kind(&err), Error.None)
	}
	defer destroy_value(&values[0])
	defer destroy_value(&values[1])
	defer destroy_value(&values[2])
	defer destroy_value(&values[3])
	for i in 1..<len(values) {
		comparison, ok := compare_numbers(&values[0], &values[i])
		testing.expect(t, ok && comparison == 0)
	}

	negative_two, negative_two_error := literal_number_value("-2", context.allocator)
	negative_one, negative_one_error := literal_number_value("-1", context.allocator)
	defer destroy_value(&negative_two)
	defer destroy_value(&negative_one)
	testing.expect_value(t, constructor_error_kind(&negative_two_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&negative_one_error), Error.None)
	comparison, ok := compare_numbers(&negative_two, &negative_one)
	testing.expect(t, ok && comparison < 0)
}

@(test)
literal_zero_orders_against_fractions_and_native_values :: proc(t: ^testing.T) {
	zero_forms := [4]string{"0", "-0.00", "0e999999999", "-0e-1147483647"}
	positive_forms := [2]string{"0.5", "5e-1"}
	negative_forms := [2]string{"-0.5", "-5e-1"}

	for zero_literal in zero_forms {
		zero, zero_error := literal_number_value(zero_literal, context.allocator)
		testing.expect_value(t, constructor_error_kind(&zero_error), Error.None)
		for positive_literal in positive_forms {
			positive, positive_error := literal_number_value(
				positive_literal,
				context.allocator,
			)
			testing.expect_value(t, constructor_error_kind(&positive_error), Error.None)
			order, ok := compare_numbers(&zero, &positive)
			reverse, reverse_ok := compare_numbers(&positive, &zero)
			testing.expect(t, ok && order < 0)
			testing.expect(t, reverse_ok && reverse > 0)
			destroy_value(&positive)
		}
		for negative_literal in negative_forms {
			negative, negative_error := literal_number_value(
				negative_literal,
				context.allocator,
			)
			testing.expect_value(t, constructor_error_kind(&negative_error), Error.None)
			order, ok := compare_numbers(&negative, &zero)
			reverse, reverse_ok := compare_numbers(&zero, &negative)
			testing.expect(t, ok && order < 0)
			testing.expect(t, reverse_ok && reverse > 0)
			destroy_value(&negative)
		}

		native_zero := number_value(-0.0)
		native_positive := number_value(0.5)
		native_negative := number_value(-0.5)
		testing.expect(t, values_equal(&zero, &native_zero))
		positive_order, positive_ok := compare_numbers(&zero, &native_positive)
		negative_order, negative_ok := compare_numbers(&native_negative, &zero)
		testing.expect(t, positive_ok && positive_order < 0)
		testing.expect(t, negative_ok && negative_order < 0)
		destroy_value(&native_zero)
		destroy_value(&native_positive)
		destroy_value(&native_negative)
		destroy_value(&zero)
	}
}

decimal_digit_count_u64 :: proc(value: u64) -> int {
	remaining := value
	count := 1
	for remaining >= 10 {
		remaining /= 10
		count += 1
	}
	return count
}

pow10_u64 :: proc(exponent: int) -> u64 {
	result := u64(1)
	for _ in 0..<exponent {
		result *= 10
	}
	return result
}

// This small integer model quantizes the exact rational coefficient*10^exp
// once at max(precision boundary, Etiny). It is intentionally independent of
// the byte-slice implementation used by literal_number_value_with_context.
decimal_context_model :: proc(
	coefficient: u64,
	exponent: i64,
	digits: int,
	emin: i64,
) -> (rounded_coefficient: u64, rounded_exponent: i64) {
	coefficient_digits := decimal_digit_count_u64(coefficient)
	etiny := emin - i64(digits) + 1
	discard := max(coefficient_digits - digits, 0)
	if etiny - exponent > i64(discard) {
		discard = int(etiny - exponent)
	}
	if discard == 0 {
		return coefficient, exponent
	}
	if discard > coefficient_digits {
		return 0, etiny
	}
	divisor := pow10_u64(discard)
	rounded_coefficient = coefficient / divisor
	remainder := coefficient % divisor
	rounded_exponent = exponent + i64(discard)
	if remainder >= (divisor + 1) / 2 {
		rounded_coefficient += 1
	}
	kept_digits := max(coefficient_digits - discard, 1)
	if decimal_digit_count_u64(rounded_coefficient) > kept_digits {
		rounded_coefficient /= 10
		rounded_exponent += 1
	}
	return
}

@(test)
parameterized_decimal_context_rounds_once_at_etiny :: proc(t: ^testing.T) {
	Context_Case :: struct {
		literal:    string,
		coefficient: u64,
		exponent:   i64,
		digits:     int,
		emin:       i64,
	}
	cases := [?]Context_Case{
		{"1495e-15", 1495, -15, 3, -10}, // Etiny=-12: exact result 1e-12.
		{"1500e-15", 1500, -15, 3, -10},
		{"1495e-15", 1495, -15, 4, -9},
		{"1495e-15", 1495, -15, 3, -11},
		{"1495e-15", 1495, -15, 2, -11},
		{"9995", 9995, 0, 3, -20},
	}
	for test_case in cases {
		expected_coefficient, expected_exponent := decimal_context_model(
			test_case.coefficient,
			test_case.exponent,
			test_case.digits,
			test_case.emin,
		)
		value, err := literal_number_value_with_context(
			test_case.literal,
			context.allocator,
			test_case.digits,
			test_case.emin,
			20,
		)
		testing.expect_value(t, constructor_error_kind(&err), Error.None)
		if err == nil {
			p := value_storage_of(&value).owned_payload
			actual_coefficient := u64(0)
			for c in payload_coefficient(p) {
				actual_coefficient = actual_coefficient * 10 + u64(c - '0')
			}
			testing.expect_value(t, actual_coefficient, expected_coefficient)
			testing.expect_value(t, p.exponent, expected_exponent)
		}
		destroy_value(&value)
	}

	reproduction, reproduction_error := literal_number_value_with_context(
		"1495e-15",
		context.allocator,
		3,
		-10,
		20,
	)
	defer destroy_value(&reproduction)
	testing.expect_value(t, constructor_error_kind(&reproduction_error), Error.None)
	reproduction_storage := value_storage_of(&reproduction)
	testing.expect(t, string(payload_coefficient(reproduction_storage.owned_payload)) == "1")
	testing.expect_value(t, reproduction_storage.owned_payload.exponent, i64(-12))
}

@(test)
decimal_context_precision_and_rounding_constants :: proc(t: ^testing.T) {
	// jv.c derives this from INT32_MAX, DECDPUN=3, Emax, and Emin.
	testing.expect_value(t, DECIMAL_DIGITS, 147_483_648)
	testing.expect_value(t, DECIMAL_ETINY, i64(-1_147_483_646))

	down := []byte{'1', '2', '4'}
	down_exponent := i64(1)
	round_coefficient(down, '4', &down_exponent)
	testing.expect(t, string(down) == "124" && down_exponent == 1)

	half_up := []byte{'1', '2', '4'}
	half_up_exponent := i64(1)
	round_coefficient(half_up, '5', &half_up_exponent)
	testing.expect(t, string(half_up) == "125" && half_up_exponent == 1)

	carry := []byte{'9', '9', '9'}
	carry_exponent := i64(1)
	increment_coefficient(carry, &carry_exponent)
	testing.expect(t, string(carry) == "100" && carry_exponent == 2)

	below, below_error := literal_number_value_with_precision("9994", context.allocator, 3)
	half, half_error := literal_number_value_with_precision("9995", context.allocator, 3)
	expected_below, expected_below_error := literal_number_value("9990", context.allocator)
	expected_half, expected_half_error := literal_number_value("10000", context.allocator)
	defer destroy_value(&below)
	defer destroy_value(&half)
	defer destroy_value(&expected_below)
	defer destroy_value(&expected_half)
	testing.expect_value(t, constructor_error_kind(&below_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&half_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&expected_below_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&expected_half_error), Error.None)
	testing.expect(t, values_equal(&below, &expected_below))
	testing.expect(t, values_equal(&half, &expected_half))
}

@(test)
signed_zero_is_retained_and_compares_numerically :: proc(t: ^testing.T) {
	positive, positive_error := literal_number_value("0", context.allocator)
	negative, negative_error := literal_number_value("-0.00", context.allocator)
	native_negative := number_value(-0.0)
	defer destroy_value(&positive)
	defer destroy_value(&negative)
	defer destroy_value(&native_negative)

	testing.expect_value(t, constructor_error_kind(&positive_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&negative_error), Error.None)
	testing.expect(t, values_equal(&positive, &negative))
	testing.expect(t, values_equal(&positive, &native_negative))
	negative_number, ok := number_value_get(&negative)
	testing.expect(t, ok && math.sign_bit(negative_number))
	spelling, _ := literal_spelling_borrowed(&negative)
	testing.expect(t, spelling == "-0.00")
}

@(test)
decimal_exponent_boundaries :: proc(t: ^testing.T) {
	maximum, maximum_error := literal_number_value("1e999999999", context.allocator)
	overflow, overflow_error := literal_number_value("1e1000000000", context.allocator)
	minimum, minimum_error := literal_number_value("1e-999999999", context.allocator)
	etiny, etiny_error := literal_number_value("1e-1147483646", context.allocator)
	underflow, underflow_error := literal_number_value("1e-1147483647", context.allocator)
	half_up, half_up_error := literal_number_value("5e-1147483647", context.allocator)
	below_half, below_half_error := literal_number_value("4e-1147483647", context.allocator)
	zero, zero_error := literal_number_value("0", context.allocator)
	defer destroy_value(&maximum)
	defer destroy_value(&overflow)
	defer destroy_value(&minimum)
	defer destroy_value(&etiny)
	defer destroy_value(&underflow)
	defer destroy_value(&half_up)
	defer destroy_value(&below_half)
	defer destroy_value(&zero)

	testing.expect_value(t, constructor_error_kind(&maximum_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&overflow_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&minimum_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&etiny_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&underflow_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&half_up_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&below_half_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&zero_error), Error.None)
	maximum_f64, _ := number_value_get(&maximum)
	overflow_f64, _ := number_value_get(&overflow)
	testing.expect(t, math.is_inf(maximum_f64))
	testing.expect(t, math.is_inf(overflow_f64))
	testing.expect(t, !values_equal(&maximum, &overflow))
	testing.expect(t, !values_equal(&minimum, &zero))
	testing.expect(t, !values_equal(&etiny, &zero))
	testing.expect(t, values_equal(&underflow, &zero))
	testing.expect(t, values_equal(&half_up, &etiny))
	testing.expect(t, values_equal(&below_half, &zero))
	boundary_order, boundary_order_ok := compare_numbers(&maximum, &overflow)
	testing.expect(t, boundary_order_ok && boundary_order < 0)
}

@(test)
literal_constructor_accepts_jq_decnumber_grammar :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	accepted_literals := [8]string{"01", "1.", ".1", "+1", "-.1", "1.e2", "00e2", "Infinity"}
	for literal in accepted_literals {
		value, err := literal_number_value(literal, probe_allocator(&probe))
		testing.expect_value(t, constructor_error_kind(&err), Error.None)
		testing.expect_value(t, kind_of(&value), Kind.Number)
		destroy_value(&value)
	}

	// jv_number_with_literal converts payload-free NaNs to native numbers.
	// jv_parse.c can pass these tokens even though jq's language lexer has
	// separate boundaries for operators such as unary '+' and '-'.
	nan_literals := [5]string{"nan", "NaN", "-NaN", "sNaN", "NaN00"}
	for literal in nan_literals {
		value, err := literal_number_value(literal, probe_allocator(&probe))
		testing.expect_value(t, constructor_error_kind(&err), Error.None)
		kind, kind_ok := number_kind(&value)
		number, number_ok := number_value_get(&value)
		testing.expect(t, kind_ok && kind == .Native)
		testing.expect(t, number_ok && math.is_nan(number))
		destroy_value(&value)
	}

	positive_infinity, positive_error := literal_number_value(
		"Infinity",
		probe_allocator(&probe),
	)
	negative_infinity, negative_error := literal_number_value(
		"-Inf",
		probe_allocator(&probe),
	)
	testing.expect_value(t, constructor_error_kind(&positive_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&negative_error), Error.None)
	positive_kind, positive_kind_ok := number_kind(&positive_infinity)
	negative_kind, negative_kind_ok := number_kind(&negative_infinity)
	positive_cache, positive_cache_ok := number_value_get(&positive_infinity)
	negative_cache, negative_cache_ok := number_value_get(&negative_infinity)
	testing.expect(t, positive_kind_ok && positive_kind == .Literal)
	testing.expect(t, negative_kind_ok && negative_kind == .Literal)
	testing.expect(t, positive_cache_ok && math.is_inf(positive_cache) && positive_cache > 0)
	testing.expect(t, negative_cache_ok && math.is_inf(negative_cache) && negative_cache < 0)
	destroy_value(&positive_infinity)
	destroy_value(&negative_infinity)

	invalid_literals := [10]string{"", ".", "+", "-", ".e1", "1e", "NaN1", "sNaN2", "Infinity0", "++1"}
	for literal in invalid_literals {
		value, err := literal_number_value(literal, probe_allocator(&probe))
		testing.expect_value(t, constructor_error_kind(&err), Error.Invalid_Number_Literal)
		testing.expect_value(t, kind_of(&value), Kind.Invalid)
	}
	testing.expect_value(t, probe.allocations, probe.frees)
}

@(test)
special_literals_use_bytewise_ascii_case_folding :: proc(t: ^testing.T) {
	// These valid UTF-8 strings have the same byte length as the special
	// spelling they previously impersonated. Rune truncation yielded the
	// first ASCII byte while skipping the remaining UTF-8 bytes.
	crafted_non_ascii := [3]string{
		"\u086e",  // Three-byte rune with low byte 'n', versus "nan".
		"\u0869",  // Three-byte rune with low byte 'i', versus "inf".
		"\U00010073", // Four-byte rune with low byte 's', versus "snan".
	}
	for literal in crafted_non_ascii {
		value, err := literal_number_value(literal, context.allocator)
		testing.expect_value(t, constructor_error_kind(&err), Error.Invalid_Number_Literal)
		testing.expect_value(t, kind_of(&value), Kind.Invalid)
		destroy_value(&value)
	}

	mixed_case_nan := [2]string{"nAn", "SnAn"}
	for literal in mixed_case_nan {
		value, err := literal_number_value(literal, context.allocator)
		testing.expect_value(t, constructor_error_kind(&err), Error.None)
		number, ok := number_value_get(&value)
		testing.expect(t, ok && math.is_nan(number))
		destroy_value(&value)
	}

	mixed_case_infinity := [2]string{"iNf", "InFiNiTy"}
	for literal in mixed_case_infinity {
		value, err := literal_number_value(literal, context.allocator)
		testing.expect_value(t, constructor_error_kind(&err), Error.None)
		number, ok := number_value_get(&value)
		testing.expect(t, ok && math.is_inf(number) && number > 0)
		destroy_value(&value)
	}
}

@(test)
native_nan_comparison_matches_jvp_number_cmp_fallback :: proc(t: ^testing.T) {
	nan_a := number_value(math.nan_f64())
	nan_b := number_value(math.nan_f64())
	finite := number_value(1)
	defer destroy_value(&nan_a)
	defer destroy_value(&nan_b)
	defer destroy_value(&finite)

	nan_finite, nan_finite_ok := compare_numbers(&nan_a, &finite)
	finite_nan, finite_nan_ok := compare_numbers(&finite, &nan_a)
	nan_nan, nan_nan_ok := compare_numbers(&nan_a, &nan_b)
	testing.expect(t, nan_finite_ok && nan_finite == 1)
	testing.expect(t, finite_nan_ok && finite_nan == 1)
	testing.expect(t, nan_nan_ok && nan_nan == 1)
	testing.expect(t, !values_equal(&nan_a, &nan_b))
}

@(test)
checked_in_tests_run_with_allocation_tracking :: proc(t: ^testing.T) {
	when TRACKING_MEMORY {
		tracker := cast(^mem.Tracking_Allocator)context.allocator.data
		testing.expect(t, tracker != nil)
	} else {
		testing.expect(t, false, "value tests require Odin allocation tracking")
	}
}
