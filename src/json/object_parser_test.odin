package json

import "base:runtime"
import "core:testing"
import "jq:value"

@(private)
expect_object_error_at :: proc(
	t: ^testing.T,
	input: string,
	kind: Scalar_Parse_Error_Kind,
	detection, cause: int,
) {
	parsed, err := parse_value(input, context.allocator)
	defer value.destroy_value(&parsed)
	defer destroy_scalar_parse_error(&err)
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, kind)
	testing.expect_value(t, err.detection_offset, detection)
	testing.expect(t, err.has_cause_offset)
	testing.expect_value(t, err.cause_offset, cause)
}

@(private)
object_member :: proc(t: ^testing.T, object: ^value.Value, key: string) -> value.Value {
	member, ok := value.object_get_copy(object, key)
	testing.expect(t, ok)
	return member
}

@(private)
find_object_commit_allocation_failure :: proc(
	t: ^testing.T,
	input: string,
	punctuation_offset: int,
) -> int {
	// The initial object has eight slots, so the ninth unique member performs
	// the bounded growth allocation whose location is controlled by the comma
	// or closing brace in the pinned parser transition.
	for fail_after in 0..<64 {
		probe := allocator_probe{backing = context.allocator, fail_after = fail_after}
		parsed, err := parse_value(input, probe_allocator(&probe))
		matched := err.kind == .Allocation_Failure &&
			err.detection_offset == punctuation_offset &&
			err.has_cause_offset && err.cause_offset == punctuation_offset
		if value.kind_of(&parsed) != .Invalid {
			testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
		}
		testing.expect_value(t, destroy_scalar_parse_error(&err), runtime.Allocator_Error.None)
		testing.expect_value(t, probe.live, 0)
		if matched do return fail_after
	}
	testing.expect(t, false, "bounded probe did not reach punctuation-time object insertion")
	return -1
}

@(test)
empty_nested_mixed_and_duplicate_objects :: proc(t: ^testing.T) {
	empty, empty_error := parse_value(" \t{}\r\n", context.allocator)
	testing.expect_value(t, empty_error.kind, Scalar_Parse_Error_Kind.None)
	length, ok := value.object_length(&empty)
	testing.expect(t, ok && length == 0)
	testing.expect_value(t, value.destroy_value(&empty), runtime.Allocator_Error.None)

	parsed, err := parse_value(
		`{"z":0,"a":[1,{"x":2}],"z":3,"m":{"n":null}}`,
		context.allocator,
	)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Object)
	length, ok = value.object_length(&parsed)
	testing.expect(t, ok && length == 3)
	z := object_member(t, &parsed, "z")
	z_number, z_ok := value.number_value_get(&z)
	testing.expect(t, z_ok && z_number == 3)
	testing.expect_value(t, value.destroy_value(&z), runtime.Allocator_Error.None)

	iterator := value.object_iterator()
	expected := [3]string{"z", "a", "m"}
	for expected_key in expected {
		key, member, found := value.object_iter_next_copy(&parsed, &iterator)
		testing.expect(t, found)
		key_bytes, key_ok := value.string_borrowed(&key)
		testing.expect(t, key_ok && key_bytes == expected_key)
		testing.expect_value(t, value.destroy_value(&key), runtime.Allocator_Error.None)
		testing.expect_value(t, value.destroy_value(&member), runtime.Allocator_Error.None)
	}
	testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
}

@(test)
object_members_commit_only_at_comma_or_close :: proc(t: ^testing.T) {
	close_input := `{"a":0,"b":1,"c":2,"d":3,"e":4,"f":5,"g":6,"h":7,"i":8}`
	close_offset := len(close_input) - 1
	close_failure := find_object_commit_allocation_failure(t, close_input, close_offset)
	testing.expect(t, close_failure >= 0)

	comma_input := `{"a":0,"b":1,"c":2,"d":3,"e":4,"f":5,"g":6,"h":7,"i":8,"j":9}`
	comma_offset := 54
	testing.expect_value(t, comma_input[comma_offset], byte(','))
	comma_failure := find_object_commit_allocation_failure(t, comma_input, comma_offset)
	testing.expect_value(t, comma_failure, close_failure)

	// With the same allocator position that fails a valid comma commit, jq's
	// separator conflict is resolved before object insertion. `true` adds no
	// allocation that could obscure whether the insertion was attempted.
	missing_separator := `{"a":0,"b":1,"c":2,"d":3,"e":4,"f":5,"g":6,"h":7,"i":8 true}`
	probe := allocator_probe{backing = context.allocator, fail_after = comma_failure}
	parsed, err := parse_value(missing_separator, probe_allocator(&probe))
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Expected_Separator)
	true_offset := len(missing_separator) - 5
	testing.expect_value(t, err.detection_offset, len(missing_separator) - 1)
	testing.expect(t, err.has_cause_offset)
	testing.expect_value(t, err.cause_offset, true_offset)
	testing.expect_value(t, probe.allocations, comma_failure)
	testing.expect_value(t, destroy_scalar_parse_error(&err), runtime.Allocator_Error.None)
	testing.expect_value(t, probe.live, 0)
}

@(test)
duplicate_replacement_preserves_order_across_punctuation_commits :: proc(t: ^testing.T) {
	parsed, err := parse_value(`{"a":1,"b":2,"a":3,"b":4}`, context.allocator)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	defer value.destroy_value(&parsed)

	iterator := value.object_iterator()
	expected_keys := [2]string{"a", "b"}
	expected_values := [2]f64{3, 4}
	for expected_key, index in expected_keys {
		key, member, found := value.object_iter_next_copy(&parsed, &iterator)
		testing.expect(t, found)
		key_bytes, key_ok := value.string_borrowed(&key)
		number, number_ok := value.number_value_get(&member)
		testing.expect(t, key_ok && key_bytes == expected_key)
		testing.expect(t, number_ok && number == expected_values[index])
		testing.expect_value(t, value.destroy_value(&key), runtime.Allocator_Error.None)
		testing.expect_value(t, value.destroy_value(&member), runtime.Allocator_Error.None)
	}
	_, _, found := value.object_iter_next_copy(&parsed, &iterator)
	testing.expect(t, !found)
}

@(test)
failed_punctuation_commit_retains_owners_for_free_retry :: proc(t: ^testing.T) {
	input := `{"a":0,"b":1,"c":2,"d":3,"e":4,"f":5,"g":6,"h":7,"i":8}`
	punctuation_offset := len(input) - 1
	fail_after := find_object_commit_allocation_failure(t, input, punctuation_offset)
	probe := allocator_probe{
		backing = context.allocator,
		fail_after = fail_after,
		free_failures_remaining = 2,
	}
	parsed, err := parse_value(input, probe_allocator(&probe))
	testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	testing.expect_value(t, err.cause_kind, Scalar_Parse_Error_Kind.Allocation_Failure)
	testing.expect_value(t, err.detection_offset, punctuation_offset)
	testing.expect(t, err.has_cause_offset)
	testing.expect_value(t, err.cause_offset, punctuation_offset)
	testing.expect(t, probe.live > 0)

	cleanup_result, retries := retry_scalar_parse_error_cleanup(&err)
	testing.expect_value(t, cleanup_result, scalar_parse_cleanup_retry_result.Terminal)
	testing.expect(t, retries > 0 && retries <= SCALAR_PARSE_CLEANUP_RETRY_LIMIT)
	testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, probe.live, 0)
}

@(test)
object_errors_preserve_jq_transition_precedence :: proc(t: ^testing.T) {
	expect_object_error_at(t, `{`, .Unfinished_Object, 0, 1)
	expect_object_error_at(t, `{"a"}`, .Object_Key_Value_Pairs_Required, 4, 4)
	expect_object_error_at(t, `{"a":}`, .Unmatched_Object_Closer, 5, 5)
	expect_object_error_at(t, `{"a":,}`, .Expected_Value_Before_Separator, 5, 5)
	expect_object_error_at(t, `{"a":1 "b":2}`, .Expected_Separator, 9, 7)
	expect_object_error_at(t, `{"a":1,}`, .Expected_Object_Member, 7, 7)
	expect_object_error_at(t, `{1:2}`, .Object_Keys_Must_Be_Strings, 2, 2)
	expect_object_error_at(t, `{true:2}`, .Object_Keys_Must_Be_Strings, 5, 5)
	expect_object_error_at(t, `{[]:2}`, .Object_Keys_Must_Be_Strings, 3, 3)
	expect_object_error_at(t, `{"a":1]`, .Unmatched_Array_Closer, 6, 6)
	expect_object_error_at(t, `{]`, .Unmatched_Array_Closer, 1, 1)
	expect_object_error_at(t, `[{"a":1}`, .Unfinished_Array, 7, 8)
	expect_object_error_at(t, `{"a":{"b":1]`, .Unmatched_Array_Closer, 11, 11)
	expect_object_error_at(t, `{} {"x":}`, .Unmatched_Object_Closer, 8, 8)
}

@(private)
nested_object_input :: proc(depth: int) -> []byte {
	bytes := make([]byte, depth * 6 + 4)
	at := 0
	for _ in 0..<depth {
		copy(bytes[at:at + 5], `{"x":`)
		at += 5
	}
	copy(bytes[at:at + 4], "null")
	at += 4
	for _ in 0..<depth {
		bytes[at] = '}'
		at += 1
	}
	return bytes
}

@(private)
nested_mixed_input :: proc(depth: int) -> []byte {
	object_count := depth / 2
	array_count := depth - object_count
	bytes := make([]byte, object_count * 6 + array_count * 2 + 4)
	at := 0
	for i in 0..<depth {
		if i & 1 == 0 {
			bytes[at] = '['
			at += 1
		} else {
			copy(bytes[at:at + 5], `{"x":`)
			at += 5
		}
	}
	copy(bytes[at:at + 4], "null")
	at += 4
	for i := depth - 1; i >= 0; i -= 1 {
		if i & 1 == 0 do bytes[at] = ']'
		else do bytes[at] = '}'
		at += 1
	}
	return bytes
}

@(private)
nested_weighted_mixed_input :: proc(array_count, object_count: int) -> []byte {
	bytes := make([]byte, array_count * 2 + object_count * 6 + 4)
	at := 0
	for _ in 0..<array_count {
		bytes[at] = '['
		at += 1
	}
	for _ in 0..<object_count {
		copy(bytes[at:at + 5], `{"x":`)
		at += 5
	}
	copy(bytes[at:at + 4], "null")
	at += 4
	for _ in 0..<object_count {
		bytes[at] = '}'
		at += 1
	}
	for _ in 0..<array_count {
		bytes[at] = ']'
		at += 1
	}
	return bytes
}

@(test)
public_parser_enforces_keyed_object_and_mixed_entry_boundaries :: proc(t: ^testing.T) {
	accepted_objects := nested_object_input(MAX_PARSING_DEPTH / 2)
	object_value, object_error := parse_value(transmute(string)accepted_objects, context.allocator)
	delete(accepted_objects)
	testing.expect_value(t, object_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&object_value), value.Kind.Object)
	testing.expect_value(t, value.destroy_value(&object_value), runtime.Allocator_Error.None)

	rejected_objects := nested_object_input(MAX_PARSING_DEPTH / 2 + 1)
	rejected_object, rejected_object_error := parse_value(
		transmute(string)rejected_objects,
		context.allocator,
	)
	delete(rejected_objects)
	testing.expect_value(t, value.kind_of(&rejected_object), value.Kind.Invalid)
	testing.expect_value(t, rejected_object_error.kind, Scalar_Parse_Error_Kind.Depth_Limit)
	testing.expect_value(t, rejected_object_error.detection_offset, 25_000)
	testing.expect(t, rejected_object_error.has_cause_offset)
	testing.expect_value(t, rejected_object_error.cause_offset, 25_000)
	testing.expect_value(t, destroy_scalar_parse_error(&rejected_object_error), runtime.Allocator_Error.None)

	// The final object opener moves the live count from 9,999 to 10,000.
	// jq then accepts its colon push to 10,001 because only openers are guarded.
	accepted_mixed := nested_weighted_mixed_input(9_999, 1)
	mixed_value, mixed_error := parse_value(transmute(string)accepted_mixed, context.allocator)
	delete(accepted_mixed)
	testing.expect_value(t, mixed_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&mixed_value), value.Kind.Array)
	testing.expect_value(t, value.destroy_value(&mixed_value), runtime.Allocator_Error.None)
}

@(private)
nested_array_payload :: proc(depth: int, payload: string) -> []byte {
	bytes := make([]byte, depth * 2 + len(payload))
	for i in 0..<depth do bytes[i] = '['
	copy(bytes[depth:depth + len(payload)], payload)
	for i in 0..<depth do bytes[depth + len(payload) + i] = ']'
	return bytes
}

@(test)
public_parser_releases_object_key_and_container_entries :: proc(t: ^testing.T) {
	// Each comma transfers and releases the pending key, so both colons may
	// reach 10,000 while nested beneath 9,998 arrays.
	comma_release := nested_array_payload(9_998, `{"a":null,"b":null}`)
	comma_value, comma_error := parse_value(transmute(string)comma_release, context.allocator)
	delete(comma_release)
	testing.expect_value(t, comma_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&comma_value), value.Kind.Array)
	testing.expect_value(t, value.destroy_value(&comma_value), runtime.Allocator_Error.None)

	// Closing the object releases its pending key and container before the
	// sibling opener is processed in the surrounding array.
	close_release := nested_array_payload(9_998, `{"a":null},[]`)
	close_value, close_error := parse_value(transmute(string)close_release, context.allocator)
	delete(close_release)
	testing.expect_value(t, close_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, value.kind_of(&close_value), value.Kind.Array)
	testing.expect_value(t, value.destroy_value(&close_value), runtime.Allocator_Error.None)
}

@(test)
object_allocation_failures_and_cleanup_retries_are_atomic :: proc(t: ^testing.T) {
	input := `{"a":[1,{"b":"text"}],"c":2,"d":3,"e":4,"f":5,"g":6,"h":7,"i":8}`
	for fail_after in 0..<40 {
		probe := allocator_probe{backing = context.allocator, fail_after = fail_after}
		parsed, err := parse_value(input, probe_allocator(&probe))
		if err.kind == .None {
			testing.expect_value(t, value.kind_of(&parsed), value.Kind.Object)
			testing.expect_value(t, value.destroy_value(&parsed), runtime.Allocator_Error.None)
		} else {
			testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
			if err.kind == .Scratch_Cleanup_Failure {
				cleanup_result, _ := retry_scalar_parse_error_cleanup(&err)
				testing.expect_value(
					t,
					cleanup_result,
					scalar_parse_cleanup_retry_result.Terminal,
				)
				testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
			}
		}
		testing.expect_value(t, probe.live, 0)
	}

	short_cases := [2]bool{false, true}
	for short in short_cases {
		probe := allocator_probe{
			backing = context.allocator,
			fail_after = max(int),
			nil_success = !short,
			short_success = short,
			free_failures_remaining = 2,
		}
		parsed, err := parse_value("{}", probe_allocator(&probe))
		testing.expect_value(t, value.kind_of(&parsed), value.Kind.Invalid)
		if short {
			testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
			cleanup_result, _ := retry_scalar_parse_error_cleanup(&err)
			testing.expect_value(
				t,
				cleanup_result,
				scalar_parse_cleanup_retry_result.Terminal,
			)
			testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.None)
		} else {
			testing.expect_value(t, err.kind, Scalar_Parse_Error_Kind.Allocation_Failure)
		}
		testing.expect_value(t, probe.live, 0)
	}

	retry_probe := allocator_probe{
		backing = context.allocator,
		fail_after = max(int),
		free_failures_remaining = 2,
	}
	retry_result, retry_error := parse_value(
		`{"a":"first","a":"second"}`,
		probe_allocator(&retry_probe),
	)
	testing.expect_value(t, value.kind_of(&retry_result), value.Kind.Invalid)
	testing.expect_value(t, retry_error.kind, Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure)
	cleanup_result, _ := retry_scalar_parse_error_cleanup(&retry_error)
	testing.expect_value(t, cleanup_result, scalar_parse_cleanup_retry_result.Terminal)
	testing.expect_value(t, retry_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, retry_probe.live, 0)
}

@(test)
cleanup_retry_control_rejects_ordinary_errors_and_enforces_its_bound :: proc(t: ^testing.T) {
	ordinary_error := Scalar_Parse_Error{kind = .Allocation_Failure}
	ordinary_result, ordinary_retries := retry_scalar_parse_error_cleanup(&ordinary_error)
	testing.expect_value(
		t,
		ordinary_result,
		scalar_parse_cleanup_retry_result.Non_Retryable,
	)
	testing.expect_value(t, ordinary_retries, 0)
	testing.expect_value(t, ordinary_error.kind, Scalar_Parse_Error_Kind.Allocation_Failure)

	probe := allocator_probe{backing = context.allocator, fail_after = max(int)}
	allocator := probe_allocator(&probe)
	scratch, allocation_error := runtime.mem_alloc(8, 1, allocator)
	testing.expect_value(t, allocation_error, runtime.Allocator_Error.None)
	testing.expect_value(t, len(scratch), 8)
	testing.expect_value(t, probe.live, 1)
	probe.free_failures_remaining = SCALAR_PARSE_CLEANUP_RETRY_LIMIT + 1
	retryable_error := Scalar_Parse_Error{
		kind = .Scratch_Cleanup_Failure,
		cleanup_scratch = scratch,
		cleanup_allocator = allocator,
	}
	retry_result, retries := retry_scalar_parse_error_cleanup(&retryable_error)
	testing.expect_value(t, retry_result, scalar_parse_cleanup_retry_result.Exhausted)
	testing.expect_value(t, retries, SCALAR_PARSE_CLEANUP_RETRY_LIMIT)
	testing.expect_value(t, probe.frees, SCALAR_PARSE_CLEANUP_RETRY_LIMIT)
	testing.expect_value(t, probe.live, 1)
	testing.expect_value(
		t,
		retryable_error.kind,
		Scalar_Parse_Error_Kind.Scratch_Cleanup_Failure,
	)

	probe.free_failures_remaining = 0
	testing.expect_value(
		t,
		destroy_scalar_parse_error(&retryable_error),
		runtime.Allocator_Error.None,
	)
	testing.expect_value(t, retryable_error.kind, Scalar_Parse_Error_Kind.None)
	testing.expect_value(t, probe.live, 0)
}
