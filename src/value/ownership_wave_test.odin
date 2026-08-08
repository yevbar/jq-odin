package value

import "base:runtime"
import "core:testing"

@(private)
ownership_wave_put :: proc(
	t: ^testing.T,
	object: ^Value,
	key_text: string,
	item: ^Value,
	allocator: runtime.Allocator,
) {
	key, key_error := string_value(key_text, allocator)
	testing.expect_value(t, constructor_error_kind(&key_error), Error.None)
	duplicate, displaced, set_error := object_set_take(object, &key, item)
	testing.expect_value(t, object_error_kind(&set_error), Object_Error.None)
	testing.expect_value(t, kind_of(item), Kind.Invalid)
	testing.expect_value(t, destroy_value(&duplicate), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
}

@(test)
value_foundation_ownership_order_and_lexeme_boundary :: proc(t: ^testing.T) {
	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}

	// The input spelling is source-owned. Constructing a runtime number copies
	// it; changing the source buffer must not change the retained lexeme.
	source_bytes := [?]byte{'0', '0', '1', '.', '2', '3', '0', '0', 'e', '+', '0', '2'}
	source_spelling := transmute(string)source_bytes[:]
	literal, literal_error := literal_number_value(
		source_spelling,
		probe_allocator(&probe),
	)
	testing.expect_value(t, constructor_error_kind(&literal_error), Error.None)
	source_bytes[0] = '9'
	retained_spelling, spelling_ok := literal_spelling_borrowed(&literal)
	testing.expect(t, spelling_ok && retained_spelling == "001.2300e+02")

	items, array_error := array_value(probe_allocator(&probe))
	testing.expect_value(t, array_error_kind(&array_error), Array_Error.None)
	string_item, string_error := string_value("embedded\x00text", probe_allocator(&probe))
	testing.expect_value(t, constructor_error_kind(&string_error), Error.None)
	displaced, append_error := array_append_take(&items, &string_item)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)
	displaced, append_error = array_append_take(&items, &literal)
	testing.expect_value(t, array_error_kind(&append_error), Array_Error.None)
	testing.expect_value(t, destroy_value(&displaced), runtime.Allocator_Error.None)

	object, object_error := object_value(probe_allocator(&probe))
	testing.expect_value(t, object_error_kind(&object_error), Object_Error.None)
	first_item := null_value()
	ownership_wave_put(t, &object, "first", &first_item, probe_allocator(&probe))
	second_item := boolean_value(true)
	ownership_wave_put(t, &object, "second", &second_item, probe_allocator(&probe))
	third_item := take_value(&items)
	ownership_wave_put(t, &object, "third", &third_item, probe_allocator(&probe))
	testing.expect_value(t, kind_of(&items), Kind.Invalid)

	removed_key, removed_value, found, delete_error := object_delete_take(&object, "second")
	testing.expect_value(t, object_error_kind(&delete_error), Object_Error.None)
	testing.expect(t, found)
	testing.expect_value(t, destroy_value(&removed_key), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&removed_value), runtime.Allocator_Error.None)
	fourth_item := number_value(4)
	ownership_wave_put(t, &object, "fourth", &fourth_item, probe_allocator(&probe))

	iterator := object_iterator()
	expected_keys := [?]string{"first", "third", "fourth"}
	for expected in expected_keys {
		key, value, ok := object_iter_next_copy(&object, &iterator)
		testing.expect(t, ok)
		key_text, key_ok := string_borrowed(&key)
		testing.expect(t, key_ok && key_text == expected)
		testing.expect_value(t, destroy_value(&key), runtime.Allocator_Error.None)
		testing.expect_value(t, destroy_value(&value), runtime.Allocator_Error.None)
	}
	_, _, has_extra := object_iter_next_copy(&object, &iterator)
	testing.expect(t, !has_extra)

	// clone shares owned payloads; take leaves an inert source; destroying the
	// final owner must retire every allocation exactly once.
	clone := clone_value(&object)
	moved := take_value(&clone)
	testing.expect_value(t, kind_of(&clone), Kind.Invalid)
	testing.expect_value(t, destroy_value(&object), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&moved), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&literal), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&items), runtime.Allocator_Error.None)
	testing.expect_value(t, destroy_value(&string_item), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
	testing.expect_value(t, probe.allocations, probe.frees)
	testing.expect(t, !probe.wrong_free_size)
}
