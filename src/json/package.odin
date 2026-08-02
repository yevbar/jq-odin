// Package json owns JSON text parsing, printing, and streaming.
package json

import "base:runtime"
import "jq:value"

// Scalar_Parse_Error_Kind serves the compatible scalar API and the one-shot
// complete-value API. Streaming implementations may extend the package without
// turning either API into an incremental parser.
Scalar_Parse_Error_Kind :: enum u8 {
	None,
	Expected_Value,
	Trailing_Input,
	Array_Not_Supported,
	Object_Not_Supported,
	Invalid_Literal,
	Invalid_Number,
	Unfinished_String,
	Unfinished_Escape,
	Unfinished_Unicode_Escape,
	Invalid_Escape,
	Invalid_Unicode_Escape,
	Invalid_Surrogate_Pair,
	Unescaped_Control,
	Malformed_BOM,
	Allocation_Failure,
	Size_Overflow,
	Value_Construction_Failure,
	Scratch_Cleanup_Failure,
	Unfinished_Array,
	Expected_Array_Element,
	Expected_Value_Before_Separator,
	Expected_Separator,
	Mismatched_Closer,
	Unmatched_Array_Closer,
	Unmatched_Object_Closer,
	Object_Key_Value_Pairs_Required,
	Expected_String_Key_Before_Colon,
	Unexpected_Colon,
	Unexpected_Extra_Values,
	Depth_Limit,
	Array_Operation_Failure,
	Object_Keys_Must_Be_Strings,
	Expected_Object_Member,
	Unfinished_Object,
	Object_Operation_Failure,
}

// jq's ordinary JSON parser reports "Exceeds depth limit for parsing" when a
// reachable container opener sees this many live parser stack entries. A
// validated colon is intentionally not guarded and may temporarily move the
// live count from 10,000 to 10,001.
@(private)
MAX_PARSING_DEPTH :: 10_000

@(private)
container_kind :: enum u8 {
	Array,
	Object,
}

@(private)
object_parse_phase :: enum u8 {
	Key,
	Colon,
	Value,
	Separator,
}

@(private)
array_parse_frame :: struct {
	array:         value.Value,
	pending_key:   value.Value,
	pending_value: value.Value,
	open_offset:   int,
	kind:          container_kind,
	expect_value:  bool,
	after_comma:   bool,
	object_phase:  object_parse_phase,
}

@(private)
frame_stack_block :: struct {
	previous:   ^frame_stack_block,
	next:       ^frame_stack_block,
	byte_count: int,
	capacity:   int,
	count:      int,
}

@(private)
frame_stack :: struct {
	blocks:      ^frame_stack_block,
	current:     ^frame_stack_block,
	active_count: int,
	allocator:   runtime.Allocator,
}

@(private)
INITIAL_FRAME_CAPACITY :: 1

#assert(size_of(frame_stack_block) % align_of(array_parse_frame) == 0)
#assert(align_of(frame_stack_block) >= align_of(array_parse_frame))

// Scalar_Parse_Error contains no view into the input. It is non-owning except
// when kind is Scratch_Cleanup_Failure. That exceptional error retains every
// scratch, constructor-error, or Value allocation whose Free failed and must
// be passed to destroy_scalar_parse_error until retirement succeeds; it must
// not be copied.
//
// detection_offset is the zero-based absolute byte where jq's scanner detects
// the error: a delimiter or matched closing quote when one triggered
// validation, otherwise the last byte observed at EOF. cause_offset is a
// separate zero-based absolute byte or EOF boundary for the local cause when
// has_cause_offset is true. Keeping both avoids conflating a useful local cause
// with the cursor used by jq-facing diagnostics.
Scalar_Parse_Error :: struct {
	kind:                      Scalar_Parse_Error_Kind,
	detection_offset:          int,
	cause_offset:              int,
	has_cause_offset:          bool,
	cause_kind:                Scalar_Parse_Error_Kind,
	cleanup_scratch:           []byte,
	cleanup_allocator:         runtime.Allocator,
	cleanup_constructor_error: value.Constructor_Error,
	cleanup_array_error:       value.Array_Operation_Error,
	cleanup_object_error:      value.Object_Operation_Error,
	cleanup_value:             value.Value,
	cleanup_frame_blocks:      ^frame_stack_block,
	cleanup_frame_current:     ^frame_stack_block,
	cleanup_frame_count:       int,
	cleanup_frame_allocator:  runtime.Allocator,
}

// destroy_scalar_parse_error retires storage retained by a scratch-cleanup
// failure. A genuine allocator error leaves the corresponding handle in err
// for a later retry. It is harmless for every other error kind.
destroy_scalar_parse_error :: proc(err: ^Scalar_Parse_Error) -> runtime.Allocator_Error {
	if err == nil || err.kind != .Scratch_Cleanup_Failure {
		return nil
	}
	first_error: runtime.Allocator_Error
	if len(err.cleanup_scratch) > 0 {
		free_error := runtime.mem_free_bytes(err.cleanup_scratch, err.cleanup_allocator)
		if free_error == nil || free_error == .Mode_Not_Implemented {
			err.cleanup_scratch = nil
			err.cleanup_allocator = {}
		} else {
			first_error = free_error
		}
	}
	constructor_error := value.destroy_constructor_error(&err.cleanup_constructor_error)
	if first_error == nil && constructor_error != nil {
		first_error = constructor_error
	}
	array_error := value.destroy_array_error(&err.cleanup_array_error)
	if first_error == nil && array_error != nil {
		first_error = array_error
	}
	object_error := value.destroy_object_error(&err.cleanup_object_error)
	if first_error == nil && object_error != nil {
		first_error = object_error
	}
	value_error := value.destroy_value(&err.cleanup_value)
	if first_error == nil && value_error != nil {
		first_error = value_error
	}
	frames_retired := true
	remaining := err.cleanup_frame_count
	block := err.cleanup_frame_current
	for block != nil && remaining > 0 {
		frame_data := cast([^]array_parse_frame)(uintptr(block) + size_of(frame_stack_block))
		frames := frame_data[:block.capacity]
		limit := min(block.count, remaining)
		for i := limit - 1; i >= 0; i -= 1 {
			frame_error := value.destroy_value(&frames[i].pending_value)
			if frame_error == nil do frame_error = value.destroy_value(&frames[i].pending_key)
			if frame_error == nil do frame_error = value.destroy_value(&frames[i].array)
			if frame_error != nil {
				frames_retired = false
				if first_error == nil do first_error = frame_error
			}
		}
		remaining -= limit
		block = block.previous
	}
	if frames_retired {
		err.cleanup_frame_current = nil
		err.cleanup_frame_count = 0
		for err.cleanup_frame_blocks != nil {
			release_block := err.cleanup_frame_blocks
			previous := release_block.previous
			byte_data := cast([^]byte)(rawptr(release_block))
			memory := byte_data[:release_block.byte_count]
			frame_free_error := runtime.mem_free_bytes(memory, err.cleanup_frame_allocator)
			if frame_free_error != nil && frame_free_error != .Mode_Not_Implemented {
				if first_error == nil do first_error = frame_free_error
				break
			}
			err.cleanup_frame_blocks = previous
		}
		if err.cleanup_frame_blocks == nil {
			err.cleanup_frame_allocator = {}
		}
	}
	if first_error == nil {
		err^ = {}
	}
	return first_error
}

@(private)
parse_failure :: proc(kind: Scalar_Parse_Error_Kind, offset: int) -> (
	value.Value,
	Scalar_Parse_Error,
) {
	return value.invalid_value(), {
		kind = kind,
		detection_offset = offset,
		cause_offset = offset,
		has_cause_offset = true,
	}
}

@(private)
parse_detected_failure :: proc(
	kind: Scalar_Parse_Error_Kind,
	detection_offset, cause_offset: int,
) -> (value.Value, Scalar_Parse_Error) {
	return value.invalid_value(), {
		kind = kind,
		detection_offset = detection_offset,
		cause_offset = cause_offset,
		has_cause_offset = true,
	}
}

@(private)
is_whitespace :: proc(c: byte) -> bool {
	return c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

@(private)
is_structure :: proc(c: byte) -> bool {
	return c == '[' || c == ']' || c == '{' || c == '}' || c == ',' || c == ':'
}

@(private)
is_token_delimiter :: proc(c: byte) -> bool {
	return is_whitespace(c) || is_structure(c) || c == '"'
}

@(private)
is_digit :: proc(c: byte) -> bool {
	return c >= '0' && c <= '9'
}

// number_cause_offset is diagnostic-only. Acceptance is decided solely by the
// Value numeric constructor; this permissive walk only identifies a useful
// local cause for ordinary decimal spellings after that constructor rejects.
@(private)
number_cause_offset :: proc(token: string) -> int {
	if len(token) == 0 {
		return 0
	}
	i := 0
	if token[i] == '-' || token[i] == '+' {
		i += 1
		if i == len(token) {
			return i
		}
	}
	digits := 0
	for i < len(token) && is_digit(token[i]) {
		i += 1
		digits += 1
	}
	if i < len(token) && token[i] == '.' {
		i += 1
		for i < len(token) && is_digit(token[i]) {
			i += 1
			digits += 1
		}
	}
	if digits == 0 {
		return i
	}
	if i < len(token) && (token[i] == 'e' || token[i] == 'E') {
		i += 1
		if i < len(token) && (token[i] == '+' || token[i] == '-') {
			i += 1
		}
		exponent_at := i
		for i < len(token) && is_digit(token[i]) {
			i += 1
		}
		if i == exponent_at {
			return i
		}
	}
	return i
}

@(private)
detection_before_eof :: proc(cursor: int) -> int {
	if cursor > 0 {
		return cursor - 1
	}
	return 0
}

@(private)
literal_detection_offset :: proc(input: string, token_end: int) -> int {
	if token_end < len(input) {
		return token_end
	}
	return detection_before_eof(token_end)
}

@(private)
hex_digit :: proc(c: byte) -> (u32, bool) {
	switch c {
	case '0'..='9':
		return u32(c - '0'), true
	case 'a'..='f':
		return u32(c - 'a') + 10, true
	case 'A'..='F':
		return u32(c - 'A') + 10, true
	}
	return 0, false
}

@(private)
parse_hex4 :: proc(input: string, at: int) -> (u32, bool) {
	result := u32(0)
	for i in 0..<4 {
		digit, ok := hex_digit(input[at + i])
		if !ok {
			return 0, false
		}
		result = result << 4 | digit
	}
	return result, true
}

@(private)
append_codepoint :: proc(output: []byte, at: ^int, codepoint: u32) {
	switch {
	case codepoint <= 0x7f:
		output[at^] = byte(codepoint)
		at^ += 1
	case codepoint <= 0x7ff:
		output[at^] = 0xc0 | byte(codepoint >> 6)
		output[at^ + 1] = 0x80 | byte(codepoint & 0x3f)
		at^ += 2
	case codepoint <= 0xffff:
		output[at^] = 0xe0 | byte(codepoint >> 12)
		output[at^ + 1] = 0x80 | byte(codepoint >> 6 & 0x3f)
		output[at^ + 2] = 0x80 | byte(codepoint & 0x3f)
		at^ += 3
	case:
		output[at^] = 0xf0 | byte(codepoint >> 18)
		output[at^ + 1] = 0x80 | byte(codepoint >> 12 & 0x3f)
		output[at^ + 2] = 0x80 | byte(codepoint >> 6 & 0x3f)
		output[at^ + 3] = 0x80 | byte(codepoint & 0x3f)
		at^ += 4
	}
}

@(private)
is_continuation :: proc(c: byte) -> bool {
	return c >= 0x80 && c <= 0xbf
}

// jq consumes the valid prefix of a malformed multibyte sequence as one bad
// point, not necessarily one replacement per byte. A truncated sequence
// consumes all bytes remaining in the current length-delimited buffer.
@(private)
copy_utf8_point :: proc(input: string, input_at: int, output: []byte, output_at: ^int) -> int {
	first := input[input_at]
	if first < 0x80 {
		output[output_at^] = first
		output_at^ += 1
		return 1
	}
	length := 0
	minimum := u32(0)
	mask := byte(0)
	switch {
	case first >= 0xc2 && first <= 0xdf:
		length, minimum, mask = 2, 0x80, 0x1f
	case first >= 0xe0 && first <= 0xef:
		length, minimum, mask = 3, 0x800, 0x0f
	case first >= 0xf0 && first <= 0xf4:
		length, minimum, mask = 4, 0x10000, 0x07
	case:
		append_codepoint(output, output_at, 0xfffd)
		return 1
	}

	remaining := len(input) - input_at
	if remaining < length {
		append_codepoint(output, output_at, 0xfffd)
		return remaining
	}
	codepoint := u32(first & mask)
	for i in 1..<length {
		c := input[input_at + i]
		if !is_continuation(c) {
			append_codepoint(output, output_at, 0xfffd)
			return i
		}
		codepoint = codepoint << 6 | u32(c & 0x3f)
	}
	if codepoint < minimum ||
	   (codepoint >= 0xd800 && codepoint <= 0xdfff) ||
	   codepoint > 0x10ffff {
		append_codepoint(output, output_at, 0xfffd)
		return length
	}
	copy(output[output_at^:], transmute([]byte)input[input_at:input_at + length])
	output_at^ += length
	return length
}

@(private)
constructor_failure_kind :: proc(err: ^value.Constructor_Error) -> Scalar_Parse_Error_Kind {
	switch value.constructor_error_kind(err) {
	case .Out_Of_Memory:
		return .Allocation_Failure
	case .Size_Overflow:
		return .Size_Overflow
	case .None, .Invalid_Number_Literal:
		return .Value_Construction_Failure
	}
	return .Value_Construction_Failure
}

@(private)
constructor_failure :: proc(err: ^value.Constructor_Error, offset: int) -> (
	value.Value,
	Scalar_Parse_Error,
) {
	kind := constructor_failure_kind(err)
	if value.constructor_error_needs_cleanup(err) {
		return value.invalid_value(), {
			kind = .Scratch_Cleanup_Failure,
			detection_offset = offset,
			cause_offset = offset,
			has_cause_offset = true,
			cause_kind = kind,
			cleanup_constructor_error = value.take_constructor_error(err),
		}
	}
	return parse_failure(kind, offset)
}

@(private)
retire_decode_failure :: proc(
	kind: Scalar_Parse_Error_Kind,
	detection_offset, cause_offset, next: int,
	decoded: []byte,
	allocator: runtime.Allocator,
) -> (value.Value, int, Scalar_Parse_Error) {
	if len(decoded) > 0 {
		free_error := runtime.mem_free_bytes(decoded, allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			return value.invalid_value(), next, {
				kind = .Scratch_Cleanup_Failure,
				detection_offset = detection_offset,
				cause_offset = cause_offset,
				has_cause_offset = true,
				cause_kind = kind,
				cleanup_scratch = decoded,
				cleanup_allocator = allocator,
			}
		}
	}
	return value.invalid_value(), next, {
		kind = kind,
		detection_offset = detection_offset,
		cause_offset = cause_offset,
		has_cause_offset = true,
	}
}

@(private)
parse_string :: proc(
	input: string,
	quote_at, token_end: int,
	allocator: runtime.Allocator,
) -> (
	result: value.Value,
	next: int,
	err: Scalar_Parse_Error,
) {
	content_len := token_end - quote_at - 2
	if content_len > max(int) / 3 {
		return value.invalid_value(), quote_at, {
			kind = .Size_Overflow,
			detection_offset = quote_at,
			cause_offset = quote_at,
			has_cause_offset = true,
		}
	}
	capacity := content_len * 3
	decoded: []byte
	temporary_allocator := context.temp_allocator
	if capacity > 0 {
		allocation_error: runtime.Allocator_Error
		decoded, allocation_error = runtime.mem_alloc(capacity, align_of(uintptr), temporary_allocator)
		if allocation_error != nil || len(decoded) != capacity {
			if len(decoded) > 0 {
				return retire_decode_failure(
					.Allocation_Failure,
					quote_at,
					quote_at,
					quote_at,
					decoded,
					temporary_allocator,
				)
			}
			return value.invalid_value(), quote_at, {
				kind = .Allocation_Failure,
				detection_offset = quote_at,
				cause_offset = quote_at,
				has_cause_offset = true,
			}
		}
	}

	i := quote_at + 1
	content_end := token_end - 1
	detection_offset := content_end
	// Unescape into the final third of scratch first. Normalization then writes
	// forward from the start; before the last source byte is consumed, at most
	// three output bytes per consumed byte cannot reach the unread source.
	raw_start := content_len * 2
	raw_out := raw_start
	for i < content_end {
		c := input[i]
		if c < 0x20 {
			return retire_decode_failure(
				.Unescaped_Control,
				detection_offset,
				i,
				i,
				decoded,
				temporary_allocator,
			)
		}
		if c != '\\' {
			decoded[raw_out] = c
			raw_out += 1
			i += 1
			continue
		}

		i += 1
		if i == content_end {
			return retire_decode_failure(
				.Invalid_Escape,
				detection_offset,
				i,
				i,
				decoded,
				temporary_allocator,
			)
		}
		switch input[i] {
		case '"', '\\', '/':
			decoded[raw_out] = input[i]
			raw_out += 1
			i += 1
		case 'b', 'f', 't', 'n', 'r':
			switch input[i] {
			case 'b': decoded[raw_out] = '\b'
			case 'f': decoded[raw_out] = '\f'
			case 't': decoded[raw_out] = '\t'
			case 'n': decoded[raw_out] = '\n'
			case 'r': decoded[raw_out] = '\r'
			}
			raw_out += 1
			i += 1
		case 'u':
			hex_at := i + 1
			if content_end - hex_at < 4 {
				return retire_decode_failure(
					.Invalid_Unicode_Escape,
					detection_offset,
					content_end,
					content_end,
					decoded,
					temporary_allocator,
				)
			}
			codepoint, ok := parse_hex4(input, hex_at)
			if !ok {
				bad := hex_at
				for bad < hex_at + 4 {
					_, digit_ok := hex_digit(input[bad])
					if !digit_ok {
						break
					}
					bad += 1
				}
				return retire_decode_failure(
					.Invalid_Unicode_Escape,
					detection_offset,
					bad,
					bad,
					decoded,
					temporary_allocator,
				)
			}
			i = hex_at + 4
			if codepoint >= 0xd800 && codepoint <= 0xdbff {
				if content_end - i < 6 || input[i] != '\\' || input[i + 1] != 'u' {
					return retire_decode_failure(
						.Invalid_Surrogate_Pair,
						detection_offset,
						i,
						i,
						decoded,
						temporary_allocator,
					)
				}
				low, low_ok := parse_hex4(input, i + 2)
				if !low_ok || low < 0xdc00 || low > 0xdfff {
					return retire_decode_failure(
						.Invalid_Surrogate_Pair,
						detection_offset,
						i + 2,
						i + 2,
						decoded,
						temporary_allocator,
					)
				}
				codepoint = 0x10000 + ((codepoint - 0xd800) << 10 | (low - 0xdc00))
				i += 6
			}
			if codepoint >= 0xdc00 && codepoint <= 0xdfff {
				codepoint = 0xfffd
			}
			append_codepoint(decoded, &raw_out, codepoint)
		case:
			return retire_decode_failure(
				.Invalid_Escape,
				detection_offset,
				i,
				i,
				decoded,
				temporary_allocator,
			)
		}
	}

	raw_string := transmute(string)decoded[raw_start:raw_out]
	raw_at := 0
	out := 0
	for raw_at < len(raw_string) {
		raw_at += copy_utf8_point(raw_string, raw_at, decoded, &out)
	}
	decoded_string := transmute(string)decoded
	constructed, construction_error := value.string_value(decoded_string[:out], allocator)
	construction_kind := Scalar_Parse_Error_Kind.None
	if construction_error != nil {
		construction_kind = constructor_failure_kind(&construction_error)
	}
	if len(decoded) > 0 {
		free_error := runtime.mem_free_bytes(decoded, temporary_allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			return value.invalid_value(), token_end, {
				kind = .Scratch_Cleanup_Failure,
				detection_offset = quote_at,
				cause_offset = quote_at,
				has_cause_offset = true,
				cause_kind = construction_kind,
				cleanup_scratch = decoded,
				cleanup_allocator = temporary_allocator,
				cleanup_constructor_error = value.take_constructor_error(&construction_error),
				cleanup_value = constructed,
			}
		}
	}
	if construction_error != nil {
		failure_value, failure := constructor_failure(&construction_error, quote_at)
		return failure_value, token_end, failure
	}
	return constructed, token_end, {}
}

@(private)
validate_matched_string :: proc(input: string, quote_at, token_end: int) -> Scalar_Parse_Error {
	content_end := token_end - 1
	detection_offset := content_end
	i := quote_at + 1
	for i < content_end {
		c := input[i]
		if c < 0x20 {
			return {
				kind = .Unescaped_Control,
				detection_offset = detection_offset,
				cause_offset = i,
				has_cause_offset = true,
			}
		}
		if c != '\\' {
			i += 1
			continue
		}
		i += 1
		if i == content_end {
			return {
				kind = .Invalid_Escape,
				detection_offset = detection_offset,
				cause_offset = i,
				has_cause_offset = true,
			}
		}
		switch input[i] {
		case '"', '\\', '/', 'b', 'f', 't', 'n', 'r':
			i += 1
		case 'u':
			hex_at := i + 1
			if content_end - hex_at < 4 {
				return {
					kind = .Invalid_Unicode_Escape,
					detection_offset = detection_offset,
					cause_offset = content_end,
					has_cause_offset = true,
				}
			}
			codepoint, ok := parse_hex4(input, hex_at)
			if !ok {
				bad := hex_at
				for bad < hex_at + 4 {
					_, digit_ok := hex_digit(input[bad])
					if !digit_ok {
						break
					}
					bad += 1
				}
				return {
					kind = .Invalid_Unicode_Escape,
					detection_offset = detection_offset,
					cause_offset = bad,
					has_cause_offset = true,
				}
			}
			i = hex_at + 4
			if codepoint >= 0xd800 && codepoint <= 0xdbff {
				if content_end - i < 6 || input[i] != '\\' || input[i + 1] != 'u' {
					return {
						kind = .Invalid_Surrogate_Pair,
						detection_offset = detection_offset,
						cause_offset = i,
						has_cause_offset = true,
					}
				}
				low, low_ok := parse_hex4(input, i + 2)
				if !low_ok || low < 0xdc00 || low > 0xdfff {
					return {
						kind = .Invalid_Surrogate_Pair,
						detection_offset = detection_offset,
						cause_offset = i + 2,
						has_cause_offset = true,
					}
				}
				i += 6
			}
		case:
			return {
				kind = .Invalid_Escape,
				detection_offset = detection_offset,
				cause_offset = i,
				has_cause_offset = true,
			}
		}
	}
	return {}
}

// scan_string_end first follows jq's scanner states to find a closing quote.
// Syntax inside a matched token is deliberately validated later so its error
// retains the closing-quote detection cursor. jq does not validate buffered
// string content unless it observes a closing quote.
@(private)
scan_string_end :: proc(input: string, quote_at: int) -> (
	next: int,
	err: Scalar_Parse_Error,
) {
	i := quote_at + 1
	for i < len(input) {
		if input[i] == '"' {
			token_end := i + 1
			return token_end, validate_matched_string(input, quote_at, token_end)
		}
		if input[i] == '\\' {
			i += 1
			if i == len(input) {
				break
			}
		}
		i += 1
	}

	return len(input), {
		kind = .Unfinished_String,
		detection_offset = detection_before_eof(len(input)),
		cause_offset = len(input),
		has_cause_offset = true,
	}
}

@(private)
keyword_cause_offset :: proc(token, pattern: string) -> int {
	shared := min(len(token), len(pattern))
	for i in 0..<shared {
		if token[i] != pattern[i] {
			return i
		}
	}
	return shared
}

@(private)
scalar_form :: enum u8 {
	Null,
	True,
	False,
	Number,
	String,
}

// parse_scalar_at parses one scalar token beginning exactly at value_at. It
// does not skip leading whitespace or classify following input as trailing;
// the one-shot scalar and array parsers apply those document/container rules.
@(private)
parse_scalar_at :: proc(input: string, value_at: int, allocator: runtime.Allocator) -> (
	result: value.Value,
	next: int,
	err: Scalar_Parse_Error,
) {
	i := value_at
	form: scalar_form
	token: string
	numeric_token: string
	switch input[i] {
	case '[':
		result, err = parse_failure(.Array_Not_Supported, i)
		return result, i, err
	case '{':
		result, err = parse_failure(.Object_Not_Supported, i)
		return result, i, err
	case '"':
		form = .String
		next, err = scan_string_end(input, i)
		if err.kind != nil {
			return value.invalid_value(), next, err
		}
	case:
		next = i
		for next < len(input) && !is_token_delimiter(input[next]) {
			next += 1
		}
		token = input[i:next]
		if len(token) == 0 {
			result, err = parse_failure(.Invalid_Literal, i)
			return result, next, err
		}
		pattern: string
		switch token[0] {
		case 't': pattern, form = "true", .True
		case 'f': pattern, form = "false", .False
		case '\'':
			detection_offset := literal_detection_offset(input, next)
			result, err = parse_detected_failure(.Invalid_Literal, detection_offset, value_at)
			return result, next, err
		case 'n':
			if len(token) > 1 && token[1] == 'u' {
				pattern, form = "null", .Null
			} else {
				form = .Number
			}
		case:
			form = .Number
		}
		if len(pattern) > 0 && token != pattern {
			detection_offset := literal_detection_offset(input, next)
			cause_offset := value_at + keyword_cause_offset(token, pattern)
			result, err = parse_detected_failure(.Invalid_Literal, detection_offset, cause_offset)
			return result, next, err
		}
		if form == .Number {
			numeric_end := 0
			for numeric_end < len(token) && token[numeric_end] != 0 {
				numeric_end += 1
			}
			numeric_token = token[:numeric_end]
		}
	}

	if form == .Number {
		construction_error: value.Constructor_Error
		result, construction_error = value.literal_number_value(numeric_token, allocator)
		if value.constructor_error_kind(&construction_error) == .Invalid_Number_Literal {
			detection_offset := literal_detection_offset(input, next)
			cause_offset := value_at + number_cause_offset(numeric_token)
			result, err = parse_detected_failure(.Invalid_Number, detection_offset, cause_offset)
			return result, next, err
		}
		if construction_error != nil {
			result, err = constructor_failure(&construction_error, value_at)
			return result, next, err
		}
	}

	switch form {
	case .Null:
		return value.null_value(), next, {}
	case .True:
		return value.boolean_value(true), next, {}
	case .False:
		return value.boolean_value(false), next, {}
	case .Number:
		return result, next, {}
	case .String:
		return parse_string(input, value_at, next, allocator)
	}
	result, err = parse_failure(.Value_Construction_Failure, value_at)
	return result, next, err
}

// parse_scalar parses exactly one top-level JSON scalar from a length-delimited
// input. input is borrowed only for this call. On success the returned Value is
// complete owning storage allocated from allocator; on failure it is inert.
parse_scalar :: proc(input: string, allocator: runtime.Allocator) -> (
	result: value.Value,
	err: Scalar_Parse_Error,
) {
	i := 0
	if len(input) > 0 && input[0] == 0xef {
		bom := [3]byte{0xef, 0xbb, 0xbf}
		matched := 1
		for matched < len(bom) && matched < len(input) && input[matched] == bom[matched] {
			matched += 1
		}
		if matched != len(bom) {
			if matched == len(input) {
				return parse_detected_failure(
					.Expected_Value,
					detection_before_eof(len(input)),
					len(input),
				)
			}
			return parse_detected_failure(.Malformed_BOM, matched, matched)
		}
		i = len(bom)
	}
	for i < len(input) && is_whitespace(input[i]) {
		i += 1
	}
	if i == len(input) {
		return parse_detected_failure(
			.Expected_Value,
			detection_before_eof(len(input)),
			len(input),
		)
	}
	value_at := i
	next := i
	is_string := input[i] == '"'
	if is_string {
		next, err = scan_string_end(input, i)
		if err.kind != nil {
			return value.invalid_value(), err
		}
	} else {
		result, next, err = parse_scalar_at(input, value_at, allocator)
		if err.kind != nil {
			return value.invalid_value(), err
		}
	}
	value_end := next
	for next < len(input) && is_whitespace(input[next]) {
		next += 1
	}
	if next != len(input) {
		cleanup_error := value.destroy_value(&result)
		if cleanup_error != nil {
			return value.invalid_value(), {
				kind = .Scratch_Cleanup_Failure,
				detection_offset = next,
				cause_offset = next,
				has_cause_offset = true,
				cause_kind = .Trailing_Input,
				cleanup_value = value.take_value(&result),
			}
		}
		return parse_failure(.Trailing_Input, next)
	}
	if is_string {
		result, _, err = parse_string(input, value_at, value_end, allocator)
		if err.kind != nil {
			return value.invalid_value(), err
		}
	}
	return result, {}
}

@(private)
array_failure_kind :: proc(err: ^value.Array_Operation_Error) -> Scalar_Parse_Error_Kind {
	switch value.array_error_kind(err) {
	case .Out_Of_Memory, .Allocator_Unsupported:
		return .Allocation_Failure
	case .Size_Overflow, .Index_Too_Large:
		return .Size_Overflow
	case .None:
		return .None
	case .Wrong_Kind, .Invalid_Index, .Aliased_Operand, .Cleanup_Failed:
		return .Array_Operation_Failure
	}
	return .Array_Operation_Failure
}

@(private)
promote_cleanup_error :: proc(err: ^Scalar_Parse_Error) {
	if err.kind != .Scratch_Cleanup_Failure {
		err.cause_kind = err.kind
		err.kind = .Scratch_Cleanup_Failure
	}
}

@(private)
take_scalar_parse_error :: proc(source: ^Scalar_Parse_Error) -> Scalar_Parse_Error {
	if source == nil {
		return {}
	}
	result := source^
	source^ = {}
	return result
}

@(private)
frame_block_frames :: proc(block: ^frame_stack_block) -> []array_parse_frame {
	if block == nil do return nil
	data := cast([^]array_parse_frame)(uintptr(block) + size_of(frame_stack_block))
	return data[:block.capacity]
}

@(private)
frame_stack_top :: proc(stack: ^frame_stack) -> ^array_parse_frame {
	if stack == nil || stack.current == nil || stack.current.count <= 0 do return nil
	return &frame_block_frames(stack.current)[stack.current.count - 1]
}

@(private)
frame_stack_pop :: proc(stack: ^frame_stack) {
	if stack == nil || stack.current == nil || stack.current.count <= 0 do return
	stack.current.count -= 1
	stack.active_count -= 1
	if stack.current.count == 0 && stack.current.previous != nil {
		stack.current = stack.current.previous
	}
}

@(private)
frame_stack_allocation_size :: proc(capacity: int) -> (int, bool) {
	header_size := int(size_of(frame_stack_block))
	frame_size := int(size_of(array_parse_frame))
	if capacity <= 0 || capacity > (max(int) - header_size) / frame_size {
		return 0, false
	}
	return header_size + capacity * frame_size, true
}

// grow_frame_stack allocates a separate linked owner. It never resizes or
// copies an existing owner, so allocation and retirement failures cannot lose
// the only representation of any live block.
@(private)
grow_frame_stack :: proc(stack: ^frame_stack, offset: int) -> Scalar_Parse_Error {
	capacity := INITIAL_FRAME_CAPACITY
	if stack.blocks != nil {
		if stack.blocks.capacity > max(int) / 2 {
			return {
				kind = .Size_Overflow,
				detection_offset = offset,
				cause_offset = offset,
				has_cause_offset = true,
			}
		}
		capacity = stack.blocks.capacity * 2
	}
	byte_count, size_ok := frame_stack_allocation_size(capacity)
	if !size_ok {
		return {
			kind = .Size_Overflow,
			detection_offset = offset,
			cause_offset = offset,
			has_cause_offset = true,
		}
	}
	memory, allocation_error := runtime.mem_alloc(
		byte_count,
		align_of(frame_stack_block),
		stack.allocator,
	)
	if allocation_error != nil || len(memory) != byte_count {
		err := Scalar_Parse_Error{
			kind = .Allocation_Failure,
			detection_offset = offset,
			cause_offset = offset,
			has_cause_offset = true,
		}
		if len(memory) > 0 {
			free_error := runtime.mem_free_bytes(memory, stack.allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				promote_cleanup_error(&err)
				err.cleanup_scratch = memory
				err.cleanup_allocator = stack.allocator
			}
		}
		return err
	}
	block := cast(^frame_stack_block)(raw_data(memory))
	block^ = {
		previous = stack.blocks,
		byte_count = byte_count,
		capacity = capacity,
	}
	if stack.blocks != nil do stack.blocks.next = block
	stack.blocks = block
	stack.current = block
	return {}
}

@(private)
push_container_frame :: proc(
	stack: ^frame_stack,
	owner: ^value.Value,
	offset: int,
	kind: container_kind,
) -> Scalar_Parse_Error {
	if stack.current == nil || stack.current.count == stack.current.capacity {
		if stack.current != nil && stack.current.next != nil {
			stack.current = stack.current.next
		} else {
			err := grow_frame_stack(stack, offset)
			if err.kind != .None do return err
		}
	}
	frame := &frame_block_frames(stack.current)[stack.current.count]
	frame^ = {
		array = value.take_value(owner),
		open_offset = offset,
		kind = kind,
		expect_value = true,
		object_phase = .Key,
	}
	stack.current.count += 1
	stack.active_count += 1
	return {}
}

// retire_frame_stack releases active frame owners before retiring every linked
// block from newest to oldest. A failed Free leaves that block and its entire
// predecessor chain represented for a later retry.
@(private)
retire_frame_stack :: proc(stack: ^frame_stack, err: ^Scalar_Parse_Error) {
	all_values_retired := true
	remaining := stack.active_count
	block := stack.current
	for block != nil && remaining > 0 {
		frames := frame_block_frames(block)
		limit := min(block.count, remaining)
		for i := limit - 1; i >= 0; i -= 1 {
			cleanup_error := value.destroy_value(&frames[i].pending_value)
			if cleanup_error == nil do cleanup_error = value.destroy_value(&frames[i].pending_key)
			if cleanup_error == nil do cleanup_error = value.destroy_value(&frames[i].array)
			if cleanup_error != nil do all_values_retired = false
		}
		remaining -= limit
		block = block.previous
	}
	if !all_values_retired {
		promote_cleanup_error(err)
		err.cleanup_frame_blocks = stack.blocks
		err.cleanup_frame_current = stack.current
		err.cleanup_frame_count = stack.active_count
		err.cleanup_frame_allocator = stack.allocator
		stack^ = {}
		return
	}
	stack.current = nil
	stack.active_count = 0
	for stack.blocks != nil {
		release_block := stack.blocks
		previous := release_block.previous
		byte_data := cast([^]byte)(rawptr(release_block))
		memory := byte_data[:release_block.byte_count]
		free_error := runtime.mem_free_bytes(memory, stack.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			promote_cleanup_error(err)
			err.cleanup_frame_blocks = release_block
			err.cleanup_frame_allocator = stack.allocator
			stack^ = {}
			return
		}
		stack.blocks = previous
	}
	stack^ = {}
}

@(private)
retain_failed_value :: proc(owner: ^value.Value, err: ^Scalar_Parse_Error) {
	cleanup_error := value.destroy_value(owner)
	if cleanup_error != nil {
		promote_cleanup_error(err)
		err.cleanup_value = value.take_value(owner)
	}
}

@(private)
retain_array_error :: proc(
	array_error: ^value.Array_Operation_Error,
	err: ^Scalar_Parse_Error,
) {
	if value.array_error_needs_cleanup(array_error) {
		promote_cleanup_error(err)
		err.cleanup_array_error = value.take_array_error(array_error)
	} else {
		_ = value.destroy_array_error(array_error)
	}
}

@(private)
object_failure_kind :: proc(err: ^value.Object_Operation_Error) -> Scalar_Parse_Error_Kind {
	switch value.object_error_kind(err) {
	case .Out_Of_Memory, .Allocator_Unsupported:
		return .Allocation_Failure
	case .Size_Overflow:
		return .Size_Overflow
	case .None:
		return .None
	case .Wrong_Kind, .Aliased_Operand, .Cleanup_Failed:
		return .Object_Operation_Failure
	}
	return .Object_Operation_Failure
}

@(private)
retain_object_error :: proc(
	object_error: ^value.Object_Operation_Error,
	err: ^Scalar_Parse_Error,
) {
	if value.object_error_needs_cleanup(object_error) {
		promote_cleanup_error(err)
		err.cleanup_object_error = value.take_object_error(object_error)
	} else {
		_ = value.destroy_object_error(object_error)
	}
}

@(private)
set_object_member :: proc(frame: ^array_parse_frame, offset: int) -> Scalar_Parse_Error {
	duplicate_key, displaced, object_error := value.object_set_take(
		&frame.array,
		&frame.pending_key,
		&frame.pending_value,
	)
	if value.object_error_kind(&object_error) != .None {
		err := Scalar_Parse_Error{
			kind = object_failure_kind(&object_error),
			detection_offset = offset,
			cause_offset = offset,
			has_cause_offset = true,
		}
		retain_object_error(&object_error, &err)
		return err
	}
	frame.pending_key = value.take_value(&duplicate_key)
	frame.pending_value = value.take_value(&displaced)
	err := Scalar_Parse_Error{}
	key_cleanup := value.destroy_value(&frame.pending_key)
	value_cleanup := value.destroy_value(&frame.pending_value)
	if key_cleanup != nil || value_cleanup != nil {
		err = {
			kind = .Scratch_Cleanup_Failure,
			detection_offset = offset,
			cause_offset = offset,
			has_cause_offset = true,
			cause_kind = .Object_Operation_Failure,
		}
	}
	return err
}

@(private)
append_array_element :: proc(
	array: ^value.Value,
	element: ^value.Value,
	offset: int,
) -> Scalar_Parse_Error {
	displaced, append_error := value.array_append_take(array, element)
	if value.array_error_kind(&append_error) != .None {
		err := Scalar_Parse_Error{
			kind = array_failure_kind(&append_error),
			detection_offset = offset,
			cause_offset = offset,
			has_cause_offset = true,
		}
		retain_array_error(&append_error, &err)
		retain_failed_value(element, &err)
		return err
	}
	if value.kind_of(&displaced) != .Invalid {
		err := Scalar_Parse_Error{
			kind = .Array_Operation_Failure,
			detection_offset = offset,
			cause_offset = offset,
			has_cause_offset = true,
		}
		retain_failed_value(&displaced, &err)
		return err
	}
	return {}
}

@(private)
new_container :: proc(kind: container_kind, allocator: runtime.Allocator) -> (
	result: value.Value,
	err: Scalar_Parse_Error,
) {
	switch kind {
	case .Array:
		array_error: value.Array_Operation_Error
		result, array_error = value.array_value(allocator)
		if value.array_error_kind(&array_error) != .None {
			err.kind = array_failure_kind(&array_error)
			retain_array_error(&array_error, &err)
		}
	case .Object:
		object_error: value.Object_Operation_Error
		result, object_error = value.object_value(allocator)
		if value.object_error_kind(&object_error) != .None {
			err.kind = object_failure_kind(&object_error)
			retain_object_error(&object_error, &err)
		}
	}
	return
}

@(private)
attach_container_value :: proc(
	frame: ^array_parse_frame,
	member: ^value.Value,
	offset: int,
) -> Scalar_Parse_Error {
	if frame.kind == .Array {
		err := append_array_element(&frame.array, member, offset)
		if err.kind == .None {
			frame.expect_value = false
			frame.after_comma = false
		}
		return err
	}
	switch frame.object_phase {
	case .Key:
		frame.pending_key = value.take_value(member)
		frame.object_phase = .Colon
		frame.after_comma = false
		return {}
	case .Value:
		frame.pending_value = value.take_value(member)
		frame.object_phase = .Separator
		return {}
	case .Colon, .Separator:
		return {
			kind = .Expected_Separator,
			detection_offset = offset,
			cause_offset = offset,
			has_cause_offset = true,
		}
	}
	return {}
}

// parse_container_at uses one Odin frame per active array or object, while
// syntactic_entries mirrors jq's ordinary-parser stackpos. A consumed opener
// charges one entry and is the only transition guarded by MAX_PARSING_DEPTH.
// A validated object key charges a second entry when its colon is consumed,
// even when that moves the count from 10,000 to 10,001. That key entry is
// released when comma or close transfers it into the object. Closing then
// releases the container entry. This live syntactic counter is not the count
// or capacity of the linked frame blocks.
//
// Frame blocks still grow only when an actually reachable, budgeted opener
// needs another frame. The depth failure is selected before constructing the
// offending Value, growing a block, or transferring it into a frame. Bytes
// beyond a completed root or decisive grammar error are never inspected for
// either budget or capacity; checked block arithmetic and allocator failures
// remain independent safeguards.
@(private)
parse_container_at :: proc(input: string, start: int, allocator: runtime.Allocator) -> (
	result: value.Value,
	next: int,
	err: Scalar_Parse_Error,
) {
	frames := frame_stack{allocator = context.temp_allocator}
	syntactic_entries := 1 // The reachable root opener consumes one jq entry.
	root_kind := container_kind.Array
	if input[start] == '{' do root_kind = .Object

	err = grow_frame_stack(&frames, start)
	if err.kind != .None {
		return value.invalid_value(), start, err
	}
	root, root_error := new_container(root_kind, allocator)
	if root_error.kind != .None {
		err = take_scalar_parse_error(&root_error)
		err.detection_offset = start
		err.cause_offset = start
		err.has_cause_offset = true
		retire_frame_stack(&frames, &err)
		return value.invalid_value(), start, err
	}
	push_error := push_container_frame(&frames, &root, start, root_kind)
	if push_error.kind != .None {
		err = take_scalar_parse_error(&push_error)
		retain_failed_value(&root, &err)
		retire_frame_stack(&frames, &err)
		return value.invalid_value(), start, err
	}

	i := start + 1
	for {
		for i < len(input) && is_whitespace(input[i]) do i += 1
		frame := frame_stack_top(&frames)
		if i == len(input) {
			kind := Scalar_Parse_Error_Kind.Unfinished_Array
			if frame.kind == .Object do kind = .Unfinished_Object
			err = {
				kind = kind,
				detection_offset = detection_before_eof(len(input)),
				cause_offset = len(input),
				has_cause_offset = true,
			}
			retire_frame_stack(&frames, &err)
			return value.invalid_value(), i, err
		}

		c := input[i]
		// jq checks its parser-stack limit on an opener before checking whether
		// a pending value instead requires a separator (jv_parse.c:156-168).
		if (c == '[' || c == '{') && syntactic_entries >= MAX_PARSING_DEPTH {
			err = {
				kind = .Depth_Limit,
				detection_offset = i,
				cause_offset = i,
				has_cause_offset = true,
			}
			retire_frame_stack(&frames, &err)
			return value.invalid_value(), i, err
		}
		close_frame := false
		if frame.kind == .Array {
			if frame.expect_value {
				switch c {
				case ']':
					length, _ := value.array_length(&frame.array)
					if frame.after_comma || length != 0 {
						err = {kind = .Expected_Array_Element, detection_offset = i, cause_offset = i, has_cause_offset = true}
					}
					close_frame = err.kind == .None
				case ',': err = {kind = .Expected_Value_Before_Separator, detection_offset = i, cause_offset = i, has_cause_offset = true}
				case '}': err = {kind = .Unmatched_Object_Closer, detection_offset = i, cause_offset = i, has_cause_offset = true}
				case ':': err = {kind = .Expected_String_Key_Before_Colon, detection_offset = i, cause_offset = i, has_cause_offset = true}
				}
			} else {
				switch c {
				case ']': close_frame = true
				case ',':
					frame.expect_value = true
					frame.after_comma = true
					i += 1
					continue
				case '}': err = {kind = .Object_Key_Value_Pairs_Required, detection_offset = i, cause_offset = i, has_cause_offset = true}
				case ':': err = {kind = .Unexpected_Colon, detection_offset = i, cause_offset = i, has_cause_offset = true}
				}
			}
		} else {
			switch frame.object_phase {
			case .Key:
				switch c {
				case '}':
					length, _ := value.object_length(&frame.array)
					if frame.after_comma || length != 0 {
						err = {kind = .Expected_Object_Member, detection_offset = i, cause_offset = i, has_cause_offset = true}
					} else {
						close_frame = true
					}
				case ']': err = {kind = .Unmatched_Array_Closer, detection_offset = i, cause_offset = i, has_cause_offset = true}
				case ',': err = {kind = .Expected_Value_Before_Separator, detection_offset = i, cause_offset = i, has_cause_offset = true}
				case ':': err = {kind = .Expected_String_Key_Before_Colon, detection_offset = i, cause_offset = i, has_cause_offset = true}
				}
			case .Colon:
				switch c {
				case ':':
					if value.kind_of(&frame.pending_key) != .String {
						err = {kind = .Object_Keys_Must_Be_Strings, detection_offset = i, cause_offset = i, has_cause_offset = true}
					} else {
						// jq does not depth-check this push. A colon can move
						// stackpos from 10,000 to 10,001 (jv_parse.c:170-179).
						syntactic_entries += 1
						frame.object_phase = .Value
						i += 1
						continue
					}
				case '}', ',': err = {kind = .Object_Key_Value_Pairs_Required, detection_offset = i, cause_offset = i, has_cause_offset = true}
				case ']': err = {kind = .Unmatched_Array_Closer, detection_offset = i, cause_offset = i, has_cause_offset = true}
				}
			case .Value:
				switch c {
				case '}': err = {kind = .Unmatched_Object_Closer, detection_offset = i, cause_offset = i, has_cause_offset = true}
				case ']': err = {kind = .Unmatched_Array_Closer, detection_offset = i, cause_offset = i, has_cause_offset = true}
				case ',': err = {kind = .Expected_Value_Before_Separator, detection_offset = i, cause_offset = i, has_cause_offset = true}
				case ':': err = {kind = .Expected_String_Key_Before_Colon, detection_offset = i, cause_offset = i, has_cause_offset = true}
				}
			case .Separator:
				switch c {
				case '}':
					err = set_object_member(frame, i)
					close_frame = err.kind == .None
				case ']': err = {kind = .Unmatched_Array_Closer, detection_offset = i, cause_offset = i, has_cause_offset = true}
				case ',':
					err = set_object_member(frame, i)
					if err.kind == .None {
						syntactic_entries -= 1 // pending key transferred
						frame.object_phase = .Key
						frame.after_comma = true
						i += 1
						continue
					}
				case ':': err = {kind = .Unexpected_Colon, detection_offset = i, cause_offset = i, has_cause_offset = true}
				}
			}
		}

		if err.kind != .None {
			retire_frame_stack(&frames, &err)
			return value.invalid_value(), i, err
		}
		if close_frame {
			i += 1
			completed_open := frame.open_offset
			if frame.kind == .Object && frame.object_phase == .Separator {
				syntactic_entries -= 1 // pending key transferred on close
			}
			syntactic_entries -= 1 // completed container
			completed := value.take_value(&frame.array)
			frame_stack_pop(&frames)
			if frames.active_count == 0 {
				retire_frame_stack(&frames, &err)
				if err.kind != .None {
					err.cleanup_value = value.take_value(&completed)
					return value.invalid_value(), i, err
				}
				return completed, i, {}
			}
			attach_error := attach_container_value(frame_stack_top(&frames), &completed, completed_open)
			if attach_error.kind != .None {
				err = take_scalar_parse_error(&attach_error)
				restore_error := push_container_frame(&frames, &completed, completed_open, frame.kind)
				if restore_error.kind != .None {
					retain_failed_value(&completed, &err)
				}
				retire_frame_stack(&frames, &err)
				return value.invalid_value(), i, err
			}
			continue
		}

		// Any unhandled structural byte is either a new nested value or a
		// separator conflict. Scalars are fully scanned before that conflict is
		// reported, matching jq's detection cursor.
		expecting_member := frame.kind == .Array && frame.expect_value ||
			frame.kind == .Object && (frame.object_phase == .Key || frame.object_phase == .Value)
		if !expecting_member {
			second_at := i
			if c == '[' || c == '{' {
				err = {kind = .Expected_Separator, detection_offset = i, cause_offset = i, has_cause_offset = true}
			} else {
				second: value.Value
				second, i, err = parse_scalar_at(input, second_at, allocator)
				if err.kind == .None {
					detection := literal_detection_offset(input, i)
					if input[second_at] == '"' do detection = i - 1
					err = {kind = .Expected_Separator, detection_offset = detection, cause_offset = second_at, has_cause_offset = true}
					retain_failed_value(&second, &err)
				}
			}
			retire_frame_stack(&frames, &err)
			return value.invalid_value(), i, err
		}

		member_at := i
		if c == '[' || c == '{' {
			child_kind := container_kind.Array
			if c == '{' do child_kind = .Object
			// The opener limit was checked above, before any allocation.
			syntactic_entries += 1
			child, child_error := new_container(child_kind, allocator)
			if child_error.kind != .None {
				err = take_scalar_parse_error(&child_error)
				err.detection_offset = i
				err.cause_offset = i
				err.has_cause_offset = true
				retire_frame_stack(&frames, &err)
				return value.invalid_value(), i, err
			}
			frame_error := push_container_frame(&frames, &child, i, child_kind)
			if frame_error.kind != .None {
				err = take_scalar_parse_error(&frame_error)
				retain_failed_value(&child, &err)
				retire_frame_stack(&frames, &err)
				return value.invalid_value(), i, err
			}
			i += 1
			continue
		}

		member: value.Value
		member, i, err = parse_scalar_at(input, i, allocator)
		if err.kind != .None {
			retire_frame_stack(&frames, &err)
			return value.invalid_value(), i, err
		}
		attach_error := attach_container_value(frame, &member, member_at)
		if attach_error.kind != .None {
			err = take_scalar_parse_error(&attach_error)
			retain_failed_value(&member, &err)
			retire_frame_stack(&frames, &err)
			return value.invalid_value(), i, err
		}
	}
}

@(private)
parse_one_value_at :: proc(input: string, start: int, allocator: runtime.Allocator) -> (
	result: value.Value,
	next: int,
	err: Scalar_Parse_Error,
) {
	switch input[start] {
	case '[', '{':
		return parse_container_at(input, start, allocator)
	case ']':
		result, err = parse_failure(.Unmatched_Array_Closer, start)
	case '}':
		result, err = parse_failure(.Unmatched_Object_Closer, start)
	case ',':
		result, err = parse_failure(.Expected_Value_Before_Separator, start)
	case ':':
		result, err = parse_failure(.Expected_String_Key_Before_Colon, start)
	case:
		return parse_scalar_at(input, start, allocator)
	}
	return result, start, err
}

// parse_value is jq's one-shot wrapper above the single-result parser. A
// second valid result is an extra-value error, while a later syntax or
// unsupported-object error supersedes the already completed first value.
parse_value :: proc(input: string, allocator: runtime.Allocator) -> (
	result: value.Value,
	err: Scalar_Parse_Error,
) {
	i := 0
	if len(input) > 0 && input[0] == 0xef {
		bom := [3]byte{0xef, 0xbb, 0xbf}
		matched := 1
		for matched < len(bom) && matched < len(input) && input[matched] == bom[matched] {
			matched += 1
		}
		if matched != len(bom) {
			return parse_scalar(input, allocator)
		}
		i = len(bom)
	}
	for i < len(input) && is_whitespace(input[i]) {
		i += 1
	}
	if i == len(input) {
		return parse_detected_failure(
			.Expected_Value,
			detection_before_eof(len(input)),
			len(input),
		)
	}
	result, i, err = parse_one_value_at(input, i, allocator)
	if err.kind != .None {
		return value.invalid_value(), err
	}
	for i < len(input) && is_whitespace(input[i]) {
		i += 1
	}
	if i == len(input) {
		return result, {}
	}

	second_at := i
	cleanup_error := value.destroy_value(&result)
	if cleanup_error != nil {
		return value.invalid_value(), {
			kind = .Scratch_Cleanup_Failure,
			detection_offset = second_at,
			cause_offset = second_at,
			has_cause_offset = true,
			cause_kind = .Unexpected_Extra_Values,
			cleanup_value = value.take_value(&result),
		}
	}
	second: value.Value
	second, _, err = parse_one_value_at(input, second_at, allocator)
	if err.kind != .None {
		return value.invalid_value(), err
	}
	err = {
		kind = .Unexpected_Extra_Values,
		detection_offset = second_at,
		cause_offset = second_at,
		has_cause_offset = true,
	}
	retain_failed_value(&second, &err)
	return value.invalid_value(), err
}
