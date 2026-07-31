// Package value owns the logical JSON value and its memory contract.
package value

import "base:runtime"
import "core:math"
import "core:strconv"

// Kind reserves the complete runtime value kind space. Array and Object are
// intentionally not constructible in this scalar implementation slice.
Kind :: enum u8 {
	Invalid,
	Null,
	Boolean,
	Number,
	String,
	Array,
	Object,
}

Number_Kind :: enum u8 {
	Native,
	Literal,
}

Error :: enum u8 {
	None,
	Out_Of_Memory,
	Invalid_Number_Literal,
	Size_Overflow,
}

@(private)
constructor_error_storage :: struct {
	kind:              Error,
	cleanup_memory:    []byte,
	cleanup_allocator: runtime.Allocator,
}

// Constructor_Error is inert for ordinary failures. When exact-length
// allocation validation cannot retire a nonempty mismatched result, it owns
// that slice until destroy_constructor_error succeeds. It must not be copied.
Constructor_Error :: union {
	constructor_error_storage,
}

@(private)
make_constructor_error :: proc(kind: Error) -> Constructor_Error {
	if kind == .None {
		return {}
	}
	return constructor_error_storage{kind = kind}
}

@(private)
make_cleanup_constructor_error :: proc(
	kind: Error,
	memory: []byte,
	allocator: runtime.Allocator,
) -> Constructor_Error {
	return constructor_error_storage{
		kind = kind,
		cleanup_memory = memory,
		cleanup_allocator = allocator,
	}
}

constructor_error_kind :: proc(err: ^Constructor_Error) -> Error {
	if err == nil || err^ == nil {
		return .None
	}
	return err.(constructor_error_storage).kind
}

constructor_error_needs_cleanup :: proc(err: ^Constructor_Error) -> bool {
	if err == nil || err^ == nil {
		return false
	}
	return len(err.(constructor_error_storage).cleanup_memory) > 0
}

take_constructor_error :: proc(source: ^Constructor_Error) -> Constructor_Error {
	if source == nil {
		return {}
	}
	result := source^
	source^ = {}
	return result
}

// destroy_constructor_error retries retirement of a mismatched allocation.
// A genuine Free error leaves the owning handle unchanged for another retry;
// Mode_Not_Implemented is successful retirement under a bulk allocator.
destroy_constructor_error :: proc(err: ^Constructor_Error) -> runtime.Allocator_Error {
	if err == nil || err^ == nil {
		return nil
	}
	storage := &err.(constructor_error_storage)
	if len(storage.cleanup_memory) > 0 {
		free_error := runtime.mem_free_bytes(storage.cleanup_memory, storage.cleanup_allocator)
		if free_error != nil && free_error != .Mode_Not_Implemented {
			return free_error
		}
	}
	err^ = {}
	return nil
}

@(private)
payload_kind :: enum u8 {
	String,
	Literal_Number,
}

@(private)
payload :: struct {
	references:      int,
	allocator:       runtime.Allocator,
	allocation_size: int,
	kind:            payload_kind,
	byte_count:      int,
	coefficient_len: int,
	exponent:        i64,
	negative:        bool,
	infinite:        bool,
	native_cache:    f64,
}

@(private)
value_storage :: struct {
	kind:           Kind,
	boolean:        bool,
	native_number:  f64,
	owned_payload:  ^payload,
}

// Value is an owning tagged handle whose only union variant is package-private.
// The nil union is the inert invalid value. Ordinary assignment of a live Value
// is not an ownership operation; use clone_value or take_value.
Value :: union {
	value_storage,
}

@(private)
value_from_storage :: proc(storage: value_storage) -> Value {
	return storage
}

@(private)
value_storage_of :: proc(value: ^Value) -> ^value_storage {
	return &value.(value_storage)
}

@(private)
DECIMAL_EMAX :: i64(999_999_999)
@(private)
DECIMAL_EMIN :: i64(-999_999_999)
@(private)
DECIMAL_DIGITS :: int(147_483_648)
@(private)
DECIMAL_ETINY :: DECIMAL_EMIN - i64(DECIMAL_DIGITS) + 1

invalid_value :: proc() -> Value {
	return {}
}

null_value :: proc() -> Value {
	return value_from_storage({kind = .Null})
}

boolean_value :: proc(value: bool) -> Value {
	return value_from_storage({kind = .Boolean, boolean = value})
}

number_value :: proc(value: f64) -> Value {
	return value_from_storage({kind = .Number, native_number = value})
}

kind_of :: proc(value: ^Value) -> Kind {
	if value == nil || value^ == nil {
		return .Invalid
	}
	return value_storage_of(value).kind
}

boolean_value_get :: proc(value: ^Value) -> (result: bool, ok: bool) {
	if value == nil || value^ == nil {
		return false, false
	}
	storage := value_storage_of(value)
	if storage.kind != .Boolean {
		return false, false
	}
	return storage.boolean, true
}

number_kind :: proc(value: ^Value) -> (result: Number_Kind, ok: bool) {
	if value == nil || value^ == nil {
		return {}, false
	}
	storage := value_storage_of(value)
	if storage.kind != .Number {
		return {}, false
	}
	if storage.owned_payload != nil {
		return .Literal, true
	}
	return .Native, true
}

number_value_get :: proc(value: ^Value) -> (result: f64, ok: bool) {
	if value == nil || value^ == nil {
		return 0, false
	}
	storage := value_storage_of(value)
	if storage.kind != .Number {
		return 0, false
	}
	if storage.owned_payload != nil {
		return storage.owned_payload.native_cache, true
	}
	return storage.native_number, true
}

@(private)
payload_bytes :: proc(p: ^payload) -> []byte {
	if p == nil || p.byte_count == 0 {
		return nil
	}
	data := cast([^]byte)(uintptr(p) + size_of(payload))
	return data[:p.byte_count]
}

@(private)
payload_coefficient :: proc(p: ^payload) -> []byte {
	if p == nil || p.coefficient_len == 0 {
		return nil
	}
	data := cast([^]byte)(uintptr(p) + size_of(payload) + uintptr(p.byte_count))
	return data[:p.coefficient_len]
}

@(private)
allocate_payload :: proc(
	kind: payload_kind,
	byte_count, coefficient_capacity: int,
	allocator: runtime.Allocator,
) -> (p: ^payload, err: Constructor_Error) {
	if byte_count < 0 || coefficient_capacity < 0 {
		return nil, make_constructor_error(.Size_Overflow)
	}
	header_size := int(size_of(payload))
	if byte_count > max(int) - header_size ||
	   coefficient_capacity > max(int) - header_size - byte_count {
		return nil, make_constructor_error(.Size_Overflow)
	}
	allocation_size := header_size + byte_count + coefficient_capacity
	memory, alloc_error := runtime.mem_alloc(
		allocation_size,
		align_of(payload),
		allocator,
	)
	if alloc_error != nil || len(memory) != allocation_size {
		if len(memory) > 0 {
			free_error := runtime.mem_free_bytes(memory, allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				return nil, make_cleanup_constructor_error(.Out_Of_Memory, memory, allocator)
			}
		}
		return nil, make_constructor_error(.Out_Of_Memory)
	}
	p = cast(^payload)(raw_data(memory))
	p.references = 1
	p.allocator = allocator
	p.allocation_size = allocation_size
	p.kind = kind
	p.byte_count = byte_count
	return p, nil
}

string_value :: proc(bytes: string, allocator: runtime.Allocator) -> (
	result: Value,
	err: Constructor_Error,
) {
	p, payload_error := allocate_payload(.String, len(bytes), 0, allocator)
	if payload_error != nil {
		return {}, payload_error
	}
	if len(bytes) > 0 {
		copy(payload_bytes(p), transmute([]byte)bytes)
	}
	return value_from_storage({kind = .String, owned_payload = p}), nil
}

// string_borrowed returns a length-delimited immutable view. It remains valid
// only while the owning handle is live and unmutated.
string_borrowed :: proc(value: ^Value) -> (result: string, ok: bool) {
	if value == nil || value^ == nil {
		return "", false
	}
	storage := value_storage_of(value)
	if storage.kind != .String || storage.owned_payload == nil {
		return "", false
	}
	bytes := payload_bytes(storage.owned_payload)
	if len(bytes) == 0 {
		return "", true
	}
	return transmute(string)bytes, true
}

@(private)
decimal_scan :: struct {
	negative:        bool,
	mantissa_start:  int,
	mantissa_end:    int,
	significant_at:  int,
	significant_len: int,
	exponent:        i64,
}

@(private)
is_digit :: proc(c: byte) -> bool {
	return c >= '0' && c <= '9'
}

@(private)
ascii_lower :: proc(c: byte) -> byte {
	if c >= 'A' && c <= 'Z' {
		return c + ('a' - 'A')
	}
	return c
}

@(private)
ascii_equal_fold :: proc(a, b: string) -> bool {
	if len(a) != len(b) {
		return false
	}
	for i in 0..<len(a) {
		if ascii_lower(a[i]) != ascii_lower(b[i]) {
			return false
		}
	}
	return true
}

@(private)
special_literal :: proc(literal: string) -> (
	negative, infinite, nan, ok: bool,
) {
	if len(literal) == 0 {
		return
	}
	i := 0
	if literal[i] == '+' || literal[i] == '-' {
		negative = literal[i] == '-'
		i += 1
		if i == len(literal) {
			return
		}
	}
	body := literal[i:]
	if ascii_equal_fold(body, "inf") || ascii_equal_fold(body, "infinity") {
		return negative, true, false, true
	}

	payload_at := 0
	if len(body) >= 4 && ascii_equal_fold(body[:4], "snan") {
		payload_at = 4
	} else if len(body) >= 3 && ascii_equal_fold(body[:3], "nan") {
		payload_at = 3
	} else {
		return
	}
	// jvp_literal_number_new converts a payload-free NaN to a native number.
	// decNumber canonicalizes an all-zero payload to that same representation.
	for c in body[payload_at:] {
		if c != '0' {
			return false, false, false, false
		}
	}
	return negative, false, true, true
}

@(private)
scan_literal :: proc(literal: string) -> (scan: decimal_scan, ok: bool) {
	if len(literal) == 0 {
		return {}, false
	}
	i := 0
	if literal[i] == '+' || literal[i] == '-' {
		scan.negative = literal[i] == '-'
		i += 1
		if i == len(literal) {
			return {}, false
		}
	}
	scan.mantissa_start = i
	integer_start := i
	for i < len(literal) && is_digit(literal[i]) {
		i += 1
	}
	integer_digits := i - integer_start

	fraction_digits := i64(0)
	if i < len(literal) && literal[i] == '.' {
		i += 1
		fraction_start := i
		for i < len(literal) && is_digit(literal[i]) {
			i += 1
		}
		fraction_digits = i64(i - fraction_start)
	}
	if integer_digits == 0 && fraction_digits == 0 {
		return {}, false
	}
	scan.mantissa_end = i

	explicit_exponent := i64(0)
	if i < len(literal) && (literal[i] == 'e' || literal[i] == 'E') {
		i += 1
		exponent_negative := false
		if i < len(literal) && (literal[i] == '+' || literal[i] == '-') {
			exponent_negative = literal[i] == '-'
			i += 1
		}
		if i == len(literal) || !is_digit(literal[i]) {
			return {}, false
		}
		EXPONENT_SATURATION :: i64(1_999_999_998)
		for i < len(literal) && is_digit(literal[i]) {
			digit := i64(literal[i] - '0')
			if explicit_exponent <= (EXPONENT_SATURATION - digit) / 10 {
				explicit_exponent = explicit_exponent * 10 + digit
			} else {
				explicit_exponent = EXPONENT_SATURATION
			}
			i += 1
		}
		if exponent_negative {
			explicit_exponent = -explicit_exponent
		}
	}
	if i != len(literal) {
		return {}, false
	}
	scan.exponent = explicit_exponent - fraction_digits

	first_digit := -1
	first_nonzero := -1
	digit_count := 0
	for j in scan.mantissa_start..<scan.mantissa_end {
		if literal[j] == '.' {
			continue
		}
		if first_digit < 0 {
			first_digit = j
		}
		if first_nonzero < 0 && literal[j] != '0' {
			first_nonzero = j
		}
		if first_nonzero >= 0 {
			digit_count += 1
		}
	}
	if first_nonzero < 0 {
		scan.significant_at = first_digit
		scan.significant_len = 1
	} else {
		scan.significant_at = first_nonzero
		scan.significant_len = digit_count
	}
	return scan, true
}

@(private)
increment_coefficient :: proc(coefficient: []byte, exponent: ^i64) {
	for i := len(coefficient) - 1; i >= 0; i -= 1 {
		if coefficient[i] != '9' {
			coefficient[i] += 1
			return
		}
		coefficient[i] = '0'
	}
	coefficient[0] = '1'
	for i := 1; i < len(coefficient); i += 1 {
		coefficient[i] = '0'
	}
	exponent^ += 1
}

@(private)
round_coefficient :: proc(coefficient: []byte, first_discarded: byte, exponent: ^i64) {
	if first_discarded >= '5' {
		increment_coefficient(coefficient, exponent)
	}
}

@(private)
coefficient_is_zero :: proc(coefficient: []byte) -> bool {
	return len(coefficient) == 1 && coefficient[0] == '0'
}

@(private)
finalize_decimal :: proc(
	p: ^payload,
	context_digits: int,
	context_emin, context_emax: i64,
) {
	coefficient := payload_coefficient(p)
	etiny := context_emin - i64(context_digits) + 1
	if coefficient_is_zero(coefficient) {
		if p.exponent > context_emax {
			p.exponent = context_emax
		} else if p.exponent < etiny {
			p.exponent = etiny
		}
		return
	}

	adjusted := p.exponent + i64(p.coefficient_len) - 1
	if adjusted > context_emax {
		p.infinite = true
		p.coefficient_len = 0
		return
	}
}

@(private)
append_i64_decimal :: proc(buffer: []byte, at: ^int, value: i64) {
	magnitude: u64
	if value < 0 {
		buffer[at^] = '-'
		at^ += 1
		magnitude = u64(-(value + 1)) + 1
	} else {
		magnitude = u64(value)
	}
	start := at^
	for {
		buffer[at^] = byte(magnitude % 10) + '0'
		at^ += 1
		magnitude /= 10
		if magnitude == 0 {
			break
		}
	}
	for left, right := start, at^ - 1; left < right; left, right = left + 1, right - 1 {
		buffer[left], buffer[right] = buffer[right], buffer[left]
	}
}

@(private)
decimal_to_binary64 :: proc(p: ^payload) -> f64 {
	if p.infinite {
		if p.negative {
			return math.inf_f64(-1)
		}
		return math.inf_f64(1)
	}
	source := payload_coefficient(p)
	if coefficient_is_zero(source) {
		if p.negative {
			return -0.0
		}
		return 0.0
	}
	adjusted := p.exponent + i64(len(source)) - 1
	if adjusted > 308 {
		if p.negative {
			return math.inf_f64(-1)
		}
		return math.inf_f64(1)
	}
	if adjusted < -324 {
		if p.negative {
			return -0.0
		}
		return 0.0
	}

	DOUBLE_DECIMAL_DIGITS :: 17
	digits: [DOUBLE_DECIMAL_DIGITS]byte
	count := min(len(source), DOUBLE_DECIMAL_DIGITS)
	copy(digits[:count], source[:count])
	exponent := p.exponent
	if len(source) > DOUBLE_DECIMAL_DIGITS {
		discarded := source[DOUBLE_DECIMAL_DIGITS:]
		round_up := discarded[0] > '5'
		if discarded[0] == '5' {
			for c in discarded[1:] {
				if c != '0' {
					round_up = true
					break
				}
			}
			if !round_up {
				round_up = (digits[count - 1] - '0') & 1 == 1
			}
		}
		exponent += i64(len(source) - DOUBLE_DECIMAL_DIGITS)
		if round_up {
			increment_coefficient(digits[:count], &exponent)
		}
	}

	// decNumberReduce removes trailing zeroes before decNumberToString.
	for count > 1 && digits[count - 1] == '0' {
		count -= 1
		exponent += 1
	}

	buffer: [64]byte
	at := 0
	if p.negative {
		buffer[at] = '-'
		at += 1
	}
	copy(buffer[at:], digits[:count])
	at += count
	buffer[at] = 'e'
	at += 1
	append_i64_decimal(buffer[:], &at, exponent)
	result, ok := strconv.parse_f64(string(buffer[:at]))
	assert(ok || math.is_inf(result))
	return result
}

@(private)
literal_number_value_with_context :: proc(
	literal: string,
	allocator: runtime.Allocator,
	context_digits: int,
	context_emin, context_emax: i64,
) -> (result: Value, err: Constructor_Error) {
	special_negative, special_infinite, special_nan, special_ok :=
		special_literal(literal)
	if special_ok && special_nan {
		return number_value(math.nan_f64()), nil
	}

	scan, ok := scan_literal(literal)
	if !ok && !special_infinite {
		return {}, make_constructor_error(.Invalid_Number_Literal)
	}
	assert(context_digits > 0 && context_digits <= DECIMAL_DIGITS)
	if context_emin > context_emax {
		return {}, make_constructor_error(.Invalid_Number_Literal)
	}

	coefficient_capacity := 0
	if !special_infinite {
		etiny := context_emin - i64(context_digits) + 1
		precision_discard := max(scan.significant_len - context_digits, 0)
		etiny_discard_i64 := max(etiny - scan.exponent, 0)
		discard := i64(precision_discard)
		if etiny_discard_i64 > discard {
			discard = etiny_discard_i64
		}
		keep := i64(scan.significant_len) - discard
		if keep > 0 {
			coefficient_capacity = int(keep)
		} else {
			coefficient_capacity = 1
		}
	}
	p, payload_error := allocate_payload(
		.Literal_Number,
		len(literal),
		coefficient_capacity,
		allocator,
	)
	if payload_error != nil {
		return {}, payload_error
	}

	raw := payload_bytes(p)
	copy(raw, transmute([]byte)literal)
	p.negative = special_negative || scan.negative
	p.infinite = special_infinite
	if special_infinite {
		p.native_cache = decimal_to_binary64(p)
		return value_from_storage({kind = .Number, owned_payload = p}), nil
	}

	etiny := context_emin - i64(context_digits) + 1
	precision_discard := max(scan.significant_len - context_digits, 0)
	etiny_discard := max(etiny - scan.exponent, 0)
	discard := i64(precision_discard)
	if etiny_discard > discard {
		discard = etiny_discard
	}
	keep := i64(scan.significant_len) - discard
	p.exponent = scan.exponent + discard
	p.coefficient_len = coefficient_capacity

	coefficient := payload_coefficient(p)
	if keep <= 0 {
		coefficient[0] = '0'
		p.coefficient_len = 1
		p.exponent = etiny
	}

	out, significant_seen := 0, 0
	first_discarded := byte('0')
	for i := scan.significant_at; i < scan.mantissa_end; i += 1 {
		if literal[i] == '.' {
			continue
		}
		if keep > 0 && i64(significant_seen) < keep {
			coefficient[out] = literal[i]
			out += 1
		} else if i64(significant_seen) == keep {
			first_discarded = literal[i]
		}
		significant_seen += 1
	}
	if discard > 0 {
		if first_discarded >= '5' {
			increment_coefficient(coefficient[:p.coefficient_len], &p.exponent)
		}
	}
	finalize_decimal(p, context_digits, context_emin, context_emax)
	p.native_cache = decimal_to_binary64(p)
	return value_from_storage({kind = .Number, owned_payload = p}), nil
}

@(private)
literal_number_value_with_precision :: proc(
	literal: string,
	allocator: runtime.Allocator,
	precision: int,
) -> (result: Value, err: Constructor_Error) {
	return literal_number_value_with_context(
		literal,
		allocator,
		precision,
		DECIMAL_EMIN,
		DECIMAL_EMAX,
	)
}

// literal_number_value mirrors jv_number_with_literal: it uses decNumber
// numeric syntax, then applies jq's additional rejection of nonzero NaN
// payloads. This is broader than strict RFC 8259 number syntax. JSON and jq
// lexer boundaries remain the responsibility of their respective scanners.
literal_number_value :: proc(
	literal: string,
	allocator: runtime.Allocator,
) -> (result: Value, err: Constructor_Error) {
	return literal_number_value_with_context(
		literal,
		allocator,
		DECIMAL_DIGITS,
		DECIMAL_EMIN,
		DECIMAL_EMAX,
	)
}

// literal_spelling_borrowed exposes retained input spelling, not jq printer
// output. The view follows the same lifetime rule as string_borrowed.
literal_spelling_borrowed :: proc(value: ^Value) -> (result: string, ok: bool) {
	if value == nil || value^ == nil {
		return "", false
	}
	storage := value_storage_of(value)
	if storage.kind != .Number || storage.owned_payload == nil ||
	   storage.owned_payload.kind != .Literal_Number {
		return "", false
	}
	bytes := payload_bytes(storage.owned_payload)
	return transmute(string)bytes, true
}

clone_value :: proc(value: ^Value) -> Value {
	if value == nil || value^ == nil {
		return {}
	}
	storage := value_storage_of(value)
	if storage.kind == .Invalid {
		return {}
	}
	result := value^
	result_storage := value_storage_of(&result)
	if result_storage.owned_payload != nil {
		assert(result_storage.owned_payload.references > 0)
		assert(result_storage.owned_payload.references < max(int))
		result_storage.owned_payload.references += 1
	}
	return result
}

take_value :: proc(source: ^Value) -> Value {
	if source == nil {
		return {}
	}
	result := source^
	source^ = {}
	return result
}

// destroy_value retires one owning handle. A genuine allocator error while
// freeing the final reference is returned with the handle left owning and
// retryable. Mode_Not_Implemented is successful retirement for allocators
// whose storage is released in bulk.
destroy_value :: proc(value: ^Value) -> runtime.Allocator_Error {
	if value == nil || value^ == nil {
		return nil
	}
	storage := value_storage_of(value)
	if storage.kind == .Invalid {
		return nil
	}
	p := storage.owned_payload
	if p == nil {
		value^ = {}
		return nil
	}
	assert(p.references > 0)
	if p.references > 1 {
		p.references -= 1
		value^ = {}
		return nil
	}
	allocator := p.allocator
	allocation_size := p.allocation_size
	free_error := runtime.mem_free_with_size(p, allocation_size, allocator)
	if free_error != nil && free_error != .Mode_Not_Implemented {
		return free_error
	}
	if free_error == .Mode_Not_Implemented {
		p.references = 0
	}
	value^ = {}
	return nil
}

@(private)
normalized_decimal :: struct {
	coefficient: []byte,
	exponent:    i64,
	negative:    bool,
	infinite:    bool,
}

@(private)
normalize_decimal :: proc(p: ^payload) -> normalized_decimal {
	if p.infinite {
		return {negative = p.negative, infinite = true}
	}
	coefficient := payload_coefficient(p)
	if coefficient_is_zero(coefficient) {
		return {coefficient = coefficient}
	}
	end := len(coefficient)
	exponent := p.exponent
	for end > 1 && coefficient[end - 1] == '0' {
		end -= 1
		exponent += 1
	}
	return {
		coefficient = coefficient[:end],
		exponent = exponent,
		negative = p.negative,
	}
}

@(private)
compare_magnitudes :: proc(left, right: normalized_decimal) -> int {
	left_adjusted := left.exponent + i64(len(left.coefficient)) - 1
	right_adjusted := right.exponent + i64(len(right.coefficient)) - 1
	if left_adjusted < right_adjusted {
		return -1
	}
	if left_adjusted > right_adjusted {
		return 1
	}
	digit_count := max(len(left.coefficient), len(right.coefficient))
	for i in 0..<digit_count {
		left_digit := byte('0')
		if i < len(left.coefficient) {
			left_digit = left.coefficient[i]
		}
		right_digit := byte('0')
		if i < len(right.coefficient) {
			right_digit = right.coefficient[i]
		}
		if left_digit < right_digit {
			return -1
		}
		if left_digit > right_digit {
			return 1
		}
	}
	return 0
}

@(private)
compare_literal_numbers :: proc(a, b: ^payload) -> int {
	left := normalize_decimal(a)
	right := normalize_decimal(b)
	if left.infinite || right.infinite {
		if left.infinite && right.infinite && left.negative == right.negative {
			return 0
		}
		if left.infinite {
			if left.negative {
				return -1
			}
			return 1
		}
		if right.negative {
			return 1
		}
		return -1
	}
	left_zero := coefficient_is_zero(left.coefficient)
	right_zero := coefficient_is_zero(right.coefficient)
	if left_zero && right_zero {
		return 0
	}
	if left_zero {
		if right.negative {
			return 1
		}
		return -1
	}
	if right_zero {
		if left.negative {
			return -1
		}
		return 1
	}
	if left.negative != right.negative {
		if left.negative {
			return -1
		}
		return 1
	}
	result := compare_magnitudes(left, right)
	if left.negative {
		result = -result
	}
	return result
}

// compare_numbers mirrors jq's low-level jvp_number_cmp: retained literals
// compare in decimal space; native/native and mixed pairs use f64 `<`, then
// `==`, then return 1. Consequently a native NaN compares as 1 in either
// operand position and against itself. This is not jq's total Value ordering;
// jv_cmp handles NaN separately before calling jvp_number_cmp.
compare_numbers :: proc(a, b: ^Value) -> (result: int, ok: bool) {
	if a == nil || b == nil || a^ == nil || b^ == nil {
		return 0, false
	}
	a_storage := value_storage_of(a)
	b_storage := value_storage_of(b)
	if a_storage.kind != .Number || b_storage.kind != .Number {
		return 0, false
	}
	a_literal := a_storage.owned_payload != nil
	b_literal := b_storage.owned_payload != nil
	if a_literal && b_literal {
		return compare_literal_numbers(a_storage.owned_payload, b_storage.owned_payload), true
	}
	left := a_storage.native_number
	if a_literal {
		left = a_storage.owned_payload.native_cache
	}
	right := b_storage.native_number
	if b_literal {
		right = b_storage.owned_payload.native_cache
	}
	if left < right {
		return -1, true
	}
	if left == right {
		return 0, true
	}
	return 1, true
}

values_equal :: proc(a, b: ^Value) -> bool {
	if a == nil || b == nil || a^ == nil || b^ == nil {
		return false
	}
	a_storage := value_storage_of(a)
	b_storage := value_storage_of(b)
	if a_storage.kind != b_storage.kind {
		return false
	}
	switch a_storage.kind {
	case .Invalid, .Array, .Object:
		return false
	case .Null:
		return true
	case .Boolean:
		return a_storage.boolean == b_storage.boolean
	case .Number:
		comparison, ok := compare_numbers(a, b)
		return ok && comparison == 0
	case .String:
		left, left_ok := string_borrowed(a)
		right, right_ok := string_borrowed(b)
		return left_ok && right_ok && left == right
	}
	return false
}
