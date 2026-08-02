package value

import "base:runtime"
import "core:math"
import "core:testing"

expect_negation_rejection :: proc(
	t: ^testing.T,
	source: ^Value,
	probe: ^allocator_probe,
) {
	before := probe.allocations
	result, err, ok := number_negate(source, probe_allocator(probe))
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect(t, !ok)
	testing.expect_value(t, constructor_error_kind(&err), Error.None)
	testing.expect(t, !constructor_error_needs_cleanup(&err))
	testing.expect_value(t, probe.allocations, before)
	testing.expect_value(t, destroy_constructor_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
}

@(test)
number_negation_rejects_non_numbers_without_allocation :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	expect_negation_rejection(t, nil, &probe)

	invalid := invalid_value()
	null := null_value()
	boolean := boolean_value(true)
	string_owned, string_error := string_value("x", context.allocator)
	array, array_error := array_value(context.allocator)
	object, object_error := object_value(context.allocator)
	defer destroy_value(&invalid)
	defer destroy_value(&null)
	defer destroy_value(&boolean)
	defer destroy_value(&string_owned)
	defer destroy_value(&array)
	defer destroy_value(&object)
	defer destroy_constructor_error(&string_error)
	defer destroy_array_error(&array_error)
	defer destroy_object_error(&object_error)

	testing.expect_value(t, constructor_error_kind(&string_error), Error.None)
	testing.expect_value(t, array_error_kind(&array_error), Array_Error.None)
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	sources := [6]^Value{&invalid, &null, &boolean, &string_owned, &array, &object}
	for source in sources {
		expect_negation_rejection(t, source, &probe)
	}
	testing.expect_value(t, probe.allocations, 0)
}

@(test)
native_number_negation_toggles_only_the_sign_bit :: proc(t: ^testing.T) {
	bits := [?]u64{
		0x4004000000000000,
		0xc004000000000000,
		0x0000000000000000,
		0x8000000000000000,
		0x7ff0000000000000,
		0xfff0000000000000,
		0x7ff8000000000042,
		0xfff8000000000042,
	}
	probe := allocator_probe{backing = context.allocator, fail_after = 0}
	for source_bits in bits {
		source := number_value(transmute(f64)source_bits)
		negated, err, ok := number_negate(&source, probe_allocator(&probe))
		testing.expect_value(t, constructor_error_kind(&err), Error.None)
		testing.expect(t, ok)
		source_number, source_ok := number_value_get(&source)
		negated_number, negated_ok := number_value_get(&negated)
		testing.expect(t, source_ok && negated_ok)
		testing.expect_value(t, transmute(u64)source_number, source_bits)
		testing.expect_value(t, transmute(u64)negated_number, source_bits ~ (u64(1) << 63))

		restored, restored_error, restore_succeeded := number_negate(&negated, probe_allocator(&probe))
		testing.expect_value(t, constructor_error_kind(&restored_error), Error.None)
		testing.expect(t, restore_succeeded)
		restored_number, restored_ok := number_value_get(&restored)
		testing.expect(t, restored_ok)
		testing.expect_value(t, transmute(u64)restored_number, source_bits)
		testing.expect_value(t, probe.allocations, 0)
		destroy_constructor_error(&err)
		destroy_constructor_error(&restored_error)
		destroy_value(&source)
		destroy_value(&negated)
		destroy_value(&restored)
	}
}

literal_metadata_matches_negation :: proc(t: ^testing.T, source, result: ^payload) {
	testing.expect(t, source != nil && result != nil && source != result)
	if source == nil || result == nil {
		return
	}
	testing.expect_value(t, result.kind, source.kind)
	testing.expect_value(t, result.coefficient_len, source.coefficient_len)
	testing.expect_value(t, result.exponent, source.exponent)
	literal_zero := coefficient_is_zero(payload_coefficient(source))
	expected_negative := !literal_zero && !source.negative
	testing.expect_value(t, result.negative, expected_negative)
	testing.expect(t, !result.explicit_positive_sign)
	testing.expect_value(t, result.infinite, source.infinite)
	if literal_zero {
		testing.expect(t, !result.infinite)
		testing.expect_value(t, transmute(u64)result.native_cache, u64(0))
		testing.expect(t, !math.sign_bit(result.native_cache))
	} else {
		testing.expect_value(
			t,
			transmute(u64)result.native_cache,
			(transmute(u64)source.native_cache) ~ (u64(1) << 63),
		)
	}
	testing.expect(t, string(payload_coefficient(result)) == string(payload_coefficient(source)))
}

@(test)
literal_number_negation_generates_fresh_canonical_spelling :: proc(t: ^testing.T) {
	Literal_Case :: struct {
		source:          string,
		first_expected:  string,
		second_expected: string,
	}
	// Source-built pinned jq 1.8.1 probes use filters of the form
	//   jq -cn '[LITERAL,-(LITERAL),-(-(LITERAL))]'
	// Exact compact triples include:
	//   1e+00       -> [1,-1,1]
	//   1E+00       -> [1,-1,1]
	//   1.2300e+4   -> [12300,-12300,12300]
	//   01          -> [1,-1,1]
	//   00.0100     -> [0.0100,-0.0100,0.0100]
	//   000e+2      -> [0E+2,0E+2,0E+2]
	//   -000e+2     -> [-0E+2,0E+2,0E+2]
	//   0           -> [0,0,0]
	//   -0.000      -> [-0.000,0.000,0.000]
	//   -4e-1147483647 -> [-0E-1147483646,0E-1147483646,0E-1147483646]
	// For each zero family, `copysign(1;.)`, `copysign(1;-.)`, and
	// `copysign(1;--.)` return [-1,1,1] for a negative source and [1,1,1]
	// for a positive source, exposing the native sign after negation.
	//   9007199254740993 -> [9007199254740993,-9007199254740993,9007199254740993]
	//   1e999999999 -> [1E+999999999,-1E+999999999,1E+999999999]
	//   4e-1147483647 -> [0E-1147483646,0E-1147483646,0E-1147483646]
	// jq filter syntax rejects leading `+` (exit 3), while the decNumber value
	// constructor accepts it; those private-constructor cases verify that fresh
	// negation never restores the constructor-only explicit sign.
	cases := [?]Literal_Case{
		{"1e+00", "-1", "1"},
		{"1E+00", "-1", "1"},
		{"1.2300e+4", "-12300", "12300"},
		{"+1.2300e+4", "-12300", "12300"},
		{"-1.2300e+4", "12300", "-12300"},
		{"1.2300", "-1.2300", "1.2300"},
		{"123.00", "-123.00", "123.00"},
		{"01", "-1", "1"},
		{"00.0100", "-0.0100", "0.0100"},
		{"000e+2", "0E+2", "0E+2"},
		{"-000e+2", "0E+2", "0E+2"},
		{"0", "0", "0"},
		{"-0", "0", "0"},
		{"0.00", "0.00", "0.00"},
		{"-0.00", "0.00", "0.00"},
		{"0.000", "0.000", "0.000"},
		{"-0.000", "0.000", "0.000"},
		{"0e-20", "0E-20", "0E-20"},
		{"-0e-20", "0E-20", "0E-20"},
		{"9007199254740993", "-9007199254740993", "9007199254740993"},
		{"123456789012345678901234567890.00", "-123456789012345678901234567890.00", "123456789012345678901234567890.00"},
		{"1e999999999", "-1E+999999999", "1E+999999999"},
		{"1E+999999999", "-1E+999999999", "1E+999999999"},
		{"1e-1147483646", "-1E-1147483646", "1E-1147483646"},
		{"4e-1147483647", "0E-1147483646", "0E-1147483646"},
		{"-4e-1147483647", "0E-1147483646", "0E-1147483646"},
		{"1e1000000000", "-Infinity", "Infinity"},
		{"Infinity", "-Infinity", "Infinity"},
	}
	for test_case in cases {
		source, source_error := literal_number_value(test_case.source, context.allocator)
		testing.expect_value(t, constructor_error_kind(&source_error), Error.None)
		probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
		result, result_error, result_negated := number_negate(&source, probe_allocator(&probe))
		first_allocation_size := probe.last_size
		second, second_error, second_negated := number_negate(&result, probe_allocator(&probe))
		testing.expect_value(t, constructor_error_kind(&result_error), Error.None)
		testing.expect_value(t, constructor_error_kind(&second_error), Error.None)
		testing.expect(t, result_negated && second_negated)
		testing.expect_value(t, probe.allocations, 2)
		testing.expect_value(t, probe.live, 2)
		source_spelling, source_ok := literal_spelling_borrowed(&source)
		result_spelling, result_ok := literal_spelling_borrowed(&result)
		second_spelling, second_ok := literal_spelling_borrowed(&second)
		testing.expect(t, source_ok && source_spelling == test_case.source)
		testing.expect(t, result_ok && result_spelling == test_case.first_expected)
		testing.expect(t, second_ok && second_spelling == test_case.second_expected)
		if source_ok && result_ok && second_ok {
			source_payload := value_storage_of(&source).owned_payload
			first_expected_size := int(size_of(payload)) + len(test_case.first_expected) + source_payload.coefficient_len
			second_expected_size := int(size_of(payload)) + len(test_case.second_expected) + source_payload.coefficient_len
			testing.expect_value(t, first_allocation_size, first_expected_size)
			testing.expect_value(t, probe.last_size, second_expected_size)
			literal_metadata_matches_negation(
				t,
				source_payload,
				value_storage_of(&result).owned_payload,
			)
			literal_metadata_matches_negation(
				t,
				value_storage_of(&result).owned_payload,
				value_storage_of(&second).owned_payload,
			)
		}
		destroy_constructor_error(&source_error)
		destroy_constructor_error(&result_error)
		destroy_constructor_error(&second_error)
		testing.expect_value(t, destroy_value(&second), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.frees, 2)
		testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	}
}

@(test)
literal_zero_negation_canonicalizes_all_sign_state :: proc(t: ^testing.T) {
	Zero_Case :: struct {
		source:   string,
		expected: string,
	}
	cases := [?]Zero_Case{
		{"0", "0"},
		{"+0", "0"},
		{"-0", "0"},
		{"0.00", "0.00"},
		{"-0.00", "0.00"},
		{"000e+2", "0E+2"},
		{"-000e+2", "0E+2"},
		{"0e-20", "0E-20"},
		{"-0e-20", "0E-20"},
		{"4e-1147483647", "0E-1147483646"},
		{"-4e-1147483647", "0E-1147483646"},
	}
	for test_case in cases {
		source, source_error := literal_number_value(test_case.source, context.allocator)
		first, first_error, first_ok := number_negate(&source, context.allocator)
		second, second_error, second_ok := number_negate(&first, context.allocator)
		testing.expect_value(t, constructor_error_kind(&source_error), Error.None)
		testing.expect_value(t, constructor_error_kind(&first_error), Error.None)
		testing.expect_value(t, constructor_error_kind(&second_error), Error.None)
		testing.expect(t, first_ok && second_ok)

		first_spelling, first_spelling_ok := literal_spelling_borrowed(&first)
		second_spelling, second_spelling_ok := literal_spelling_borrowed(&second)
		testing.expect(t, first_spelling_ok && first_spelling == test_case.expected)
		testing.expect(t, second_spelling_ok && second_spelling == test_case.expected)

		first_storage := value_storage_of(&first)
		second_storage := value_storage_of(&second)
		if first_storage.owned_payload != nil && second_storage.owned_payload != nil {
			literal_metadata_matches_negation(
				t,
				value_storage_of(&source).owned_payload,
				first_storage.owned_payload,
			)
			literal_metadata_matches_negation(
				t,
				first_storage.owned_payload,
				second_storage.owned_payload,
			)
		}
		first_number, first_number_ok := number_value_get(&first)
		second_number, second_number_ok := number_value_get(&second)
		testing.expect(t, first_number_ok && first_number == 0 && !math.sign_bit(first_number))
		testing.expect(t, second_number_ok && second_number == 0 && !math.sign_bit(second_number))

		destroy_value(&second)
		destroy_value(&first)
		destroy_value(&source)
		destroy_constructor_error(&second_error)
		destroy_constructor_error(&first_error)
		destroy_constructor_error(&source_error)
	}
}

@(test)
literal_negation_owners_destroy_independently_and_double_negation_restores :: proc(t: ^testing.T) {
	source, source_error := literal_number_value("+9007199254740993.00e-2", context.allocator)
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	first, first_error, first_succeeded := number_negate(&source, probe_allocator(&probe))
	second, second_error, second_succeeded := number_negate(&first, probe_allocator(&probe))
	testing.expect_value(t, constructor_error_kind(&source_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&first_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&second_error), Error.None)
	testing.expect(t, first_succeeded && second_succeeded)
	testing.expect_value(t, probe.allocations, 2)

	source_spelling, source_ok := literal_spelling_borrowed(&source)
	first_spelling, first_ok := literal_spelling_borrowed(&first)
	second_spelling, second_ok := literal_spelling_borrowed(&second)
	testing.expect(t, source_ok && source_spelling == "+9007199254740993.00e-2")
	testing.expect(t, first_ok && first_spelling == "-90071992547409.9300")
	testing.expect(t, second_ok && second_spelling == "90071992547409.9300")
	if source_ok && second_ok {
		source_payload := value_storage_of(&source).owned_payload
		second_payload := value_storage_of(&second).owned_payload
		testing.expect(t, source_payload != second_payload)
		testing.expect_value(t, source_payload.negative, second_payload.negative)
		testing.expect_value(t, source_payload.exponent, second_payload.exponent)
		testing.expect_value(t, source_payload.infinite, second_payload.infinite)
		testing.expect_value(
			t,
			transmute(u64)source_payload.native_cache,
			transmute(u64)second_payload.native_cache,
		)
		testing.expect(
			t,
			string(payload_coefficient(source_payload)) == string(payload_coefficient(second_payload)),
		)
	}

	// Source-first retirement cannot affect either independent destination.
	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	first_after, first_after_ok := literal_spelling_borrowed(&first)
	second_after, second_after_ok := literal_spelling_borrowed(&second)
	testing.expect(t, first_after_ok && first_after == "-90071992547409.9300")
	testing.expect(t, second_after_ok && second_after == "90071992547409.9300")
	testing.expect_value(t, destroy_value(&second), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 1)
	testing.expect_value(t, destroy_value(&first), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	destroy_constructor_error(&source_error)
	destroy_constructor_error(&first_error)
	destroy_constructor_error(&second_error)
}

@(test)
literal_negation_allocation_failures_preserve_source_and_cleanup :: proc(t: ^testing.T) {
	source, source_error := literal_number_value("1.25", context.allocator)
	defer destroy_value(&source)
	defer destroy_constructor_error(&source_error)
	testing.expect_value(t, constructor_error_kind(&source_error), Error.None)

	failing := allocator_probe{backing = context.allocator, fail_after = 0}
	failed, failed_error, failed_ok := number_negate(&source, probe_allocator(&failing))
	testing.expect_value(t, kind_of(&failed), Kind.Invalid)
	testing.expect(t, !failed_ok)
	testing.expect_value(t, constructor_error_kind(&failed_error), Error.Out_Of_Memory)
	testing.expect_value(t, failing.allocations, 1)
	destroy_constructor_error(&failed_error)

	nil_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		nil_success = true,
	}
	nil_result, nil_error, nil_ok := number_negate(&source, probe_allocator(&nil_probe))
	testing.expect_value(t, kind_of(&nil_result), Kind.Invalid)
	testing.expect(t, !nil_ok)
	testing.expect_value(t, constructor_error_kind(&nil_error), Error.Out_Of_Memory)
	testing.expect_value(t, nil_probe.frees, 0)
	destroy_constructor_error(&nil_error)

	short_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
	}
	short_result, short_error, short_ok := number_negate(&source, probe_allocator(&short_probe))
	testing.expect_value(t, kind_of(&short_result), Kind.Invalid)
	testing.expect(t, !short_ok)
	testing.expect_value(t, constructor_error_kind(&short_error), Error.Out_Of_Memory)
	testing.expect_value(t, short_probe.frees, 1)
	testing.expect_value(t, short_probe.live, 0)
	destroy_constructor_error(&short_error)

	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		short_success = true,
		free_failures_remaining = 2,
	}
	retry_result, retry_error, retry_ok := number_negate(&source, probe_allocator(&retry_probe))
	testing.expect_value(t, kind_of(&retry_result), Kind.Invalid)
	testing.expect(t, !retry_ok)
	testing.expect_value(t, constructor_error_kind(&retry_error), Error.Out_Of_Memory)
	testing.expect(t, constructor_error_needs_cleanup(&retry_error))
	moved_error := take_constructor_error(&retry_error)
	testing.expect_value(t, constructor_error_kind(&retry_error), Error.None)
	testing.expect_value(
		t,
		destroy_constructor_error(&moved_error),
		runtime.Allocator_Error.Invalid_Pointer,
	)
	testing.expect(t, constructor_error_needs_cleanup(&moved_error))
	testing.expect_value(t, destroy_constructor_error(&moved_error), runtime.Allocator_Error.None)
	testing.expect_value(t, retry_probe.frees, 3)
	testing.expect_value(t, retry_probe.live, 0)

	spelling, spelling_ok := literal_spelling_borrowed(&source)
	testing.expect(t, spelling_ok && spelling == "1.25")
}

negation_bulk_mismatch_probe :: struct {
	backing:     runtime.Allocator,
	allocations: int,
	frees:       int,
}

negation_bulk_mismatch_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	probe := cast(^negation_bulk_mismatch_probe)data
	#partial switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		probe.allocations += 1
		return probe.backing.procedure(
			probe.backing.data,
			mode,
			max(size - 1, 0),
			alignment,
			old_memory,
			old_size,
			location,
		)
	case .Free:
		probe.frees += 1
		return nil, .Mode_Not_Implemented
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
literal_negation_mismatch_bulk_retirement_is_successful :: proc(t: ^testing.T) {
	arena: runtime.Arena
	init_error := runtime.arena_init(&arena, 4096, context.allocator)
	testing.expect_value(t, init_error, runtime.Allocator_Error.None)
	if init_error != nil {
		return
	}
	source, source_error := literal_number_value("2.5", context.allocator)
	probe := negation_bulk_mismatch_probe{backing = runtime.arena_allocator(&arena)}
	allocator := runtime.Allocator{
		procedure = negation_bulk_mismatch_allocator_proc,
		data = &probe,
	}
	result, err, ok := number_negate(&source, allocator)
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect(t, !ok)
	testing.expect_value(t, constructor_error_kind(&err), Error.Out_Of_Memory)
	testing.expect(t, !constructor_error_needs_cleanup(&err))
	testing.expect_value(t, probe.allocations, 1)
	testing.expect_value(t, probe.frees, 1)
	destroy_constructor_error(&err)
	destroy_value(&result)
	destroy_value(&source)
	destroy_constructor_error(&source_error)
	runtime.arena_destroy(&arena)
}

@(test)
literal_negation_final_destroy_failure_is_retryable :: proc(t: ^testing.T) {
	source, source_error := literal_number_value("-0.00", context.allocator)
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	result, result_error, ok := number_negate(&source, probe_allocator(&probe))
	testing.expect_value(t, constructor_error_kind(&source_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&result_error), Error.None)
	testing.expect(t, ok)
	result_number_kind, result_is_number := number_kind(&result)
	if !result_is_number || result_number_kind != .Literal {
		destroy_value(&source)
		destroy_constructor_error(&source_error)
		destroy_constructor_error(&result_error)
		return
	}
	storage := value_storage_of(&result)
	payload_before := storage.owned_payload
	cache_before := transmute(u64)storage.owned_payload.native_cache
	first_error := destroy_value(&result)
	testing.expect_value(t, first_error, runtime.Allocator_Error.Invalid_Pointer)
	testing.expect_value(t, kind_of(&result), Kind.Number)
	testing.expect(t, value_storage_of(&result).owned_payload == payload_before)
	testing.expect_value(t, transmute(u64)value_storage_of(&result).owned_payload.native_cache, cache_before)
	spelling, spelling_ok := literal_spelling_borrowed(&result)
	testing.expect(t, spelling_ok && spelling == "0.00")
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 2)
	testing.expect_value(t, probe.live, 0)
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 2)
	destroy_value(&source)
	destroy_constructor_error(&source_error)
	destroy_constructor_error(&result_error)
}

@(test)
literal_negation_output_first_destruction_preserves_source :: proc(t: ^testing.T) {
	source, source_error := literal_number_value("8e-3", context.allocator)
	result, result_error, negated := number_negate(&source, context.allocator)
	testing.expect_value(t, constructor_error_kind(&source_error), Error.None)
	testing.expect_value(t, constructor_error_kind(&result_error), Error.None)
	testing.expect(t, negated)
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
	spelling, ok := literal_spelling_borrowed(&source)
	testing.expect(t, ok && spelling == "8e-3")
	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	destroy_constructor_error(&source_error)
	destroy_constructor_error(&result_error)
}

@(test)
native_nan_sign_cases_are_nan_after_negation :: proc(t: ^testing.T) {
	positive := number_value(transmute(f64)u64(0x7ff8000000001234))
	negative := number_value(transmute(f64)u64(0xfff8000000001234))
	positive_result, positive_error, positive_negated := number_negate(&positive, context.allocator)
	negative_result, negative_error, negative_negated := number_negate(&negative, context.allocator)
	positive_number, positive_ok := number_value_get(&positive_result)
	negative_number, negative_ok := number_value_get(&negative_result)
	testing.expect(t, positive_ok && math.is_nan(positive_number) && math.sign_bit(positive_number))
	testing.expect(t, negative_ok && math.is_nan(negative_number) && !math.sign_bit(negative_number))
	testing.expect(t, positive_negated && negative_negated)
	destroy_value(&positive)
	destroy_value(&negative)
	destroy_value(&positive_result)
	destroy_value(&negative_result)
	destroy_constructor_error(&positive_error)
	destroy_constructor_error(&negative_error)
}
