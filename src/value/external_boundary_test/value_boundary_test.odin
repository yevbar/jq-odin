package value_external_boundary_test

import "base:runtime"
import "core:testing"
import value "jq:value"

VALUE_SIZE :: 56
VALUE_ALIGNMENT :: 8

@(test)
external_package_uses_only_the_value_lifecycle_boundary :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(value.Value), VALUE_SIZE)
	testing.expect_value(t, align_of(value.Value), VALUE_ALIGNMENT)

	inert: value.Value
	testing.expect_value(t, value.kind_of(&inert), value.Kind.Invalid)
	testing.expect_value(t, value.destroy_value(&inert), runtime.Allocator_Error.None)

	left := value.number_value(20)
	right := value.number_value(22)
	clone := value.clone_value(&left)
	moved := value.take_value(&clone)
	testing.expect_value(t, value.kind_of(&clone), value.Kind.Invalid)
	testing.expect_value(t, value.kind_of(&moved), value.Kind.Number)

	result, add_error := value.value_add(&moved, &right, context.allocator)
	testing.expect_value(t, value.value_add_error_kind(&add_error), value.Value_Add_Error_Kind.None)
	result_number, result_ok := value.number_value_get(&result)
	testing.expect(t, result_ok && result_number == 42)

	testing.expect_value(t, value.destroy_value_add_error(&add_error), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&left), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&right), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&clone), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&moved), runtime.Allocator_Error.None)
	testing.expect_value(t, value.destroy_value(&result), runtime.Allocator_Error.None)
}
