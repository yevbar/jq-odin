package value

import "base:runtime"
import "core:math"
import "core:testing"

Arithmetic_Proc :: proc(left, right: ^Value) -> (Value, Number_Arithmetic_Result_Kind)

expect_arithmetic_bits :: proc(
	t: ^testing.T,
	operation: Arithmetic_Proc,
	left_bits, right_bits, expected_bits: u64,
) {
	left := number_value(transmute(f64)left_bits)
	right := number_value(transmute(f64)right_bits)
	result, kind := operation(&left, &right)
	number, number_ok := number_value_get(&result)
	testing.expect_value(t, kind, Number_Arithmetic_Result_Kind.Success)
	testing.expect(t, number_ok)
	testing.expect_value(t, transmute(u64)number, expected_bits)
	testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
}

@(test)
number_arithmetic_rejects_non_numbers_without_mutation :: proc(t: ^testing.T) {
	invalid := invalid_value()
	null := null_value()
	boolean := boolean_value(true)
	string_owned, string_error := string_value("x", context.allocator)
	number := number_value(3)
	defer destroy_value(&string_owned)
	defer destroy_constructor_error(&string_error)

	operations := [?]Arithmetic_Proc{
		number_subtract,
		number_multiply,
		number_divide,
		number_modulo,
	}
	nonnumbers := [?]^Value{nil, &invalid, &null, &boolean, &string_owned}
	for operation in operations {
		for nonnumber in nonnumbers {
			left_result, left_kind := operation(nonnumber, &number)
			right_result, right_kind := operation(&number, nonnumber)
			testing.expect_value(t, left_kind, Number_Arithmetic_Result_Kind.Invalid_Operands)
			testing.expect_value(t, right_kind, Number_Arithmetic_Result_Kind.Invalid_Operands)
			testing.expect_value(t, kind_of(&left_result), Kind.Invalid)
			testing.expect_value(t, kind_of(&right_result), Kind.Invalid)
		}
	}
	number_after, number_ok := number_value_get(&number)
	testing.expect(t, number_ok && number_after == 3)
}

@(test)
number_arithmetic_covers_every_representation_pair :: proc(t: ^testing.T) {
	literal_left, left_error := literal_number_value("7.5", context.allocator)
	literal_right, right_error := literal_number_value("2.25", context.allocator)
	native_left := number_value(7.5)
	native_right := number_value(2.25)
	defer destroy_value(&literal_left)
	defer destroy_value(&literal_right)
	defer destroy_constructor_error(&left_error)
	defer destroy_constructor_error(&right_error)

	pairs := [?][2]^Value{
		{&native_left, &native_right},
		{&native_left, &literal_right},
		{&literal_left, &native_right},
		{&literal_left, &literal_right},
	}
	operations := [?]Arithmetic_Proc{
		number_subtract,
		number_multiply,
		number_divide,
		number_modulo,
	}
	expected := [?]u64{
		0x4015000000000000, // 5.25
		0x4030e00000000000, // 16.875
		0x400aaaaaaaaaaaab, // 3.3333333333333335
		0x3ff0000000000000, // jq intmax remainder is 1
	}
	for pair in pairs {
		for operation, i in operations {
			result, kind := operation(pair[0], pair[1])
			result_kind, result_kind_ok := number_kind(&result)
			number, number_ok := number_value_get(&result)
			testing.expect_value(t, kind, Number_Arithmetic_Result_Kind.Success)
			testing.expect(t, result_kind_ok && result_kind == .Native)
			testing.expect(t, number_ok)
			testing.expect_value(t, transmute(u64)number, expected[i])
			destroy_value(&result)
		}
	}
	left_spelling, left_ok := literal_spelling_borrowed(&literal_left)
	right_spelling, right_ok := literal_spelling_borrowed(&literal_right)
	testing.expect(t, left_ok && left_spelling == "7.5")
	testing.expect(t, right_ok && right_spelling == "2.25")
}

@(test)
number_subtract_pins_binary64_edges_and_nan_selection :: proc(t: ^testing.T) {
	cases := [?][3]u64{
		{0, 0, 0},
		{0, 0x8000000000000000, 0},
		{0x8000000000000000, 0, 0x8000000000000000},
		{0x8000000000000000, 0x8000000000000000, 0},
		{0x0010000000000000, 0x0000000000000001, 0x000fffffffffffff},
		{0x7fefffffffffffff, 0xffefffffffffffff, 0x7ff0000000000000},
		{0x7ff0000000000000, 0x7ff0000000000000, 0xfff8000000000000},
		{0x7ff8000000000042, 0xfff8000000000099, 0x7ff8000000000042},
		{0xfff8000000000099, 0x7ff8000000000042, 0xfff8000000000099},
		{0x7ff0000000000011, 0x3ff0000000000000, 0x7ff8000000000011},
		{0x3ff0000000000000, 0xfff0000000000022, 0xfff8000000000022},
	}
	for test_case in cases {
		expect_arithmetic_bits(t, number_subtract, test_case[0], test_case[1], test_case[2])
	}
}

@(test)
number_multiply_pins_binary64_edges_and_nan_selection :: proc(t: ^testing.T) {
	cases := [?][3]u64{
		{0, 0x8000000000000000, 0x8000000000000000},
		{0x8000000000000000, 0x8000000000000000, 0},
		{0x0000000000000001, 0x3fe0000000000000, 0},
		{0x0000000000000001, 0x4000000000000000, 0x0000000000000002},
		{0x7fefffffffffffff, 0x4000000000000000, 0x7ff0000000000000},
		{0x7ff0000000000000, 0, 0xfff8000000000000},
		{0x7ff8000000000042, 0xfff8000000000099, 0xfff8000000000099},
		{0xfff8000000000099, 0x7ff8000000000042, 0x7ff8000000000042},
		{0x7ff0000000000011, 0x3ff0000000000000, 0x7ff8000000000011},
	}
	for test_case in cases {
		expect_arithmetic_bits(t, number_multiply, test_case[0], test_case[1], test_case[2])
	}
}

@(test)
number_divide_pins_binary64_edges_and_nan_selection :: proc(t: ^testing.T) {
	cases := [?][3]u64{
		{0, 0x3ff0000000000000, 0},
		{0x8000000000000000, 0x3ff0000000000000, 0x8000000000000000},
		{0, 0xbff0000000000000, 0x8000000000000000},
		{0x0010000000000000, 0x4000000000000000, 0x0008000000000000},
		{0x0000000000000001, 0x4000000000000000, 0},
		{0x7fefffffffffffff, 0x3fe0000000000000, 0x7ff0000000000000},
		{0x3ff0000000000000, 0x7ff0000000000000, 0},
		{0x7ff0000000000000, 0x7ff0000000000000, 0xfff8000000000000},
		{0x7ff8000000000042, 0xfff8000000000099, 0x7ff8000000000042},
		{0x3ff0000000000000, 0xfff0000000000022, 0xfff8000000000022},
	}
	for test_case in cases {
		expect_arithmetic_bits(t, number_divide, test_case[0], test_case[1], test_case[2])
	}
}

@(test)
number_divide_and_modulo_classify_both_zero_signs :: proc(t: ^testing.T) {
	one := number_value(1)
	zeroes := [?]u64{0, 0x8000000000000000}
	zero_operations := [?]Arithmetic_Proc{number_divide, number_modulo}
	for zero_bits in zeroes {
		zero := number_value(transmute(f64)zero_bits)
		for operation in zero_operations {
			result, kind := operation(&one, &zero)
			testing.expect_value(t, kind, Number_Arithmetic_Result_Kind.Zero_Divisor)
			testing.expect_value(t, kind_of(&result), Kind.Invalid)
		}
	}
	zero_spellings := [?]string{"0.0", "-0.0"}
	for spelling in zero_spellings {
		zero, err := literal_number_value(spelling, context.allocator)
		for operation in zero_operations {
			result, kind := operation(&one, &zero)
			testing.expect_value(t, kind, Number_Arithmetic_Result_Kind.Zero_Divisor)
			testing.expect_value(t, kind_of(&result), Kind.Invalid)
		}
		destroy_value(&zero)
		destroy_constructor_error(&err)
	}
}

@(test)
number_modulo_matches_jq_integer_remainder_not_fmod :: proc(t: ^testing.T) {
	Case :: struct {
		left, right: f64,
		expected: u64,
		zero: bool,
	}
	cases := [?]Case{
		{-0.0, 1, 0, false},
		{7, 3, 0x3ff0000000000000, false},
		{-7, 3, 0xbff0000000000000, false},
		{7, -3, 0x3ff0000000000000, false},
		{-7, -3, 0xbff0000000000000, false},
		{7.5, 2.25, 0x3ff0000000000000, false},
		{-7.5, 2.25, 0xbff0000000000000, false},
		{1, 0.5, 0, true},
		{1, -0.5, 0, true},
		{9_223_372_036_854_775_808.0, 3, 0xc000000000000000, false},
		{9_223_372_036_854_777_856.0, 3, 0x3ff0000000000000, false},
		{math.inf_f64(1), 3, 0x3ff0000000000000, false},
		{math.inf_f64(-1), 3, 0xc000000000000000, false},
	}
	for test_case in cases {
		left := number_value(test_case.left)
		right := number_value(test_case.right)
		result, kind := number_modulo(&left, &right)
		if test_case.zero {
			testing.expect_value(t, kind, Number_Arithmetic_Result_Kind.Zero_Divisor)
			testing.expect_value(t, kind_of(&result), Kind.Invalid)
		} else {
			number, ok := number_value_get(&result)
			testing.expect_value(t, kind, Number_Arithmetic_Result_Kind.Success)
			testing.expect(t, ok)
			testing.expect_value(t, transmute(u64)number, test_case.expected)
		}
		destroy_value(&result)
	}
	positive_nan := number_value(transmute(f64)u64(0x7ff8000000000042))
	negative_nan := number_value(transmute(f64)u64(0xfff8000000000099))
	three := number_value(3)
	nan_pairs := [?][2]^Value{{&positive_nan, &three}, {&three, &negative_nan}}
	for pair in nan_pairs {
		result, kind := number_modulo(pair[0], pair[1])
		number, ok := number_value_get(&result)
		testing.expect_value(t, kind, Number_Arithmetic_Result_Kind.Success)
		testing.expect(t, ok && math.is_nan(number))
		testing.expect_value(t, transmute(u64)number, u64(0x7ff8000000000000))
		destroy_value(&result)
	}
}

@(test)
number_arithmetic_precision_literals_become_native :: proc(t: ^testing.T) {
	Case :: struct {
		operation: Arithmetic_Proc,
		left, right: string,
		expected: u64,
	}
	cases := [?]Case{
		{number_subtract, "9007199254740993", "1", 0x433fffffffffffff},
		{number_multiply, "9007199254740993", "1", 0x4340000000000000},
		{number_divide, "9007199254740993", "1", 0x4340000000000000},
		{number_subtract, "1.0000000000000001", "0", 0x3ff0000000000000},
		{number_multiply, "1.0000000000000002", "1", 0x3ff0000000000001},
		{number_divide, "2.2250738585072014e-308", "2", 0x0008000000000000},
		{number_multiply, "5e-324", "0.5", 0},
	}
	for test_case in cases {
		left, left_error := literal_number_value(test_case.left, context.allocator)
		right, right_error := literal_number_value(test_case.right, context.allocator)
		result, kind := test_case.operation(&left, &right)
		number, ok := number_value_get(&result)
		result_number_kind, kind_ok := number_kind(&result)
		testing.expect_value(t, kind, Number_Arithmetic_Result_Kind.Success)
		testing.expect(t, ok && kind_ok && result_number_kind == .Native)
		testing.expect_value(t, transmute(u64)number, test_case.expected)
		destroy_value(&result)
		destroy_value(&right)
		destroy_value(&left)
		destroy_constructor_error(&right_error)
		destroy_constructor_error(&left_error)
	}
}

@(test)
number_arithmetic_is_allocation_free_and_sources_remain_independent :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	left, left_error := literal_number_value("7.5", probe_allocator(&probe))
	right, right_error := literal_number_value("2.25", probe_allocator(&probe))
	baseline_allocations := probe.allocations
	probe.fail_after = baseline_allocations

	operations := [?]Arithmetic_Proc{
		number_subtract,
		number_multiply,
		number_divide,
		number_modulo,
	}
	for operation in operations {
		result, kind := operation(&left, &right)
		testing.expect_value(t, kind, Number_Arithmetic_Result_Kind.Success)
		testing.expect_value(t, probe.allocations, baseline_allocations)
		testing.expect_value(t, destroy_value(&result), runtime.Allocator_Error.None)
	}
	zero := number_value(-0.0)
	zero_operations := [?]Arithmetic_Proc{number_divide, number_modulo}
	for operation in zero_operations {
		result, kind := operation(&left, &zero)
		testing.expect_value(t, kind, Number_Arithmetic_Result_Kind.Zero_Divisor)
		testing.expect_value(t, probe.allocations, baseline_allocations)
		destroy_value(&result)
	}
	left_spelling, left_ok := literal_spelling_borrowed(&left)
	right_spelling, right_ok := literal_spelling_borrowed(&right)
	testing.expect(t, left_ok && left_spelling == "7.5")
	testing.expect(t, right_ok && right_spelling == "2.25")

	probe.free_failures_remaining = 1
	testing.expect(t, destroy_value(&left) != nil)
	left_after, left_after_ok := literal_spelling_borrowed(&left)
	testing.expect(t, left_after_ok && left_after == "7.5")
	repeated, repeated_kind := number_subtract(&left, &right)
	repeated_number, repeated_ok := number_value_get(&repeated)
	testing.expect_value(t, repeated_kind, Number_Arithmetic_Result_Kind.Success)
	testing.expect(t, repeated_ok && repeated_number == 5.25)
	testing.expect_value(t, probe.allocations, baseline_allocations)
	destroy_value(&repeated)
	testing.expect_value(t, destroy_value(&left), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&right), runtime.Allocator_Error.None)
	// The probe counts the injected failed free attempt as well as both
	// successful retirements.
	testing.expect_value(t, probe.frees, probe.allocations + 1)
	destroy_constructor_error(&right_error)
	destroy_constructor_error(&left_error)
}
