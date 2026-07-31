// Package diagnostic owns source locations and domain-neutral diagnostics.
package diagnostic

import "base:runtime"
import "core:strconv"
import "core:strings"
import "core:sync"

@(private="package")
Source_Identity :: distinct u64

@(private="package")
next_source_identity: u64

// Source is a borrowed view of a source identity and its bytes.
//
// name and bytes alias caller-owned storage. The caller must keep both alive
// and unchanged while the Source, or a Location returned from it, is in use.
// A Source returned by borrow_source may be copied unchanged, but callers must
// not rewrite any Source field. Odin cannot make individual fields of this
// public struct opaque: consistently replacing the string views and their
// pointer/length metadata while retaining identity is outside the valid API
// contract and cannot be rejected as provenance forgery. A separate
// borrow_source call creates a distinct view even when its name and bytes are
// equal. Odin strings are length-delimited, so bytes may contain embedded NULs.
Source :: struct {
	name:              string,
	bytes:             string,
	identity:          Source_Identity,
	borrowed_name:     rawptr,
	borrowed_name_len: int,
	borrowed_bytes:    rawptr,
	borrowed_bytes_len: int,
}

// Span stores a half-open byte range [start, end) for a Source.
//
// make_span is the checked constructor. Because Odin does not support private
// struct fields, validation is structural rather than proof of provenance: a
// caller with a valid source identity can copy a Span and select any in-range
// offsets. Public operations validate the range and matching source-view
// identity before exposing or using offsets. The identity is a non-owning value;
// Span does not retain source storage.
Span :: struct {
	start:           int,
	end:             int,
	source_identity: Source_Identity,
}

// Location describes a span start and its containing source line.
//
// line and byte_column are one-based. source_line aliases the Source bytes and
// is valid only for the Source's borrowed lifetime. It excludes the terminating
// newline, when present.
Location :: struct {
	line:         int,
	byte_column:  int,
	source_line:  string,
	line_start:   int,
}

// borrow_source constructs a distinct borrowed source view without allocating.
// The caller keeps its backing strings valid and unchanged for the borrow
// lifetime. The returned Source may be copied unchanged; callers must not
// rewrite its fields. A later borrow_source call is intentionally a different
// view.
borrow_source :: proc(name, bytes: string) -> Source {
	return Source{
		name = name,
		bytes = bytes,
		identity = new_source_identity(),
		borrowed_name = rawptr(raw_data(name)),
		borrowed_name_len = len(name),
		borrowed_bytes = rawptr(raw_data(bytes)),
		borrowed_bytes_len = len(bytes),
	}
}

// source_name returns the Source's borrowed name view.
source_name :: proc(source: Source) -> string {
	return source.name
}

// source_bytes returns the Source's borrowed bytes view.
source_bytes :: proc(source: Source) -> string {
	return source.bytes
}

// make_span validates a half-open byte range against source.
//
// A zero-width span at end of source is valid. locate and render_error define
// how that span is presented; parser choices about attaching spans to
// unterminated constructs remain outside this package.
make_span :: proc(source: Source, start, end: int) -> (span: Span, ok: bool) {
	if !source_is_valid(source) ||
	   start < 0 ||
	   end < start ||
	   end > len(source.bytes) {
		return {}, false
	}
	return Span{
		start = start,
		end = end,
		source_identity = source.identity,
	}, true
}

// span_offsets returns the half-open byte offsets after structurally validating
// span against source. Invalid, stale, or mismatched spans return false.
span_offsets :: proc(source: Source, span: Span) -> (start, end: int, ok: bool) {
	if !span_is_valid(source, span) {
		return 0, 0, false
	}
	return span.start, span.end, true
}

// locate converts a known span start to a one-based line and byte-column and
// returns its containing source line. It does not allocate.
//
// The returned source_line is borrowed from source. False is returned if span
// is not structurally valid for source. For a zero-width end-of-source span,
// source_line is the final line and byte_column is one past its last byte. If
// source ends in a newline, source_line is the following empty line and
// byte_column is one.
locate :: proc(source: Source, span: Span) -> (location: Location, ok: bool) {
	if !span_is_valid(source, span) {
		return {}, false
	}

	line_number := 1
	line_start := 0
	for offset in 0 ..< span.start {
		if source.bytes[offset] == '\n' {
			line_number += 1
			line_start = offset + 1
		}
	}

	line_end := line_start
	for line_end < len(source.bytes) && source.bytes[line_end] != '\n' {
		line_end += 1
	}

	return Location{
		line = line_number,
		byte_column = span.start - line_start + 1,
		source_line = source.bytes[line_start:line_end],
		line_start = line_start,
	}, true
}

// render_error renders jq's known-location "jq: error:" diagnostic form.
//
// The returned string is owned storage allocated with allocator. The caller
// must release it with delete(result, allocator). No returned data aliases
// source, message, context.allocator, or context.temp_allocator.
//
// An end-of-source span uses locate's final-line policy and is rendered with
// one caret. False is returned without allocating when span is invalid for
// source. UNKNOWN_LOCATION behavior is intentionally outside this API.
render_error :: proc(
	source: Source,
	span: Span,
	message: string,
	allocator: runtime.Allocator,
) -> (result: string, ok: bool) {
	location, located := locate(source, span)
	if !located {
		return "", false
	}

	highlight_end := min(span.end, location.line_start + len(location.source_line))
	caret_count := max(1, highlight_end - span.start)

	builder: strings.Builder
	_, init_err := strings.builder_init(&builder, allocator)
	if init_err != nil {
		return "", false
	}
	defer strings.builder_destroy(&builder)

	line_buffer: [32]byte
	column_buffer: [32]byte
	line_text := strconv.write_int(line_buffer[:], i64(location.line), 10)
	column_text := strconv.write_int(column_buffer[:], i64(location.byte_column), 10)

	if !builder_write(&builder, "jq: error: ") ||
	   !builder_write(&builder, message) ||
	   !builder_write(&builder, " at ") ||
	   !builder_write(&builder, source.name) ||
	   !builder_write(&builder, ", line ") ||
	   !builder_write(&builder, line_text) ||
	   !builder_write(&builder, ", column ") ||
	   !builder_write(&builder, column_text) ||
	   !builder_write(&builder, ":\n    ") ||
	   !builder_write(&builder, location.source_line) ||
	   !builder_write(&builder, "\n    ") {
		return "", false
	}
	for _ in 1 ..< location.byte_column {
		if strings.write_byte(&builder, ' ') != 1 {
			return "", false
		}
	}
	for _ in 0 ..< caret_count {
		if strings.write_byte(&builder, '^') != 1 {
			return "", false
		}
	}

	clone_err: runtime.Allocator_Error
	result, clone_err = strings.clone(strings.to_string(builder), allocator)
	if clone_err != nil || len(result) != strings.builder_len(builder) {
		if result != "" {
			delete(result, allocator)
		}
		return "", false
	}
	return result, true
}

@(private="package")
builder_write :: proc(builder: ^strings.Builder, text: string) -> bool {
	return strings.write_string(builder, text) == len(text)
}

@(private="package")
span_is_valid :: proc(source: Source, span: Span) -> bool {
	return source_is_valid(source) &&
	       span.source_identity == source.identity &&
	       span.start >= 0 &&
	       span.end >= span.start &&
	       span.end <= len(source.bytes)
}

@(private="package")
source_is_valid :: proc(source: Source) -> bool {
	return source.identity != 0 &&
	       source.borrowed_name == rawptr(raw_data(source.name)) &&
	       source.borrowed_name_len == len(source.name) &&
	       source.borrowed_bytes == rawptr(raw_data(source.bytes)) &&
	       source.borrowed_bytes_len == len(source.bytes)
}

@(private="package")
new_source_identity :: proc() -> Source_Identity {
	for {
		current := sync.atomic_load_explicit(&next_source_identity, .Relaxed)
		if current == max(u64) {
			panic("diagnostic Source identity exhausted")
		}
		next := current + 1
		if _, exchanged := sync.atomic_compare_exchange_weak_explicit(
			&next_source_identity,
			current,
			next,
			.Relaxed,
			.Relaxed,
		); exchanged {
			return Source_Identity(next)
		}
	}
}
