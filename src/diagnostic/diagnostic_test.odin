package diagnostic

import "base:runtime"
import "core:mem"
import "core:testing"

@(private="package")
Size_Checking_Allocator :: struct {
	backing:       runtime.Allocator,
	tracker:       ^mem.Tracking_Allocator,
	size_mismatch: bool,
}

@(private="package")
size_checking_allocator :: proc(data: ^Size_Checking_Allocator) -> runtime.Allocator {
	return runtime.Allocator{
		procedure = size_checking_allocator_proc,
		data = data,
	}
}

@(private="package")
size_checking_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	data := (^Size_Checking_Allocator)(allocator_data)
	if old_memory != nil &&
	   (mode == .Free || mode == .Resize || mode == .Resize_Non_Zeroed) {
		entry, found := data.tracker.allocation_map[old_memory]
		if !found || entry.size != old_size {
			data.size_mismatch = true
		}
	}
	return data.backing.procedure(
		data.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(private="package")
Failing_Allocator :: struct {
	backing:       runtime.Allocator,
	fail_at:       int,
	request_count: int,
}

@(private="package")
failing_allocator :: proc(data: ^Failing_Allocator) -> runtime.Allocator {
	return runtime.Allocator{
		procedure = failing_allocator_proc,
		data = data,
	}
}

@(private="package")
failing_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
	data := (^Failing_Allocator)(allocator_data)
	if mode == .Alloc ||
	   mode == .Alloc_Non_Zeroed ||
	   mode == .Resize ||
	   mode == .Resize_Non_Zeroed {
		data.request_count += 1
		if data.fail_at > 0 && data.request_count == data.fail_at {
			return nil, .Out_Of_Memory
		}
	}
	return data.backing.procedure(
		data.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
}

@(test)
test_locate_table :: proc(t: ^testing.T) {
	Case :: struct {
		name:         string,
		text:         string,
		start:        int,
		end:          int,
		line:         int,
		byte_column:  int,
		source_line:  string,
		line_start:   int,
	}
	cases := [?]Case{
		{"first line", "first\nmiddle\nlast", 0, 1, 1, 1, "first", 0},
		{"middle line", "first\nmiddle\nlast", 7, 8, 2, 2, "middle", 6},
		{"last line", "first\nmiddle\nlast", 13, 17, 3, 1, "last", 13},
		{"final nonempty line before trailing newline", "first\nlast\n", 6, 10, 2, 1, "last", 6},
		{"EOF without trailing newline", "last", 4, 4, 1, 5, "last", 0},
		{"EOF after trailing newline", "first\nlast\n", 11, 11, 3, 1, "", 11},
		{"empty line", "one\n\nthree", 4, 4, 2, 1, "", 4},
		{"empty source", "", 0, 0, 1, 1, "", 0},
		{"UTF-8 byte column", "é$x", 2, 4, 1, 3, "é$x", 0},
	}

	for test_case in cases {
		source := borrow_source(test_case.name, test_case.text)
		span, span_ok := make_span(source, test_case.start, test_case.end)
		testing.expect(t, span_ok)

		location, locate_ok := locate(source, span)
		testing.expect(t, locate_ok)
		testing.expect_value(t, location.line, test_case.line)
		testing.expect_value(t, location.byte_column, test_case.byte_column)
		testing.expect_value(t, location.source_line, test_case.source_line)
		testing.expect_value(t, location.line_start, test_case.line_start)
	}
}

@(test)
test_make_span_rejects_invalid_ranges :: proc(t: ^testing.T) {
	source := borrow_source("<test>", "abc")
	invalid := [][2]int{
		{-1, 0},
		{2, 1},
		{0, 4},
		{4, 4},
	}

	for offsets in invalid {
		_, ok := make_span(source, offsets[0], offsets[1])
		testing.expect(t, !ok)
	}

	_, zero_width_ok := make_span(source, 3, 3)
	testing.expect(t, zero_width_ok)
}

@(test)
test_span_offsets_validate_source :: proc(t: ^testing.T) {
	source := borrow_source("<test>", "abc")
	valid, made := make_span(source, 1, 3)
	testing.expect(t, made)
	start, end, offsets_ok := span_offsets(source, valid)
	testing.expect(t, offsets_ok)
	testing.expect_value(t, start, 1)
	testing.expect_value(t, end, 3)

	fabricated := [?]Span{
		{start = -1, end = 0},
		{start = 2, end = 1},
		{start = 0, end = 4},
	}
	for span in fabricated {
		invalid_start, invalid_end, invalid_ok := span_offsets(source, span)
		testing.expect(t, !invalid_ok)
		testing.expect_value(t, invalid_start, 0)
		testing.expect_value(t, invalid_end, 0)
		_, locate_ok := locate(source, span)
		testing.expect(t, !locate_ok)
	}
}

@(test)
test_span_validation_accepts_copied_in_range_offsets :: proc(t: ^testing.T) {
	source := borrow_source("<test>", "abc")
	span, made := make_span(source, 1, 2)
	testing.expect(t, made)

	re_offset_span := span
	re_offset_span.start = 0
	re_offset_span.end = 3

	start, end, offsets_ok := span_offsets(source, re_offset_span)
	testing.expect(t, offsets_ok)
	testing.expect_value(t, start, 0)
	testing.expect_value(t, end, 3)

	location, locate_ok := locate(source, re_offset_span)
	testing.expect(t, locate_ok)
	testing.expect_value(t, location.line, 1)
	testing.expect_value(t, location.byte_column, 1)

	rendered, render_ok := render_error(
		source,
		re_offset_span,
		"problem",
		context.allocator,
	)
	testing.expect(t, render_ok)
	testing.expect_value(
		t,
		rendered,
		"jq: error: problem at <test>, line 1, column 1:\n    abc\n    ^^^",
	)
	delete(rendered)
}

@(test)
test_span_rejects_same_length_different_source :: proc(t: ^testing.T) {
	original := borrow_source("a", "a\nb")
	span, made := make_span(original, 2, 3)
	testing.expect(t, made)
	different := borrow_source("b", "xyz")

	start, end, offsets_ok := span_offsets(different, span)
	testing.expect(t, !offsets_ok)
	testing.expect_value(t, start, 0)
	testing.expect_value(t, end, 0)

	location, locate_ok := locate(different, span)
	testing.expect(t, !locate_ok)
	testing.expect_value(t, location, Location{})

	failer := Failing_Allocator{backing = context.allocator}
	rendered, render_ok := render_error(
		different,
		span,
		"problem",
		failing_allocator(&failer),
	)
	testing.expect(t, !render_ok)
	testing.expect_value(t, rendered, "")
	testing.expect_value(t, failer.request_count, 0)
}

@(test)
test_source_public_field_contract_and_structural_limit :: proc(t: ^testing.T) {
	source := borrow_source("first", "a\nb")
	span, made := make_span(source, 2, 3)
	testing.expect(t, made)

	copied_source := source
	start, end, copied_ok := span_offsets(copied_source, span)
	testing.expect(t, copied_ok)
	testing.expect_value(t, start, 2)
	testing.expect_value(t, end, 3)

	equal_but_distinct := borrow_source(source_name(source), source_bytes(source))
	_, _, distinct_ok := span_offsets(equal_but_distinct, span)
	testing.expect(t, !distinct_ok)

	stale_view := source
	stale_view.bytes = "x\ny"
	_, _, stale_ok := span_offsets(stale_view, span)
	testing.expect(t, !stale_ok)

	inconsistent_metadata := source
	inconsistent_metadata.borrowed_bytes_len = len(source_bytes(source)) + 1
	_, _, inconsistent_ok := span_offsets(inconsistent_metadata, span)
	testing.expect(t, !inconsistent_ok)

	// Odin cannot make Source fields opaque. This rewrite is outside the valid
	// API contract, but structural validation cannot distinguish it from an
	// unchanged copy when all public view metadata is replaced consistently.
	rewritten := source
	rewritten.name = "other"
	rewritten.bytes = "x\ny"
	rewritten.borrowed_name = rawptr(raw_data(rewritten.name))
	rewritten.borrowed_name_len = len(rewritten.name)
	rewritten.borrowed_bytes = rawptr(raw_data(rewritten.bytes))
	rewritten.borrowed_bytes_len = len(rewritten.bytes)

	rewritten_start, rewritten_end, rewritten_ok := span_offsets(rewritten, span)
	testing.expect(t, rewritten_ok)
	testing.expect_value(t, rewritten_start, 2)
	testing.expect_value(t, rewritten_end, 3)

	location, locate_ok := locate(rewritten, span)
	testing.expect(t, locate_ok)
	testing.expect_value(t, location.line, 2)
	testing.expect_value(t, location.byte_column, 1)
	testing.expect_value(t, location.source_line, "y")
}

@(test)
test_render_highlight_table :: proc(t: ^testing.T) {
	Case :: struct {
		name:      string,
		text:      string,
		start:     int,
		end:       int,
		expected:  string,
	}
	cases := [?]Case{
		{
			"zero width",
			"abc",
			1,
			1,
			"jq: error: problem at zero width, line 1, column 2:\n    abc\n     ^",
		},
		{
			"multi-line span clamps to first line",
			"abc\ndef",
			1,
			6,
			"jq: error: problem at multi-line span clamps to first line, line 1, column 2:\n    abc\n     ^^",
		},
		{
			"UTF-8 byte column and multi-line clamp",
			"éxy\nnext",
			2,
			7,
			"jq: error: problem at UTF-8 byte column and multi-line clamp, line 1, column 3:\n    éxy\n      ^^",
		},
		{
			"CRLF preserves carriage return",
			"ab\r\ncd",
			2,
			3,
			"jq: error: problem at CRLF preserves carriage return, line 1, column 3:\n    ab\r\n      ^",
		},
		{
			"final nonempty line before trailing newline",
			"first\nlast\n",
			6,
			10,
			"jq: error: problem at final nonempty line before trailing newline, line 2, column 1:\n    last\n    ^^^^",
		},
		{
			"end of empty line",
			"abc\n\nlast",
			4,
			4,
			"jq: error: problem at end of empty line, line 2, column 1:\n    \n    ^",
		},
		{
			"end of source without trailing newline",
			"last",
			4,
			4,
			"jq: error: problem at end of source without trailing newline, line 1, column 5:\n    last\n        ^",
		},
		{
			"end of source after trailing newline",
			"last\n",
			5,
			5,
			"jq: error: problem at end of source after trailing newline, line 2, column 1:\n    \n    ^",
		},
		{
			"end of source after repeated final newlines",
			"last\n\n",
			6,
			6,
			"jq: error: problem at end of source after repeated final newlines, line 3, column 1:\n    \n    ^",
		},
	}

	for test_case in cases {
		source := borrow_source(test_case.name, test_case.text)
		span, span_ok := make_span(source, test_case.start, test_case.end)
		testing.expect(t, span_ok)
		rendered, render_ok := render_error(source, span, "problem", context.allocator)
		testing.expect(t, render_ok)
		testing.expect_value(t, rendered, test_case.expected)
		delete(rendered)
	}
}

@(test)
test_render_length_delimited_inputs :: proc(t: ^testing.T) {
	Case :: struct {
		name:      string,
		text:      string,
		start:     int,
		end:       int,
		message:   string,
		expected:  string,
	}
	cases := [?]Case{
		{
			"name\x00suffix",
			"abc",
			1,
			2,
			"problem",
			"jq: error: problem at name\x00suffix, line 1, column 2:\n    abc\n     ^",
		},
		{
			"<source-nul>",
			"a\x00bc",
			1,
			3,
			"problem",
			"jq: error: problem at <source-nul>, line 1, column 2:\n    a\x00bc\n     ^^",
		},
		{
			"<message-nul>",
			"abc",
			0,
			1,
			"problem\x00suffix",
			"jq: error: problem\x00suffix at <message-nul>, line 1, column 1:\n    abc\n    ^",
		},
		{
			"<message-newline>",
			"abc",
			0,
			1,
			"first line\nsecond line",
			"jq: error: first line\nsecond line at <message-newline>, line 1, column 1:\n    abc\n    ^",
		},
	}

	for test_case in cases {
		source := borrow_source(test_case.name, test_case.text)
		span, span_ok := make_span(source, test_case.start, test_case.end)
		testing.expect(t, span_ok)
		rendered, render_ok := render_error(
			source,
			span,
			test_case.message,
			context.allocator,
		)
		testing.expect(t, render_ok)
		testing.expect_value(t, rendered, test_case.expected)
		delete(rendered)
	}
}

@(test)
test_exact_fixture_visible_formatting :: proc(t: ^testing.T) {
	Case :: struct {
		text:      string,
		start:     int,
		end:       int,
		message:   string,
		expected:  string,
	}
	cases := [?]Case{
		{
			". as [] | null",
			6,
			7,
			"syntax error, unexpected ']', expecting BINDING or '[' or '{'",
			"jq: error: syntax error, unexpected ']', expecting BINDING or '[' or '{' at <top-level>, line 1, column 7:\n    . as [] | null\n          ^",
		},
		{
			". as $foo | [$foo, $bar]",
			19,
			23,
			"$bar is not defined",
			"jq: error: $bar is not defined at <top-level>, line 1, column 20:\n    . as $foo | [$foo, $bar]\n                       ^^^^",
		},
		{
			". as {} | null",
			6,
			7,
			"syntax error, unexpected '}'",
			"jq: error: syntax error, unexpected '}' at <top-level>, line 1, column 7:\n    . as {} | null\n          ^",
		},
		{
			"{(0):1}",
			2,
			3,
			"Cannot use number (0) as object key",
			"jq: error: Cannot use number (0) as object key at <top-level>, line 1, column 3:\n    {(0):1}\n      ^",
		},
		{
			"{1+2:3}",
			1,
			4,
			"May need parentheses around object key expression",
			"jq: error: May need parentheses around object key expression at <top-level>, line 1, column 2:\n    {1+2:3}\n     ^^^",
		},
		{
			"{non_const:., (0):1}",
			15,
			16,
			"Cannot use number (0) as object key",
			"jq: error: Cannot use number (0) as object key at <top-level>, line 1, column 16:\n    {non_const:., (0):1}\n                   ^",
		},
		{
			". as {(true):$foo} | $foo",
			7,
			11,
			"Cannot use boolean (true) as object key",
			"jq: error: Cannot use boolean (true) as object key at <top-level>, line 1, column 8:\n    . as {(true):$foo} | $foo\n           ^^^^",
		},
		{
			". as $foo | break $foo",
			12,
			22,
			"$*label-foo is not defined",
			"jq: error: $*label-foo is not defined at <top-level>, line 1, column 13:\n    . as $foo | break $foo\n                ^^^^^^^^^^",
		},
		{
			"module (.+1); 0",
			7,
			12,
			"Module metadata must be constant",
			"jq: error: Module metadata must be constant at <top-level>, line 1, column 8:\n    module (.+1); 0\n           ^^^^^",
		},
		{
			"module []; 0",
			7,
			9,
			"Module metadata must be an object",
			"jq: error: Module metadata must be an object at <top-level>, line 1, column 8:\n    module []; 0\n           ^^",
		},
		{
			"include \"a\" (.+1); 0",
			12,
			17,
			"Module metadata must be constant",
			"jq: error: Module metadata must be constant at <top-level>, line 1, column 13:\n    include \"a\" (.+1); 0\n                ^^^^^",
		},
		{
			"include \"a\" []; 0",
			12,
			14,
			"Module metadata must be an object",
			"jq: error: Module metadata must be an object at <top-level>, line 1, column 13:\n    include \"a\" []; 0\n                ^^",
		},
		{
			"%::wat",
			0,
			1,
			"syntax error, unexpected '%', expecting end of file",
			"jq: error: syntax error, unexpected '%', expecting end of file at <top-level>, line 1, column 1:\n    %::wat\n    ^",
		},
		{
			"include \"\\ \"; 0",
			9,
			11,
			"Invalid escape at line 1, column 4 (while parsing '\"\\ \"')",
			"jq: error: Invalid escape at line 1, column 4 (while parsing '\"\\ \"') at <top-level>, line 1, column 10:\n    include \"\\ \"; 0\n             ^^",
		},
	}

	for test_case in cases {
		source := borrow_source("<top-level>", test_case.text)
		span, span_ok := make_span(source, test_case.start, test_case.end)
		testing.expect(t, span_ok)
		rendered, render_ok := render_error(source, span, test_case.message, context.allocator)
		testing.expect(t, render_ok)
		testing.expect_value(t, rendered, test_case.expected)
		delete(rendered)
	}
}

@(test)
test_render_rejects_invalid_span_without_allocating :: proc(t: ^testing.T) {
	source := borrow_source("<test>", "abc")
	invalid := Span{start = 2, end = 1}
	rendered, ok := render_error(source, invalid, "problem", context.allocator)
	testing.expect(t, !ok)
	testing.expect_value(t, rendered, "")
}

@(test)
test_render_allocator_ownership_and_no_aliases :: proc(t: ^testing.T) {
	output_tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&output_tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&output_tracker)
	size_checker := Size_Checking_Allocator{
		backing = mem.tracking_allocator(&output_tracker),
		tracker = &output_tracker,
	}
	output_allocator := size_checking_allocator(&size_checker)

	temp_tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&temp_tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&temp_tracker)
	old_temp_allocator := context.temp_allocator
	context.temp_allocator = mem.tracking_allocator(&temp_tracker)
	defer context.temp_allocator = old_temp_allocator

	backing := make([]byte, 3)
	defer delete(backing)
	backing[0] = 'a'
	backing[1] = 'b'
	backing[2] = 'c'
	source := borrow_source("<owned-test>", string(backing))
	span, span_ok := make_span(source, 0, 1)
	testing.expect(t, span_ok)

	rendered, render_ok := render_error(source, span, "problem", output_allocator)
	testing.expect(t, render_ok)
	testing.expect_value(t, len(output_tracker.allocation_map), 1)
	testing.expect_value(t, len(temp_tracker.allocation_map), 0)
	testing.expect(t, !size_checker.size_mismatch)
	output_entry, found := output_tracker.allocation_map[raw_data(rendered)]
	testing.expect(t, found)
	testing.expect_value(t, output_entry.size, len(rendered))

	backing[0] = 'z'
	testing.expect_value(
		t,
		rendered,
		"jq: error: problem at <owned-test>, line 1, column 1:\n    abc\n    ^",
	)

	delete(rendered, output_allocator)
	testing.expect(t, !size_checker.size_mismatch)
	testing.expect_value(t, len(output_tracker.allocation_map), 0)
	testing.expect_value(t, len(output_tracker.bad_free_array), 0)
}

@(test)
test_repeated_render_release_owns_each_result :: proc(t: ^testing.T) {
	output_tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&output_tracker, context.allocator)
	defer mem.tracking_allocator_destroy(&output_tracker)
	size_checker := Size_Checking_Allocator{
		backing = mem.tracking_allocator(&output_tracker),
		tracker = &output_tracker,
	}
	output_allocator := size_checking_allocator(&size_checker)

	source := borrow_source("<stress>", "éxy\nnext")
	span, span_ok := make_span(source, 2, 7)
	testing.expect(t, span_ok)
	message := "problem"
	expected := "jq: error: problem at <stress>, line 1, column 3:\n    éxy\n      ^^"

	for _ in 0 ..< 1000 {
		rendered, render_ok := render_error(source, span, message, output_allocator)
		testing.expect(t, render_ok)
		testing.expect_value(t, rendered, expected)
		testing.expect(t, raw_data(rendered) != raw_data(source_bytes(source)))
		testing.expect(t, raw_data(rendered) != raw_data(message))
		testing.expect_value(t, len(output_tracker.allocation_map), 1)
		output_entry, found := output_tracker.allocation_map[raw_data(rendered)]
		testing.expect(t, found)
		testing.expect_value(t, output_entry.size, len(rendered))
		testing.expect(t, !size_checker.size_mismatch)
		testing.expect_value(t, len(output_tracker.bad_free_array), 0)

		delete(rendered, output_allocator)
		testing.expect(t, !size_checker.size_mismatch)
		testing.expect_value(t, len(output_tracker.allocation_map), 0)
		testing.expect_value(t, len(output_tracker.bad_free_array), 0)
	}
}

@(test)
test_render_fails_atomically_on_each_allocation_request :: proc(t: ^testing.T) {
	source := borrow_source("<fault>", "0123456789")
	span, span_ok := make_span(source, 2, 9)
	testing.expect(t, span_ok)
	message := "abcdefghijklmnopqrstuvwxyz"

	baseline_tracker: mem.Tracking_Allocator
	mem.tracking_allocator_init(&baseline_tracker, context.allocator)
	baseline := Failing_Allocator{
		backing = mem.tracking_allocator(&baseline_tracker),
	}
	rendered, render_ok := render_error(
		source,
		span,
		message,
		failing_allocator(&baseline),
	)
	testing.expect(t, render_ok)
	testing.expect(t, baseline.request_count > 1)
	total_requests := baseline.request_count
	delete(rendered, failing_allocator(&baseline))
	testing.expect_value(t, len(baseline_tracker.allocation_map), 0)
	testing.expect_value(t, len(baseline_tracker.bad_free_array), 0)
	mem.tracking_allocator_destroy(&baseline_tracker)

	for fail_at in 1 ..= total_requests {
		tracker: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracker, context.allocator)
		failer := Failing_Allocator{
			backing = mem.tracking_allocator(&tracker),
			fail_at = fail_at,
		}

		failed_result, failed_ok := render_error(
			source,
			span,
			message,
			failing_allocator(&failer),
		)
		testing.expect(t, !failed_ok)
		testing.expect_value(t, failed_result, "")
		testing.expect_value(t, failer.request_count, fail_at)
		testing.expect_value(t, len(tracker.allocation_map), 0)
		testing.expect_value(t, len(tracker.bad_free_array), 0)
		mem.tracking_allocator_destroy(&tracker)
	}
}
