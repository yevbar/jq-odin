package json

import "base:runtime"
import "core:math"
import "core:strconv"
import "jq:value"

@(private)
MAX_COMPACT_PRINT_DEPTH :: 256

@(private)
COMPACT_DEPTH_MARKER :: "<skipped: too deep>"

Compact_Error_Kind :: enum u8 {
	None,
	Invalid_Serializer_Owner,
	Invalid_Result_Owner,
	Invalid_Value,
	Invalid_UTF8,
	Value_Access_Failure,
	Out_Of_Memory,
	Size_Overflow,
	Cleanup_Failed,
}

Compact_Error :: struct {
	kind:       Compact_Error_Kind,
	value_kind: value.Kind,
}

@(private)
compact_owner_state :: enum u8 {
	Invalid,
	Ready,
	Cleanup_Required,
}

@(private)
compact_frame_kind :: enum u8 {
	Value,
	Array,
	Object,
}

@(private)
compact_frame :: struct {
	node:       value.Value,
	kind:       compact_frame_kind,
	index:      int,
	length:     int,
	iterator:   value.Object_Iterator,
	started:    bool,
	depth:      int,
}

// Compact_Serializer is an address-bound owner initialized by
// init_compact_serializer. It may be reused after successful calls and after
// failures that leave it Ready. Cleanup_Required rejects serialization until
// destroy_compact_serializer succeeds. Ordinary assignment creates an invalid
// copy: use the original address until destruction makes it inert. A failed
// destroy is retryable.
Compact_Serializer :: struct {
	owner:          rawptr,
	state:          compact_owner_state,
	allocator:      runtime.Allocator,
	output_memory:  []byte,
	output_length:  int,
	frame_memory:   []byte,
	frames:         []compact_frame,
	frame_count:    int,
	cleanup_memory: []byte,
}

// Compact_Result is an address-bound owner containing length-delimited JSON.
// compact_result_bytes returns a borrowed view valid until take or destroy.
// The caller must call destroy_compact_result with the same live allocator.
// Ordinary assignment creates an invalid non-owner; use take_compact_result
// to move ownership to a different address. A failed destroy is retryable.
Compact_Result :: struct {
	owner:      rawptr,
	state:      compact_owner_state,
	allocator:  runtime.Allocator,
	memory:     []byte,
	byte_count: int,
}

// Pretty_Serializer and Pretty_Result deliberately mirror the compact owner
// layouts so both public modes use the same bounded traversal and cleanup
// implementation. They remain distinct types, preventing a result or owner
// from being passed to the other mode accidentally.
Pretty_Serializer :: distinct Compact_Serializer
Pretty_Result :: distinct Compact_Result

@(private)
serializer_valid :: proc(serializer: ^Compact_Serializer) -> bool {
	return serializer != nil && serializer.owner == rawptr(serializer) &&
	       serializer.state != .Invalid
}

@(private)
result_valid :: proc(result: ^Compact_Result) -> bool {
	return result != nil && result.owner == rawptr(result) && result.state != .Invalid
}

init_compact_serializer :: proc(
	serializer: ^Compact_Serializer,
	allocator: runtime.Allocator,
) -> bool {
	if serializer == nil || serializer.state != .Invalid || serializer.owner != nil {
		return false
	}
	serializer.owner = rawptr(serializer)
	serializer.state = .Ready
	serializer.allocator = allocator
	return true
}

compact_result_bytes :: proc(result: ^Compact_Result) -> (string, bool) {
	if !result_valid(result) ||
	   result.byte_count < 0 || result.byte_count > len(result.memory) {
		return "", false
	}
	if result.byte_count == 0 do return "", true
	return transmute(string)result.memory[:result.byte_count], true
}

take_compact_result :: proc(
	destination, source: ^Compact_Result,
) -> Compact_Error_Kind {
	if destination == nil || source == nil || destination == source ||
	   destination.owner != nil || destination.state != .Invalid {
		return .Invalid_Result_Owner
	}
	if !result_valid(source) || source.state != .Ready {
		return .Invalid_Result_Owner
	}
	destination^ = source^
	destination.owner = rawptr(destination)
	source^ = {}
	return .None
}

destroy_compact_result :: proc(result: ^Compact_Result) -> runtime.Allocator_Error {
	if result == nil || result.state == .Invalid && result.owner == nil do return nil
	if !result_valid(result) do return .Invalid_Pointer
	if len(result.memory) > 0 {
		err := runtime.mem_free_bytes(result.memory, result.allocator)
		if err != nil && err != .Mode_Not_Implemented {
			result.state = .Cleanup_Required
			return err
		}
	}
	result^ = {}
	return nil
}

@(private)
retire_serializer_memory :: proc(memory: ^[]byte, allocator: runtime.Allocator) -> runtime.Allocator_Error {
	if len(memory^) == 0 do return nil
	err := runtime.mem_free_bytes(memory^, allocator)
	if err == nil || err == .Mode_Not_Implemented {
		memory^ = nil
		return nil
	}
	return err
}

@(private)
clear_serializer_frames :: proc(serializer: ^Compact_Serializer) -> runtime.Allocator_Error {
	for serializer.frame_count > 0 {
		at := serializer.frame_count - 1
		err := value.destroy_value(&serializer.frames[at].node)
		if err != nil do return err
		serializer.frames[at] = {}
		serializer.frame_count = at
	}
	return nil
}

destroy_compact_serializer :: proc(serializer: ^Compact_Serializer) -> runtime.Allocator_Error {
	if serializer == nil || serializer.state == .Invalid && serializer.owner == nil do return nil
	if !serializer_valid(serializer) do return .Invalid_Pointer
	first_error := clear_serializer_frames(serializer)
	if serializer.frame_count == 0 {
		err := retire_serializer_memory(&serializer.frame_memory, serializer.allocator)
		if first_error == nil && err != nil do first_error = err
		if len(serializer.frame_memory) == 0 do serializer.frames = nil
	}
	err := retire_serializer_memory(&serializer.output_memory, serializer.allocator)
	if first_error == nil && err != nil do first_error = err
	err = retire_serializer_memory(&serializer.cleanup_memory, serializer.allocator)
	if first_error == nil && err != nil do first_error = err
	if first_error != nil {
		serializer.state = .Cleanup_Required
		return first_error
	}
	serializer^ = {}
	return nil
}

@(private)
allocation_failure :: proc(serializer: ^Compact_Serializer, memory: []byte) -> Compact_Error {
	if len(memory) > 0 {
		err := runtime.mem_free_bytes(memory, serializer.allocator)
		if err != nil && err != .Mode_Not_Implemented {
			serializer.cleanup_memory = memory
			serializer.state = .Cleanup_Required
			return {kind = .Cleanup_Failed}
		}
	}
	return {kind = .Out_Of_Memory}
}

@(private)
grow_output :: proc(serializer: ^Compact_Serializer, additional: int) -> Compact_Error {
	if additional < 0 || serializer.output_length > max(int) - additional {
		return {kind = .Size_Overflow}
	}
	required := serializer.output_length + additional
	if required <= len(serializer.output_memory) do return {}
	capacity := max(len(serializer.output_memory), 256)
	for capacity < required {
		if capacity > max(int) - capacity / 2 {
			capacity = required
			break
		}
		capacity += capacity / 2
	}
	memory, alloc_error := runtime.mem_alloc(capacity, align_of(uintptr), serializer.allocator)
	if alloc_error != nil || len(memory) != capacity {
		return allocation_failure(serializer, memory)
	}
	if serializer.output_length > 0 {
		copy(memory[:serializer.output_length], serializer.output_memory[:serializer.output_length])
	}
	if len(serializer.output_memory) > 0 {
		free_error := runtime.mem_free_bytes(serializer.output_memory, serializer.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			serializer.cleanup_memory = memory
			serializer.state = .Cleanup_Required
			return {kind = .Cleanup_Failed}
		}
	}
	serializer.output_memory = memory
	return {}
}

@(private)
append_bytes :: proc(serializer: ^Compact_Serializer, bytes: string) -> Compact_Error {
	err := grow_output(serializer, len(bytes))
	if err.kind != .None do return err
	copy(serializer.output_memory[serializer.output_length:], transmute([]byte)bytes)
	serializer.output_length += len(bytes)
	return {}
}

@(private)
append_byte :: proc(serializer: ^Compact_Serializer, byte_value: byte) -> Compact_Error {
	err := grow_output(serializer, 1)
	if err.kind != .None do return err
	serializer.output_memory[serializer.output_length] = byte_value
	serializer.output_length += 1
	return {}
}

@(private)
append_pretty_indent :: proc(serializer: ^Compact_Serializer, depth: int) -> Compact_Error {
	if depth < 0 || depth > max(int) / 2 do return {kind = .Size_Overflow}
	err := append_byte(serializer, '\n')
	if err.kind != .None do return err
	for _ in 0..<depth * 2 {
		err = append_byte(serializer, ' ')
		if err.kind != .None do return err
	}
	return {}
}

@(private)
grow_frames :: proc(serializer: ^Compact_Serializer, required: int) -> Compact_Error {
	if required < 0 do return {kind = .Size_Overflow}
	if required <= len(serializer.frames) do return {}
	capacity := max(len(serializer.frames), 16)
	for capacity < required {
		if capacity > max(int) - capacity / 2 {
			capacity = required
			break
		}
		capacity += capacity / 2
	}
	if capacity > max(int) / int(size_of(compact_frame)) {
		return {kind = .Size_Overflow}
	}
	byte_count := capacity * int(size_of(compact_frame))
	memory, alloc_error := runtime.mem_alloc(byte_count, align_of(compact_frame), serializer.allocator)
	if alloc_error != nil || len(memory) != byte_count {
		return allocation_failure(serializer, memory)
	}
	frames := (cast([^]compact_frame)(raw_data(memory)))[:capacity]
	for i in 0..<serializer.frame_count do frames[i] = serializer.frames[i]
	if len(serializer.frame_memory) > 0 {
		free_error := runtime.mem_free_bytes(serializer.frame_memory, serializer.allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			serializer.cleanup_memory = memory
			serializer.state = .Cleanup_Required
			return {kind = .Cleanup_Failed}
		}
	}
	serializer.frame_memory = memory
	serializer.frames = frames
	return {}
}

@(private)
strict_utf8_width :: proc(bytes: string, at: int) -> (int, bool) {
	c := bytes[at]
	if c < 0x80 do return 1, true
	width := 0
	minimum := u32(0)
	codepoint := u32(0)
	switch {
	case c >= 0xc2 && c <= 0xdf: width, minimum, codepoint = 2, 0x80, u32(c & 0x1f)
	case c >= 0xe0 && c <= 0xef: width, minimum, codepoint = 3, 0x800, u32(c & 0x0f)
	case c >= 0xf0 && c <= 0xf4: width, minimum, codepoint = 4, 0x10000, u32(c & 0x07)
	case: return 0, false
	}
	if len(bytes) - at < width do return 0, false
	for i in 1..<width {
		continuation := bytes[at + i]
		if continuation < 0x80 || continuation > 0xbf do return 0, false
		codepoint = codepoint << 6 | u32(continuation & 0x3f)
	}
	if codepoint < minimum || codepoint > 0x10ffff ||
	   codepoint >= 0xd800 && codepoint <= 0xdfff {
		return 0, false
	}
	return width, true
}

@(private)
append_hex_control :: proc(serializer: ^Compact_Serializer, c: byte) -> Compact_Error {
	digits := "0123456789abcdef"
	encoded := [6]byte{'\\', 'u', '0', '0', digits[c >> 4], digits[c & 0xf]}
	return append_bytes(serializer, transmute(string)encoded[:])
}

@(private)
append_quoted :: proc(serializer: ^Compact_Serializer, bytes: string) -> Compact_Error {
	err := append_byte(serializer, '"')
	if err.kind != .None do return err
	i := 0
	for i < len(bytes) {
		c := bytes[i]
		if c >= 0x80 {
			width, ok := strict_utf8_width(bytes, i)
			if !ok do return {kind = .Invalid_UTF8, value_kind = .String}
			err = append_bytes(serializer, bytes[i:i + width])
			if err.kind != .None do return err
			i += width
			continue
		}
		switch c {
		case '"': err = append_bytes(serializer, `\"`)
		case '\\': err = append_bytes(serializer, `\\`)
		case '\b': err = append_bytes(serializer, `\b`)
		case '\t': err = append_bytes(serializer, `\t`)
		case '\n': err = append_bytes(serializer, `\n`)
		case '\f': err = append_bytes(serializer, `\f`)
		case '\r': err = append_bytes(serializer, `\r`)
		case:
			if c < 0x20 || c == 0x7f {
				err = append_hex_control(serializer, c)
			} else {
				err = append_byte(serializer, c)
			}
		}
		if err.kind != .None do return err
		i += 1
	}
	return append_byte(serializer, '"')
}

@(private)
saturating_decimal_exponent :: proc(bytes: string) -> i64 {
	LIMIT :: i64(1_999_999_998)
	result := i64(0)
	for c in bytes {
		digit := i64(c - '0')
		if result <= (LIMIT - digit) / 10 {
			result = result * 10 + digit
		} else {
			return LIMIT
		}
	}
	return result
}

@(private)
append_i64 :: proc(serializer: ^Compact_Serializer, number: i64, force_plus := false) -> Compact_Error {
	buffer: [32]byte
	written := strconv.write_int(buffer[:], number, 10)
	if force_plus && number >= 0 {
		err := append_byte(serializer, '+')
		if err.kind != .None do return err
	}
	return append_bytes(serializer, written)
}

@(private)
append_literal_number_with_context :: proc(
	serializer: ^Compact_Serializer,
	literal: string,
	precision, etiny, emax: i64,
) -> Compact_Error {
	i := 0
	negative := false
	if literal[i] == '+' || literal[i] == '-' {
		negative = literal[i] == '-'
		i += 1
	}
	// The decimal context permits huge coefficients. Borrow digit runs from the
	// retained spelling rather than creating coefficient-sized stack storage.
	mantissa_start := i
	dot_at := -1
	exponent_at := len(literal)
	for i < len(literal) {
		if literal[i] == '.' do dot_at = i
		if literal[i] == 'e' || literal[i] == 'E' {
			exponent_at = i
			break
		}
		i += 1
	}
	if dot_at < 0 do dot_at = exponent_at
	fraction_digits := exponent_at - dot_at - (1 if dot_at < exponent_at else 0)
	explicit := i64(0)
	if exponent_at < len(literal) {
		exp_at := exponent_at + 1
		exp_negative := false
		if literal[exp_at] == '+' || literal[exp_at] == '-' {
			exp_negative = literal[exp_at] == '-'
			exp_at += 1
		}
		explicit = saturating_decimal_exponent(literal[exp_at:])
		if exp_negative do explicit = -explicit
	}
	exponent := explicit - i64(fraction_digits)
	first_digit := mantissa_start
	for first_digit < exponent_at &&
	    (literal[first_digit] == '0' || literal[first_digit] == '.') {
		first_digit += 1
	}
	all_zero := first_digit == exponent_at
	if all_zero {
		first_digit = mantissa_start
		for literal[first_digit] == '.' do first_digit += 1
	}
	digit_count := 0
	if all_zero {
		digit_count = 1
	} else {
		for at in first_digit..<exponent_at {
			if literal[at] != '.' do digit_count += 1
		}
	}
	adjusted := exponent + i64(digit_count) - 1
	if all_zero {
		if exponent > emax do exponent = emax
		if exponent < etiny do exponent = etiny
		adjusted = exponent
	}
	// Reproduce the public literal constructor's decimal-context rounding at
	// the precision/ETINY boundary. Its retained input spelling alone is not
	// already the printable coefficient.
	precision_discard := max(i64(digit_count) - precision, i64(0))
	etiny_discard := max(etiny - exponent, i64(0))
	discard := precision_discard
	if etiny_discard > discard do discard = etiny_discard
	if !all_zero && discard > 0 {
		keep := i64(digit_count) - discard
		first_discarded := byte('0')
		kept := i64(0)
		all_kept_nines := keep > 0
		for at in first_digit..<exponent_at {
			if literal[at] == '.' do continue
			if kept < keep {
				if literal[at] != '9' do all_kept_nines = false
				kept += 1
			} else if kept == keep {
				first_discarded = literal[at]
				break
			}
		}
		round_up := first_discarded >= '5'
		rounded_exponent := exponent + discard
		rounded_digits := max(keep, i64(1))
		if keep <= 0 {
			rounded_exponent = etiny
		} else if round_up && all_kept_nines {
			rounded_exponent += 1
			// decSetSubnormal restores Etiny after an all-nines carry by
			// shifting the rounded coefficient left one decimal place.
			if etiny_discard > precision_discard {
				rounded_digits += 1
				rounded_exponent -= 1
			}
		}
		rounded_adjusted := rounded_exponent + rounded_digits - 1
		if rounded_adjusted > emax {
			return append_native_number(
				serializer,
				math.inf_f64(-1) if negative else math.inf_f64(1),
			)
		}
		use_scientific := rounded_exponent > 0 || rounded_adjusted < -6

		if negative {
			err := append_byte(serializer, '-')
			if err.kind != .None do return err
		}
		coefficient_start := serializer.output_length
		decimal_point := rounded_digits + rounded_exponent
		if !use_scientific && decimal_point <= 0 {
			err := append_bytes(serializer, "0.")
			if err.kind != .None do return err
			for _ in i64(0)..<-decimal_point {
				err = append_byte(serializer, '0')
				if err.kind != .None do return err
			}
			coefficient_start = serializer.output_length
		}
		emitted := i64(0)
		if keep <= 0 {
			digit := byte('1') if keep == 0 && round_up else byte('0')
			err := append_byte(serializer, digit)
			if err.kind != .None do return err
			emitted = 1
		} else {
			for at in first_digit..<exponent_at {
				if literal[at] == '.' do continue
				if emitted == keep do break
				if use_scientific && emitted == 1 ||
				   !use_scientific && decimal_point > 0 && emitted == decimal_point {
					err := append_byte(serializer, '.')
					if err.kind != .None do return err
				}
				err := append_byte(serializer, literal[at])
				if err.kind != .None do return err
				emitted += 1
			}
		}
		if round_up && keep > 0 {
			for at := serializer.output_length - 1; at >= coefficient_start; at -= 1 {
				if serializer.output_memory[at] == '.' do continue
				if serializer.output_memory[at] != '9' {
					serializer.output_memory[at] += 1
					break
				}
				serializer.output_memory[at] = '0'
				if at == coefficient_start {
					serializer.output_memory[at] = '1'
				}
			}
		}
		for emitted < rounded_digits {
			if use_scientific && emitted == 1 ||
			   !use_scientific && decimal_point > 0 && emitted == decimal_point {
				err := append_byte(serializer, '.')
				if err.kind != .None do return err
			}
			err := append_byte(serializer, '0')
			if err.kind != .None do return err
			emitted += 1
		}
		if use_scientific {
			err := append_byte(serializer, 'E')
			if err.kind != .None do return err
			return append_i64(serializer, rounded_adjusted, true)
		}
		return {}
	}
	if !all_zero && adjusted > emax {
		return append_native_number(
			serializer,
			math.inf_f64(-1) if negative else math.inf_f64(1),
		)
	}
	if negative {
		err := append_byte(serializer, '-')
		if err.kind != .None do return err
	}
	if exponent > 0 || adjusted < -6 {
		emitted := 0
		for at in first_digit..<exponent_at {
			if literal[at] == '.' do continue
			if all_zero && emitted == 1 do break
			if emitted == 1 {
				err := append_byte(serializer, '.')
				if err.kind != .None do return err
			}
			err := append_byte(serializer, literal[at])
			if err.kind != .None do return err
			emitted += 1
		}
		err := append_byte(serializer, 'E')
		if err.kind != .None do return err
		return append_i64(serializer, adjusted, true)
	}
	decimal_point := i64(digit_count) + exponent
	if decimal_point <= 0 {
		err := append_bytes(serializer, "0.")
		if err.kind != .None do return err
		for _ in i64(0)..<-decimal_point {
			err = append_byte(serializer, '0')
			if err.kind != .None do return err
		}
	}
	emitted := i64(0)
	for at in first_digit..<exponent_at {
		if literal[at] == '.' do continue
		if all_zero && emitted == 1 do break
		if decimal_point > 0 && emitted == decimal_point {
			err := append_byte(serializer, '.')
			if err.kind != .None do return err
		}
		err := append_byte(serializer, literal[at])
		if err.kind != .None do return err
		emitted += 1
	}
	for emitted < decimal_point {
		err := append_byte(serializer, '0')
		if err.kind != .None do return err
		emitted += 1
	}
	return {}
}

// append_literal_number implements decNumberToString's plain/scientific
// choice for the retained jq literal representation. The Value constructor
// has already validated the spelling and applied the pinned decimal context.
@(private)
append_literal_number :: proc(serializer: ^Compact_Serializer, literal: string) -> Compact_Error {
	return append_literal_number_with_context(
		serializer,
		literal,
		147_483_648,
		-1_147_483_646,
		999_999_999,
	)
}

@(private)
append_native_number :: proc(serializer: ^Compact_Serializer, number: f64) -> Compact_Error {
	n := number
	if math.is_nan(n) do return append_bytes(serializer, "null")
	if math.is_inf(n) {
		n = -max(f64) if n < 0 else max(f64)
	}
	buffer: [64]byte
	scientific := strconv.write_float(buffer[:], n, 'e', -1, 64)
	at := 0
	if scientific[at] == '+' do at += 1
	negative := false
	if scientific[at] == '-' {
		negative = true
		at += 1
	}
	e_at := at
	for scientific[e_at] != 'e' do e_at += 1
	digits := e_at - at
	if digits > 1 do digits -= 1
	exponent, ok := strconv.parse_i64(scientific[e_at + 1:])
	if !ok do return {kind = .Value_Access_Failure, value_kind = .Number}
	decimal_point := exponent + 1
	use_scientific := decimal_point <= -4 || decimal_point > i64(digits) + 15
	if use_scientific {
		if negative {
			err := append_byte(serializer, '-')
			if err.kind != .None do return err
		}
		err := append_bytes(serializer, scientific[at:e_at])
		if err.kind != .None do return err
		err = append_byte(serializer, 'e')
		if err.kind != .None do return err
		if exponent < 0 {
			err = append_byte(serializer, '-')
			exponent = -exponent
		} else {
			err = append_byte(serializer, '+')
		}
		if err.kind != .None do return err
		if exponent < 10 {
			err = append_byte(serializer, '0')
			if err.kind != .None do return err
		}
		return append_i64(serializer, exponent)
	}
	if negative {
		err := append_byte(serializer, '-')
		if err.kind != .None do return err
	}
	digit_at := at
	written := i64(0)
	if decimal_point <= 0 {
		err := append_bytes(serializer, "0.")
		if err.kind != .None do return err
		for _ in i64(0)..<-decimal_point {
			err = append_byte(serializer, '0')
			if err.kind != .None do return err
		}
	}
	for digit_at < e_at {
		if scientific[digit_at] == '.' {
			digit_at += 1
			continue
		}
		if decimal_point > 0 && written == decimal_point {
			err := append_byte(serializer, '.')
			if err.kind != .None do return err
		}
		err := append_byte(serializer, scientific[digit_at])
		if err.kind != .None do return err
		written += 1
		digit_at += 1
	}
	for written < decimal_point {
		err := append_byte(serializer, '0')
		if err.kind != .None do return err
		written += 1
	}
	return {}
}

@(private)
append_number :: proc(serializer: ^Compact_Serializer, node: ^value.Value) -> Compact_Error {
	if spelling, literal := value.literal_spelling_borrowed(node); literal {
		return append_literal_number(serializer, spelling)
	}
	native, ok := value.number_value_get(node)
	if !ok do return {kind = .Value_Access_Failure, value_kind = .Number}
	return append_native_number(serializer, native)
}

@(private)
finish_compact_failure :: proc(serializer: ^Compact_Serializer, err: Compact_Error) -> Compact_Error {
	cleanup_error := clear_serializer_frames(serializer)
	serializer.output_length = 0
	if cleanup_error != nil || len(serializer.cleanup_memory) > 0 {
		serializer.state = .Cleanup_Required
		return {kind = .Cleanup_Failed, value_kind = err.value_kind}
	}
	return err
}

// Both public layout modes share this ownership and traversal implementation.
// At jq's depth cutoff the representation contains a raw
// <skipped: too deep> marker rather than valid JSON.
@(private)
serialize_json :: proc(
	serializer: ^Compact_Serializer,
	input: ^value.Value,
	result: ^Compact_Result,
	pretty: bool,
) -> Compact_Error {
	if !serializer_valid(serializer) || serializer.state != .Ready {
		return {kind = .Invalid_Serializer_Owner}
	}
	if result == nil || result.owner != nil || result.state != .Invalid {
		return {kind = .Invalid_Result_Owner}
	}
	kind := value.kind_of(input)
	if kind == .Invalid do return {kind = .Invalid_Value, value_kind = kind}
	serializer.output_length = 0
	err := grow_frames(serializer, 1)
	if err.kind != .None do return finish_compact_failure(serializer, err)
	serializer.frames[serializer.frame_count] = {
		node = value.clone_value(input),
		kind = .Value,
	}
	serializer.frame_count += 1
	for serializer.frame_count > 0 {
		// A popped object frame can temporarily require three cleanup owners:
		// its parent frame plus copied key and value. Reserve those slots before
		// popping anything so an allocation failure cannot strand an owner.
		if serializer.frame_count > max(int) - 2 {
			return finish_compact_failure(serializer, {kind = .Size_Overflow})
		}
		err = grow_frames(serializer, serializer.frame_count + 2)
		if err.kind != .None do return finish_compact_failure(serializer, err)
		serializer.frame_count -= 1
		frame := serializer.frames[serializer.frame_count]
		serializer.frames[serializer.frame_count] = {}
		kind = value.kind_of(&frame.node)
		switch frame.kind {
		case .Value:
			if frame.depth > MAX_COMPACT_PRINT_DEPTH {
				err = append_bytes(serializer, COMPACT_DEPTH_MARKER)
				break
			}
			switch kind {
			case .Null: err = append_bytes(serializer, "null")
			case .Boolean:
				boolean, ok := value.boolean_value_get(&frame.node)
				if !ok { err = {kind = .Value_Access_Failure, value_kind = kind} }
				else { err = append_bytes(serializer, "true" if boolean else "false") }
			case .Number: err = append_number(serializer, &frame.node)
			case .String:
				bytes, ok := value.string_borrowed(&frame.node)
				if !ok { err = {kind = .Value_Access_Failure, value_kind = kind} }
				else { err = append_quoted(serializer, bytes) }
			case .Array:
				frame.kind = .Array
				serializer.frames[serializer.frame_count] = frame
				serializer.frame_count += 1
				continue
			case .Object:
				frame.kind = .Object
				frame.iterator = value.object_iterator()
				serializer.frames[serializer.frame_count] = frame
				serializer.frame_count += 1
				continue
			case .Invalid: err = {kind = .Invalid_Value, value_kind = kind}
			}
		case .Array:
			if !frame.started {
				length_ok := false
				frame.length, length_ok = value.array_length(&frame.node)
				if !length_ok {
					err = {kind = .Value_Access_Failure, value_kind = .Array}
				} else {
					err = append_byte(serializer, '[')
				}
				frame.started = true
				if err.kind == .None && frame.length == 0 do err = append_byte(serializer, ']')
			} else if frame.index >= frame.length {
				if pretty do err = append_pretty_indent(serializer, frame.depth)
				if err.kind == .None do err = append_byte(serializer, ']')
			} else {
				if frame.index > 0 do err = append_byte(serializer, ',')
				if err.kind == .None && pretty {
					err = append_pretty_indent(serializer, frame.depth + 1)
				}
				if err.kind == .None {
					child, ok := value.array_element_copy(&frame.node, frame.index)
					if !ok {
						err = {kind = .Value_Access_Failure, value_kind = .Array}
					} else {
						frame.index += 1
						serializer.frames[serializer.frame_count] = frame
						serializer.frame_count += 1
						serializer.frames[serializer.frame_count] = {
							node = child,
							kind = .Value,
							depth = frame.depth + 1,
						}
						serializer.frame_count += 1
						continue
					}
				}
			}
			if err.kind == .None && frame.started && frame.index < frame.length {
				serializer.frames[serializer.frame_count] = frame
				serializer.frame_count += 1
				continue
			}
		case .Object:
			if !frame.started {
				length_ok := false
				frame.length, length_ok = value.object_length(&frame.node)
				if !length_ok {
					err = {kind = .Value_Access_Failure, value_kind = .Object}
				} else {
					err = append_byte(serializer, '{')
				}
				frame.started = true
				if err.kind == .None && frame.length == 0 do err = append_byte(serializer, '}')
			} else if frame.index >= frame.length {
				if pretty do err = append_pretty_indent(serializer, frame.depth)
				if err.kind == .None do err = append_byte(serializer, '}')
			} else {
				key, child, ok := value.object_iter_next_copy(&frame.node, &frame.iterator)
				if !ok {
					err = {kind = .Value_Access_Failure, value_kind = .Object}
				} else {
					if frame.index > 0 do err = append_byte(serializer, ',')
					if err.kind == .None && pretty {
						err = append_pretty_indent(serializer, frame.depth + 1)
					}
					key_bytes, key_ok := value.string_borrowed(&key)
					if err.kind == .None && !key_ok {
						err = {kind = .Value_Access_Failure, value_kind = .Object}
					}
					if err.kind == .None do err = append_quoted(serializer, key_bytes)
					if err.kind == .None do err = append_byte(serializer, ':')
					if err.kind == .None && pretty do err = append_byte(serializer, ' ')
					key_destroy_error := value.destroy_value(&key)
					if key_destroy_error != nil {
						serializer.frames[serializer.frame_count] = frame
						serializer.frame_count += 1
						serializer.frames[serializer.frame_count] = {
							node = key,
							kind = .Value,
						}
						serializer.frame_count += 1
						serializer.frames[serializer.frame_count] = {
							node = child,
							kind = .Value,
							depth = frame.depth + 1,
						}
						serializer.frame_count += 1
						return finish_compact_failure(
							serializer,
							{kind = .Cleanup_Failed, value_kind = .Object},
						)
					}
					if err.kind == .None {
						frame.index += 1
						serializer.frames[serializer.frame_count] = frame
						serializer.frame_count += 1
						serializer.frames[serializer.frame_count] = {
							node = child,
							kind = .Value,
							depth = frame.depth + 1,
						}
						serializer.frame_count += 1
						continue
					}
					child_destroy_error := value.destroy_value(&child)
					if child_destroy_error != nil {
						serializer.frames[serializer.frame_count] = frame
						serializer.frame_count += 1
						serializer.frames[serializer.frame_count] = {
							node = child,
							kind = .Value,
						}
						serializer.frame_count += 1
						return finish_compact_failure(
							serializer,
							{kind = .Cleanup_Failed, value_kind = .Object},
						)
					}
				}
			}
			if err.kind == .None && frame.started && frame.index < frame.length {
				serializer.frames[serializer.frame_count] = frame
				serializer.frame_count += 1
				continue
			}
		}
		if err.kind != .None {
			serializer.frames[serializer.frame_count] = frame
			serializer.frame_count += 1
			return finish_compact_failure(serializer, err)
		}
		destroy_error := value.destroy_value(&frame.node)
		if destroy_error != nil {
			serializer.frames[serializer.frame_count] = frame
			serializer.frame_count += 1
			return finish_compact_failure(serializer, {kind = .Cleanup_Failed, value_kind = kind})
		}
	}
	result^ = {
		owner = rawptr(result),
		state = .Ready,
		allocator = serializer.allocator,
		memory = serializer.output_memory,
		byte_count = serializer.output_length,
	}
	serializer.output_memory = nil
	serializer.output_length = 0
	return {}
}

serialize_compact :: proc(
	serializer: ^Compact_Serializer,
	input: ^value.Value,
	result: ^Compact_Result,
) -> Compact_Error {
	return serialize_json(serializer, input, result, false)
}

init_pretty_serializer :: proc(
	serializer: ^Pretty_Serializer,
	allocator: runtime.Allocator,
) -> bool {
	return init_compact_serializer(cast(^Compact_Serializer)serializer, allocator)
}

pretty_result_bytes :: proc(result: ^Pretty_Result) -> (string, bool) {
	return compact_result_bytes(cast(^Compact_Result)result)
}

take_pretty_result :: proc(destination, source: ^Pretty_Result) -> Compact_Error_Kind {
	return take_compact_result(
		cast(^Compact_Result)destination,
		cast(^Compact_Result)source,
	)
}

destroy_pretty_result :: proc(result: ^Pretty_Result) -> runtime.Allocator_Error {
	return destroy_compact_result(cast(^Compact_Result)result)
}

destroy_pretty_serializer :: proc(serializer: ^Pretty_Serializer) -> runtime.Allocator_Error {
	return destroy_compact_serializer(cast(^Compact_Serializer)serializer)
}

// serialize_pretty borrows input and emits jq 1.8.1's default two-space pretty
// term bytes. It intentionally excludes the CLI's trailing newline, color,
// ASCII-only output, and sorted-key options.
serialize_pretty :: proc(
	serializer: ^Pretty_Serializer,
	input: ^value.Value,
	result: ^Pretty_Result,
) -> Compact_Error {
	return serialize_json(
		cast(^Compact_Serializer)serializer,
		input,
		cast(^Compact_Result)result,
		true,
	)
}
