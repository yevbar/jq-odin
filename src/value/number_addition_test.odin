package value

import "base:runtime"
import "core:math"
import "core:testing"

expect_add_rejection :: proc(t: ^testing.T, left, right: ^Value) {
	result, ok := number_add(left, right)
	testing.expect(t, !ok)
	testing.expect_value(t, kind_of(&result), Kind.Invalid)
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
}

@(test)
number_add_rejects_nil_invalid_and_non_numbers :: proc(t: ^testing.T) {
	invalid := invalid_value()
	null := null_value()
	boolean := boolean_value(true)
	string_owned, string_error := string_value("x", context.allocator)
	number := number_value(1)
	defer destroy_value(&string_owned)
	defer destroy_constructor_error(&string_error)

	sources := [4]^Value{&invalid, &null, &boolean, &string_owned}
	for source in sources {
		expect_add_rejection(t, source, &number)
		expect_add_rejection(t, &number, source)
	}
	expect_add_rejection(t, nil, &number)
	expect_add_rejection(t, &number, nil)
	expect_add_rejection(t, nil, nil)
	number_after, number_ok := number_value_get(&number)
	testing.expect(t, number_ok && number_after == 1)
}

@(test)
number_add_all_representation_pairs_return_inline_native :: proc(t: ^testing.T) {
	literal_left, left_error := literal_number_value("1.25", context.allocator)
	literal_right, right_error := literal_number_value("2.50", context.allocator)
	native_left := number_value(1.25)
	native_right := number_value(2.5)
	defer destroy_value(&literal_left)
	defer destroy_value(&literal_right)
	defer destroy_value(&native_left)
	defer destroy_value(&native_right)
	defer destroy_constructor_error(&left_error)
	defer destroy_constructor_error(&right_error)

	pairs := [4][2]^Value{
		{&literal_left, &literal_right},
		{&literal_left, &native_right},
		{&native_left, &literal_right},
		{&native_left, &native_right},
	}
	for pair in pairs {
		result, ok := number_add(pair[0], pair[1])
		testing.expect(t, ok)
		kind, kind_ok := number_kind(&result)
		number, number_ok := number_value_get(&result)
		testing.expect(t, kind_ok && kind == .Native)
		testing.expect(t, number_ok && number == 3.75)
		testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
	}
	left_spelling, left_ok := literal_spelling_borrowed(&literal_left)
	right_spelling, right_ok := literal_spelling_borrowed(&literal_right)
	testing.expect(t, left_ok && left_spelling == "1.25")
	testing.expect(t, right_ok && right_spelling == "2.50")
}

@(test)
number_add_matches_binary64_rounding_and_boundaries :: proc(t: ^testing.T) {
	Addition_Case :: struct {
		left:     string,
		right:    string,
		expected: u64,
	}
	// Expected bits are the native results behind pinned jq 1.8.1 compact
	// probes. Literal conversion occurs before the binary64 addition.
	cases := [?]Addition_Case{
		{"0.1", "0.2", 0x3fd3333333333334},
		{"9007199254740993", "1", 0x4340000000000000},
		{"9007199254740991", "1", 0x4340000000000000},
		{"1.0000000000000001", "0", 0x3ff0000000000000},
		{"1.0000000000000002", "0", 0x3ff0000000000001},
		{"2.2250738585072014e-308", "0", 0x0010000000000000},
		{"5e-324", "5e-324", 0x0000000000000002},
		{"5e-324", "-5e-324", 0x0000000000000000},
		{"1e-1147483646", "0", 0x0000000000000000},
		{"4e-1147483647", "0", 0x0000000000000000},
	}
	for test_case in cases {
		left, left_error := literal_number_value(test_case.left, context.allocator)
		right, right_error := literal_number_value(test_case.right, context.allocator)
		result, ok := number_add(&left, &right)
		result_number, number_ok := number_value_get(&result)
		testing.expect_value(t, constructor_error_kind(&left_error), Error.None)
		testing.expect_value(t, constructor_error_kind(&right_error), Error.None)
		testing.expect(t, ok && number_ok)
		testing.expect_value(t, transmute(u64)result_number, test_case.expected)
		destroy_value(&result)
		destroy_value(&right)
		destroy_value(&left)
		destroy_constructor_error(&right_error)
		destroy_constructor_error(&left_error)
	}
}

@(test)
number_add_signed_zero_infinity_and_single_nan :: proc(t: ^testing.T) {
	zero_bits := [?][3]u64{
		{0x0000000000000000, 0x0000000000000000, 0x0000000000000000},
		{0x0000000000000000, 0x8000000000000000, 0x0000000000000000},
		{0x8000000000000000, 0x0000000000000000, 0x0000000000000000},
		{0x8000000000000000, 0x8000000000000000, 0x8000000000000000},
	}
	for bits in zero_bits {
		left := number_value(transmute(f64)bits[0])
		right := number_value(transmute(f64)bits[1])
		result, ok := number_add(&left, &right)
		number, number_ok := number_value_get(&result)
		testing.expect(t, ok && number_ok)
		testing.expect_value(t, transmute(u64)number, bits[2])
		destroy_value(&result)
	}
	literal_negative_zero, literal_zero_error := literal_number_value("-0.00", context.allocator)
	literal_zero_sum, literal_zero_ok := number_add(&literal_negative_zero, &literal_negative_zero)
	literal_zero_number, literal_zero_number_ok := number_value_get(&literal_zero_sum)
	testing.expect(t, literal_zero_ok && literal_zero_number_ok)
	testing.expect_value(t, transmute(u64)literal_zero_number, u64(0x8000000000000000))
	destroy_value(&literal_zero_sum)
	destroy_value(&literal_negative_zero)
	destroy_constructor_error(&literal_zero_error)

	maximum, maximum_error := literal_number_value("1.7976931348623157e308", context.allocator)
	overflow, overflow_ok := number_add(&maximum, &maximum)
	overflow_number, overflow_number_ok := number_value_get(&overflow)
	testing.expect(t, overflow_ok && overflow_number_ok && math.is_inf(overflow_number))

	positive_infinity, positive_error := literal_number_value("1e999999999", context.allocator)
	negative_infinity, negative_error := literal_number_value("-1e999999999", context.allocator)
	nan_result, nan_ok := number_add(&positive_infinity, &negative_infinity)
	nan_number, nan_number_ok := number_value_get(&nan_result)
	testing.expect(t, nan_ok && nan_number_ok && math.is_nan(nan_number))

	left_nan_bits := u64(0x7ff8000000000042)
	left_nan := number_value(transmute(f64)left_nan_bits)
	one := number_value(1)
	payload_result, payload_ok := number_add(&left_nan, &one)
	payload_number, payload_number_ok := number_value_get(&payload_result)
	testing.expect(t, payload_ok && payload_number_ok && math.is_nan(payload_number))
	// A sole NaN is selected without canonicalizing its quiet payload.
	testing.expect_value(t, transmute(u64)payload_number, left_nan_bits)

	values := [8]^Value{&payload_result, &one, &left_nan, &nan_result, &negative_infinity, &positive_infinity, &overflow, &maximum}
	for value in values {
		destroy_value(value)
	}
	errors := [3]^Constructor_Error{&negative_error, &positive_error, &maximum_error}
	for err in errors {
		destroy_constructor_error(err)
	}
}

@(test)
number_add_selects_jq_compatible_nan_operand :: proc(t: ^testing.T) {
	NaN_Case :: struct {
		left:     u64,
		right:    u64,
		expected: u64,
	}
	positive_quiet := u64(0x7ff8000000000042)
	negative_quiet := u64(0xfff8000000000099)
	positive_signaling := u64(0x7ff0000000000011)
	negative_signaling := u64(0xfff0000000000022)
	one := u64(0x3ff0000000000000)
	// Exact results come from binop_plus in the pinned jq 1.8.1 static
	// library. jq's language-level copysign oracle additionally observes the
	// signs of both quiet-NaN operand orders. A selected signaling NaN is
	// quieted, just as it is by jq's C double addition.
	cases := [?]NaN_Case{
		{positive_quiet, one, positive_quiet},
		{one, negative_quiet, negative_quiet},
		{positive_quiet, negative_quiet, negative_quiet},
		{negative_quiet, positive_quiet, positive_quiet},
		{positive_signaling, one, 0x7ff8000000000011},
		{one, negative_signaling, 0xfff8000000000022},
		{positive_signaling, negative_quiet, negative_quiet},
		{positive_quiet, negative_signaling, 0xfff8000000000022},
		{positive_signaling, negative_signaling, 0xfff8000000000022},
		{negative_signaling, positive_signaling, 0x7ff8000000000011},
	}
	for test_case in cases {
		left := number_value(transmute(f64)test_case.left)
		right := number_value(transmute(f64)test_case.right)
		result, ok := number_add(&left, &right)
		number, number_ok := number_value_get(&result)
		testing.expect(t, ok && number_ok && math.is_nan(number))
		testing.expect_value(t, transmute(u64)number, test_case.expected)
		testing.expect_value(t, math.sign_bit(number), test_case.expected >> 63 == 1)
		destroy_value(&result)
	}
}

@(test)
number_add_nan_selection_covers_literal_native_pairs :: proc(t: ^testing.T) {
	literal_finite, finite_error := literal_number_value("1.25", context.allocator)
	literal_infinity, infinity_error := literal_number_value("1e999999999", context.allocator)
	positive_nan_bits := u64(0x7ff8000000000042)
	negative_nan_bits := u64(0xfff8000000000099)
	positive_nan := number_value(transmute(f64)positive_nan_bits)
	negative_nan := number_value(transmute(f64)negative_nan_bits)
	defer destroy_value(&literal_finite)
	defer destroy_value(&literal_infinity)
	defer destroy_constructor_error(&finite_error)
	defer destroy_constructor_error(&infinity_error)

	pairs := [4][2]^Value{
		{&positive_nan, &literal_finite},
		{&literal_finite, &negative_nan},
		{&negative_nan, &literal_infinity},
		{&literal_infinity, &positive_nan},
	}
	expected := [4]u64{
		positive_nan_bits,
		negative_nan_bits,
		negative_nan_bits,
		positive_nan_bits,
	}
	for pair, i in pairs {
		result, ok := number_add(pair[0], pair[1])
		number, number_ok := number_value_get(&result)
		testing.expect(t, ok && number_ok && math.is_nan(number))
		testing.expect_value(t, transmute(u64)number, expected[i])
		destroy_value(&result)
	}
}

@(test)
number_add_literal_nan_canonical_in_both_operand_orders :: proc(t: ^testing.T) {
	left_nan, left_error := literal_number_value("NaN", context.allocator)
	right_nan, right_error := literal_number_value("NaN", context.allocator)
	left_finite, left_finite_error := literal_number_value("1", context.allocator)
	right_finite, right_finite_error := literal_number_value("1", context.allocator)
	defer destroy_value(&left_nan)
	defer destroy_value(&right_nan)
	defer destroy_value(&left_finite)
	defer destroy_value(&right_finite)
	defer destroy_constructor_error(&left_error)
	defer destroy_constructor_error(&right_error)
	defer destroy_constructor_error(&left_finite_error)
	defer destroy_constructor_error(&right_finite_error)

	pairs := [2][2]^Value{
		{&left_nan, &right_finite},
		{&left_finite, &right_nan},
	}
	for pair in pairs {
		result, ok := number_add(pair[0], pair[1])
		number, number_ok := number_value_get(&result)
		testing.expect(t, ok && number_ok && math.is_nan(number))
		testing.expect_value(t, transmute(u64)number, u64(0x7ff8000000000000))
		destroy_value(&result)
	}
}

@(test)
number_add_literal_native_nan_pairs_are_canonical :: proc(t: ^testing.T) {
	literal_nan, literal_error := literal_number_value("-NaN", context.allocator)
	native_finite := number_value(1)
	defer destroy_value(&literal_nan)
	defer destroy_constructor_error(&literal_error)

	pairs := [2][2]^Value{
		{&literal_nan, &native_finite},
		{&native_finite, &literal_nan},
	}
	for pair in pairs {
		result, ok := number_add(pair[0], pair[1])
		number, number_ok := number_value_get(&result)
		testing.expect(t, ok && number_ok && math.is_nan(number))
		testing.expect_value(t, transmute(u64)number, u64(0x7ff8000000000000))
		destroy_value(&result)
	}
}

@(test)
number_add_non_nan_operands_keep_native_infinity_nan :: proc(t: ^testing.T) {
	positive_infinity := transmute(f64)u64(0x7ff0000000000000)
	negative_infinity := transmute(f64)u64(0xfff0000000000000)
	orders := [2][2]f64{
		{positive_infinity, negative_infinity},
		{negative_infinity, positive_infinity},
	}
	for operands in orders {
		// Infinity-generated NaN is target/compiler behavior, not jq's
		// cross-platform operand-selection contract. Keep the ordinary Odin
		// binary64 operation bit-for-bit when neither input is NaN.
		expected := operands[0] + operands[1]
		left := number_value(operands[0])
		right := number_value(operands[1])
		result, ok := number_add(&left, &right)
		number, number_ok := number_value_get(&result)
		testing.expect(t, ok && number_ok && math.is_nan(number))
		testing.expect_value(t, transmute(u64)number, transmute(u64)expected)
		destroy_value(&result)
	}
}

@(test)
number_add_repeated_calls_round_after_each_operation :: proc(t: ^testing.T) {
	one_tenth, one_error := literal_number_value("0.1", context.allocator)
	two_tenths, two_error := literal_number_value("0.2", context.allocator)
	three_tenths, three_error := literal_number_value("0.3", context.allocator)
	left_first, left_first_ok := number_add(&one_tenth, &two_tenths)
	left_result, left_ok := number_add(&left_first, &three_tenths)
	right_first, right_first_ok := number_add(&two_tenths, &three_tenths)
	right_result, right_ok := number_add(&one_tenth, &right_first)
	left_number, left_number_ok := number_value_get(&left_result)
	right_number, right_number_ok := number_value_get(&right_result)
	testing.expect(t, left_first_ok && left_ok && right_first_ok && right_ok)
	testing.expect(t, left_number_ok && right_number_ok)
	testing.expect_value(t, transmute(u64)left_number, u64(0x3fe3333333333334))
	testing.expect_value(t, transmute(u64)right_number, u64(0x3fe3333333333333))

	values := [7]^Value{&right_result, &right_first, &left_result, &left_first, &three_tenths, &two_tenths, &one_tenth}
	for value in values {
		destroy_value(value)
	}
	errors := [3]^Constructor_Error{&three_error, &two_error, &one_error}
	for err in errors {
		destroy_constructor_error(err)
	}
}

@(test)
number_decimal_parity_boundary_keeps_jq_binary64_result :: proc(t: ^testing.T) {
	// jq 1.8.1 rounds each arithmetic operation as binary64. The value
	// boundary therefore ends with these bits; any textual difference for
	// this result belongs to the JSON serializer, not literal preservation or
	// arithmetic rounding in value.
	first, first_error := literal_number_value("1e-19", context.allocator)
	second, second_error := literal_number_value("1e-20", context.allocator)
	third, third_error := literal_number_value("5e-21", context.allocator)
	defer destroy_value(&first)
	defer destroy_value(&second)
	defer destroy_value(&third)
	defer destroy_constructor_error(&first_error)
	defer destroy_constructor_error(&second_error)
	defer destroy_constructor_error(&third_error)

	sum, sum_ok := number_add(&first, &second)
	result, result_kind := number_subtract(&sum, &third)
	defer destroy_value(&sum)
	defer destroy_value(&result)

	result_number, number_ok := number_value_get(&result)
	testing.expect(t, sum_ok && result_kind == .Success && number_ok)
	testing.expect_value(t, transmute(u64)result_number, u64(0x3bfefd93607ff6ce))
}

@(test)
number_add_borrows_aliases_clones_and_owners_independently :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	source, source_error := literal_number_value("9007199254740993", probe_allocator(&probe))
	clone := clone_value(&source)
	allocations_before := probe.allocations
	probe.fail_after = probe.allocations

	aliased, alias_ok := number_add(&source, &source)
	cloned, clone_ok := number_add(&source, &clone)
	testing.expect(t, alias_ok && clone_ok)
	testing.expect_value(t, probe.allocations, allocations_before)
	alias_number, alias_number_ok := number_value_get(&aliased)
	clone_number, clone_number_ok := number_value_get(&cloned)
	testing.expect(t, alias_number_ok && clone_number_ok)
	testing.expect_value(t, transmute(u64)alias_number, u64(0x4350000000000000))
	testing.expect_value(t, transmute(u64)clone_number, u64(0x4350000000000000))

	// Result-first and source-first retirement are independent. The retained
	// shallow clone keeps the literal payload live after its source is gone.
	testing.expect_value(t, destroy_value(&aliased), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 0)
	testing.expect_value(t, destroy_value(&source), runtime.Allocator_Error.None)
	spelling, spelling_ok := literal_spelling_borrowed(&clone)
	testing.expect(t, spelling_ok && spelling == "9007199254740993")
	testing.expect_value(t, destroy_value(&clone), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, 1)
	testing.expect_value(t, destroy_value(&cloned), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.allocations, allocations_before)
	destroy_constructor_error(&source_error)
}

@(test)
number_add_has_no_allocator_or_cleanup_failure_boundary :: proc(t: ^testing.T) {
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 1,
	}
	left, left_error := literal_number_value("1.5", probe_allocator(&probe))
	right, right_error := literal_number_value("2.5", probe_allocator(&probe))
	allocations_before := probe.allocations
	frees_before := probe.frees
	probe.fail_after = probe.allocations
	result, ok := number_add(&left, &right)
	result_number, number_ok := number_value_get(&result)
	testing.expect(t, ok && number_ok && result_number == 4)
	testing.expect_value(t, probe.allocations, allocations_before)
	testing.expect_value(t, probe.frees, frees_before)
	// Inline result destruction cannot invoke either the failing source
	// allocator or Constructor_Error cleanup machinery.
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.frees, frees_before)
	probe.free_failures_remaining = 0
	destroy_value(&right)
	destroy_value(&left)
	destroy_constructor_error(&right_error)
	destroy_constructor_error(&left_error)
	testing.expect_value(t, probe.allocations, probe.frees)
}
