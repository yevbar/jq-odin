// Package value owns the logical JSON value and its memory contract.
package value

import "base:runtime"
import "core:math"
import "core:strconv"

// Kind reserves the complete runtime value kind space. Object remains
// intentionally unconstructible in this implementation slice.
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

// Number_Arithmetic_Result_Kind separates operand rejection and jq's
// zero-divisor runtime condition from a successful numeric result. These
// primitives allocate nothing, so allocator/resource failure is not part of
// this result space.
Number_Arithmetic_Result_Kind :: enum u8 {
	Success,
	Invalid_Operands,
	Zero_Divisor,
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
	// allocator_unsupported preserves allocator-mode provenance without
	// expanding the source-compatible public Error classification.
	allocator_unsupported: bool,
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
make_constructor_error :: proc(
	kind: Error,
	allocator_unsupported: bool = false,
) -> Constructor_Error {
	if kind == .None {
		return {}
	}
	return constructor_error_storage{
		kind = kind,
		allocator_unsupported = allocator_unsupported,
	}
}

@(private)
make_cleanup_constructor_error :: proc(
	kind: Error,
	memory: []byte,
	allocator: runtime.Allocator,
	allocator_unsupported: bool = false,
) -> Constructor_Error {
	return constructor_error_storage{
		kind = kind,
		allocator_unsupported = allocator_unsupported,
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

@(private)
constructor_error_allocator_unsupported :: proc(err: ^Constructor_Error) -> bool {
	if err == nil || err^ == nil do return false
	return err.(constructor_error_storage).allocator_unsupported
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
	Array,
	Object,
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
	explicit_positive_sign: bool,
	infinite:        bool,
	native_cache:    f64,
	array_initialized_length: int,
	array_capacity:           int,
	array_retired_count:      int,
	array_cleanup_at:         int,
	array_retiring:           bool,
	object_capacity:          int,
	object_next_free:         int,
	object_length:            int,
	object_cleanup_at:        int,
	object_cleanup_key_done:  bool,
	object_retiring:          bool,
	teardown_parent:          ^payload,
}

@(private)
value_storage :: struct {
	kind:           Kind,
	boolean:        bool,
	native_number:  f64,
	owned_payload:  ^payload,
	// payload_allocation_bound is the exact length returned by the allocator
	// that created owned_payload. It is immutable for this owning handle:
	// clone/take/slice copy it, and COW replacement installs a new payload and
	// bound together. Payload metadata is never an authority for this extent.
	payload_allocation_bound: int,
	array_length:   int,
	array_offset:   u16,
}

// Value_Handle fixes the public union payload layout across package boundaries.
// The compiler must retain its exported spelling so importing packages agree
// on Value's tag offset, but package privacy prevents callers from naming or
// constructing the storage variant.
@(private)
Value_Handle :: distinct [6]u64

// Value is an owning tagged handle. The nil union is the inert invalid value.
// Ordinary assignment of a live Value is not an ownership operation; use
// clone_value or take_value. The public fixed-layout variant gives importers
// the same payload size, alignment, and tag offset as package value.
Value :: union {
	Value_Handle,
}

#assert(size_of(value_storage) == size_of(Value_Handle))
#assert(align_of(value_storage) == align_of(Value_Handle))
#assert(size_of(Value) == 56)
#assert(align_of(Value) == 8)

@(private)
value_from_storage :: proc(storage: value_storage) -> Value {
	result: Value = Value_Handle{}
	value_storage_of(&result)^ = storage
	return result
}

@(private)
value_from_payload :: proc(kind: Kind, p: ^payload) -> Value {
	assert(p != nil)
	assert(p.allocation_size >= int(size_of(payload)))
	return value_from_storage({
		kind = kind,
		owned_payload = p,
		payload_allocation_bound = p.allocation_size,
	})
}

@(private)
payload_bound_matches :: proc(storage: ^value_storage, expected_size: int) -> bool {
	return storage != nil && storage.owned_payload != nil &&
	       storage.payload_allocation_bound == expected_size &&
	       storage.owned_payload.allocation_size == expected_size
}

@(private)
literal_storage_valid :: proc(storage: ^value_storage) -> bool {
	if storage == nil || storage.kind != .Number || storage.owned_payload == nil {
		return false
	}
	p := storage.owned_payload
	if p.kind != .Literal_Number || p.references <= 0 || p.references == max(int) ||
	   p.byte_count < 0 || p.coefficient_len < 0 ||
	   (p.infinite && p.coefficient_len != 0) ||
	   (!p.infinite && p.coefficient_len == 0) ||
	   p.byte_count > max(int) - int(size_of(payload)) {
		return false
	}
	minimum_size := int(size_of(payload)) + p.byte_count
	if p.coefficient_len > max(int) - minimum_size do return false
	if storage.payload_allocation_bound != p.allocation_size ||
	   storage.payload_allocation_bound < minimum_size + p.coefficient_len {
		return false
	}
	coefficient_capacity := storage.payload_allocation_bound - minimum_size
	return literal_metadata_valid(p, coefficient_capacity)
}

@(private)
string_storage_valid :: proc(storage: ^value_storage) -> bool {
	if storage == nil || storage.kind != .String || storage.owned_payload == nil {
		return false
	}
	p := storage.owned_payload
	if p.kind != .String || p.references <= 0 || p.references == max(int) || p.byte_count < 0 ||
	   p.coefficient_len != 0 || p.byte_count > max(int) - int(size_of(payload)) {
		return false
	}
	return payload_bound_matches(storage, int(size_of(payload)) + p.byte_count)
}

@(private)
value_local_extent_valid :: proc(value: ^Value, allow_retiring := false) -> bool {
	if value == nil || value^ == nil do return false
	storage := value_storage_of(value)
	switch storage.kind {
	case .Null, .Boolean:
		return storage.owned_payload == nil && storage.payload_allocation_bound == 0
	case .Number:
		if storage.owned_payload == nil do return storage.payload_allocation_bound == 0
		return literal_storage_valid(storage)
	case .String:
		return string_storage_valid(storage)
	case .Array:
		return array_storage_extent_valid(storage, allow_retiring)
	case .Object:
		return object_storage_extent_valid(storage, allow_retiring)
	case .Invalid:
		return false
	}
	return false
}

@(private)
value_storage_of :: proc(value: ^Value) -> ^value_storage {
	handle := &value.(Value_Handle)
	return cast(^value_storage)rawptr(handle)
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
	if storage.owned_payload != nil || storage.payload_allocation_bound != 0 {
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
		if !literal_storage_valid(storage) do return {}, false
		return .Literal, true
	}
	if storage.payload_allocation_bound != 0 do return {}, false
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
		if !literal_storage_valid(storage) do return 0, false
		return storage.owned_payload.native_cache, true
	}
	if storage.payload_allocation_bound != 0 do return 0, false
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
		allocator_unsupported := alloc_error == .Mode_Not_Implemented
		if len(memory) > 0 {
			free_error := runtime.mem_free_bytes(memory, allocator)
			if free_error != nil && free_error != .Mode_Not_Implemented {
				return nil, make_cleanup_constructor_error(
					.Out_Of_Memory,
					memory,
					allocator,
					allocator_unsupported,
				)
			}
		}
		return nil, make_constructor_error(.Out_Of_Memory, allocator_unsupported)
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
	return value_from_payload(.String, p), nil
}

// string_borrowed returns a length-delimited immutable view. It remains valid
// only while the owning handle is live and unmutated.
string_borrowed :: proc(value: ^Value) -> (result: string, ok: bool) {
	if value == nil || value^ == nil {
		return "", false
	}
	storage := value_storage_of(value)
	if !string_storage_valid(storage) {
		return "", false
	}
	p := storage.owned_payload
	bytes := payload_bytes(p)
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
literal_coefficient_capacity_borrowed :: proc(p: ^payload, capacity: int) -> []byte {
	if p == nil || capacity <= 0 do return nil
	data := cast([^]byte)(uintptr(p) + size_of(payload) + uintptr(p.byte_count))
	return data[:capacity]
}

@(private)
literal_significant_byte :: proc(literal: string, scan: decimal_scan, at: int) -> (
	byte,
	bool,
) {
	seen := 0
	for i in scan.significant_at..<scan.mantissa_end {
		if literal[i] == '.' do continue
		if seen == at do return literal[i], true
		seen += 1
	}
	return 0, false
}

@(private)
literal_rounded_coefficient_matches :: proc(
	literal: string,
	scan: decimal_scan,
	discard: i64,
	coefficient: []byte,
	exponent: i64,
) -> bool {
	if discard < 0 || len(coefficient) == 0 {
		return false
	}
	keep := i64(scan.significant_len) - discard
	expected_len := int(keep) if keep > 0 else 1
	if len(coefficient) != expected_len do return false

	round_up := false
	carry_at := -1
	if discard > 0 && keep >= 0 {
		first_discarded_at := int(keep) if keep > 0 else 0
		seen := 0
		found_discarded := false
		for i in scan.significant_at..<scan.mantissa_end {
			digit := literal[i]
			if digit == '.' do continue
			if seen < first_discarded_at && digit != '9' do carry_at = seen
			if seen == first_discarded_at {
				round_up = digit >= '5'
				found_discarded = true
				break
			}
			seen += 1
		}
		if !found_discarded do return false
		if !round_up do carry_at = -1
	}
	carry_overflow := round_up && keep > 0 && carry_at < 0
	expected_exponent := i128(scan.exponent) + i128(discard)
	if carry_overflow do expected_exponent += 1
	if i128(exponent) != expected_exponent do return false

	if keep <= 0 {
		expected := byte('1') if round_up else byte('0')
		return coefficient[0] == expected
	}
	coefficient_at := 0
	for spelling_at in scan.significant_at..<scan.mantissa_end {
		digit := literal[spelling_at]
		if digit == '.' do continue
		if coefficient_at == int(keep) do break
		expected := digit
		if carry_overflow {
			expected = '1' if coefficient_at == 0 else '0'
		} else if carry_at >= 0 {
			if coefficient_at == carry_at {
				expected += 1
			} else if coefficient_at > carry_at {
				expected = '0'
			}
		}
		if coefficient[coefficient_at] != expected do return false
		coefficient_at += 1
	}
	return coefficient_at == int(keep)
}

@(private)
literal_zero_exponent_valid :: proc(scan_exponent, exponent: i64) -> bool {
	if scan_exponent > DECIMAL_EMAX do return exponent == DECIMAL_EMAX
	if scan_exponent >= DECIMAL_ETINY do return exponent == scan_exponent
	// Private precision constructors have an etiny between the default etiny
	// and emin. A zero below that context is clamped to that exact etiny.
	return exponent >= DECIMAL_ETINY && exponent <= DECIMAL_EMIN &&
	       exponent > scan_exponent
}

@(private)
literal_metadata_valid :: proc(p: ^payload, coefficient_capacity: int) -> bool {
	if p == nil || coefficient_capacity < 0 do return false
	spelling_bytes := payload_bytes(p)
	literal := transmute(string)spelling_bytes
	special_negative, special_infinite, special_nan, special_ok := special_literal(literal)
	expected_positive_sign := len(literal) > 0 && literal[0] == '+'
	if p.explicit_positive_sign != expected_positive_sign do return false

	if special_ok {
		// Direct infinity construction has exponent zero. Canonical negation of
		// an overflowed finite literal preserves its overflowing exponent while
		// replacing the retained spelling and dropping the no-longer-live tail.
		valid_exponent := p.exponent == 0 || p.exponent > DECIMAL_EMAX
		if special_nan || !special_infinite || !p.infinite || p.coefficient_len != 0 ||
		   coefficient_capacity != 0 || p.negative != special_negative || !valid_exponent {
			return false
		}
		return transmute(u64)p.native_cache == transmute(u64)decimal_to_binary64(p)
	}

	scan, scan_ok := scan_literal(literal)
	if !scan_ok || p.negative != scan.negative do return false
	coefficient := literal_coefficient_capacity_borrowed(p, coefficient_capacity)
	if scan.significant_len == 1 {
		first, first_ok := literal_significant_byte(literal, scan, 0)
		if !first_ok do return false
		if first == '0' {
			if p.infinite || coefficient_capacity != 1 || p.coefficient_len != 1 ||
			   coefficient[0] != '0' || !literal_zero_exponent_valid(scan.exponent, p.exponent) {
				return false
			}
			return transmute(u64)p.native_cache == transmute(u64)decimal_to_binary64(p)
		}
	}

	if coefficient_capacity <= 0 || coefficient_capacity > scan.significant_len {
		return false
	}
	if p.infinite {
		if p.coefficient_len != 0 do return false
	} else if p.coefficient_len != coefficient_capacity {
		return false
	}

	// The constructor's discarded count is reflected in the stored exponent.
	// A rounding carry is the only operation that can add one more.
	discard_wide := i128(p.exponent) - i128(scan.exponent)
	if discard_wide < 0 || discard_wide > i128(max(i64)) do return false
	discard_from_exponent := i64(discard_wide)
	matched := literal_rounded_coefficient_matches(
		literal, scan, discard_from_exponent, coefficient, p.exponent,
	)
	if !matched && discard_from_exponent > 0 {
		matched = literal_rounded_coefficient_matches(
			literal, scan, discard_from_exponent - 1, coefficient, p.exponent,
		)
	}
	if !matched do return false
	if discard_wide > i128(scan.significant_len) + 1 {
		if p.infinite || coefficient_capacity != 1 || coefficient[0] != '0' ||
		   p.exponent < DECIMAL_ETINY || p.exponent > DECIMAL_EMIN {
			return false
		}
	}
	adjusted := i128(p.exponent) + i128(coefficient_capacity) - 1
	if p.infinite {
		if adjusted <= i128(DECIMAL_EMAX) do return false
	} else if adjusted > i128(DECIMAL_EMAX) {
		return false
	}
	return transmute(u64)p.native_cache == transmute(u64)decimal_to_binary64(p)
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
			return -math.inf_f64(1)
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
			return -math.inf_f64(1)
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
		return number_value(transmute(f64)u64(0x7ff8000000000000)), nil
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
	p.explicit_positive_sign = len(literal) > 0 && literal[0] == '+'
	p.infinite = special_infinite
	if special_infinite {
		p.native_cache = decimal_to_binary64(p)
		return value_from_payload(.Number, p), nil
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
	return value_from_payload(.Number, p), nil
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
	if !literal_storage_valid(storage) {
		return "", false
	}
	bytes := payload_bytes(storage.owned_payload)
	return transmute(string)bytes, true
}

@(private)
toggle_f64_sign :: proc(value: f64) -> f64 {
	return transmute(f64)((transmute(u64)value) ~ (u64(1) << 63))
}

// number_negate borrows source for the complete call and returns an
// independent number. Native numbers remain inline. Literal numbers use one
// exact destination allocation through allocator and preserve their decimal
// identity. Their retained spelling is freshly generated in decNumberToString
// form; it never aliases or recovers the source lexeme.
@(private)
decimal_i64_digit_count :: proc(value: i64) -> int {
	magnitude := value
	if magnitude < 0 do magnitude = -magnitude
	digits := 1
	for magnitude >= 10 {
		magnitude /= 10
		digits += 1
	}
	return digits
}

@(private)
canonical_literal_size :: proc(p: ^payload, negative: bool) -> (int, bool) {
	if p == nil || p.kind != .Literal_Number {
		return 0, false
	}
	sign_size := 1 if negative && (p.infinite || !coefficient_is_zero(payload_coefficient(p))) else 0
	if p.infinite {
		return sign_size + len("Infinity"), true
	}

	digits := p.coefficient_len
	if digits <= 0 {
		return 0, false
	}
	if p.exponent == 0 {
		if digits > max(int) - sign_size {
			return 0, false
		}
		return sign_size + digits, true
	}
	pre := i64(digits) + p.exponent
	if p.exponent > 0 || pre < -5 {
		adjusted := p.exponent + i64(digits) - 1
		// coefficient, optional point, E, exponent sign, exponent digits
		extra := 2 + decimal_i64_digit_count(adjusted)
		if digits > 1 do extra += 1
		if digits > max(int) - sign_size - extra {
			return 0, false
		}
		return sign_size + digits + extra, true
	}
	if pre > 0 {
		extra := 1 if pre < i64(digits) else 0
		if digits > max(int) - sign_size - extra {
			return 0, false
		}
		return sign_size + digits + extra, true
	}
	leading_zeroes := int(-pre)
	extra := 2 + leading_zeroes
	if digits > max(int) - sign_size - extra {
		return 0, false
	}
	return sign_size + extra + digits, true
}

@(private)
write_canonical_literal :: proc(destination: []byte, p: ^payload, negative: bool) {
	at := 0
	coefficient := payload_coefficient(p)
	if negative && (p.infinite || !coefficient_is_zero(coefficient)) {
		destination[at] = '-'
		at += 1
	}
	if p.infinite {
		copy(destination[at:], "Infinity")
		at += len("Infinity")
		assert(at == len(destination))
		return
	}
	if p.exponent == 0 {
		copy(destination[at:], coefficient)
		at += len(coefficient)
		assert(at == len(destination))
		return
	}

	digits := len(coefficient)
	pre := i64(digits) + p.exponent
	if p.exponent > 0 || pre < -5 {
		adjusted := p.exponent + i64(digits) - 1
		destination[at] = coefficient[0]
		at += 1
		if digits > 1 {
			destination[at] = '.'
			at += 1
			copy(destination[at:], coefficient[1:])
			at += digits - 1
		}
		destination[at] = 'E'
		at += 1
		if adjusted >= 0 {
			destination[at] = '+'
			at += 1
		}
		append_i64_decimal(destination, &at, adjusted)
		assert(at == len(destination))
		return
	}
	if pre > 0 {
		before_point := int(pre)
		copy(destination[at:], coefficient[:before_point])
		at += before_point
		if before_point < digits {
			destination[at] = '.'
			at += 1
			copy(destination[at:], coefficient[before_point:])
			at += digits - before_point
		}
		assert(at == len(destination))
		return
	}
	destination[at] = '0'
	destination[at + 1] = '.'
	at += 2
	for _ in i64(0)..<-pre {
		destination[at] = '0'
		at += 1
	}
	copy(destination[at:], coefficient)
	at += digits
	assert(at == len(destination))
}

number_negate :: proc(
	source: ^Value,
	allocator: runtime.Allocator,
) -> (result: Value, err: Constructor_Error, ok: bool) {
	if source == nil || source^ == nil {
		return {}, nil, false
	}
	storage := value_storage_of(source)
	if storage.kind != .Number {
		return {}, nil, false
	}
	if storage.owned_payload == nil {
		if storage.payload_allocation_bound != 0 do return {}, nil, false
		return number_value(toggle_f64_sign(storage.native_number)), nil, true
	}
	if !literal_storage_valid(storage) do return {}, nil, false

	source_payload := storage.owned_payload
	literal_zero := coefficient_is_zero(payload_coefficient(source_payload))
	destination_negative := !literal_zero && !source_payload.negative
	destination_byte_count, size_ok := canonical_literal_size(
		source_payload,
		destination_negative,
	)
	if !size_ok {
		return {}, make_constructor_error(.Size_Overflow), false
	}

	destination_payload, payload_error := allocate_payload(
		.Literal_Number,
		destination_byte_count,
		source_payload.coefficient_len,
		allocator,
	)
	if payload_error != nil {
		return {}, payload_error, false
	}

	write_canonical_literal(
		payload_bytes(destination_payload),
		source_payload,
		destination_negative,
	)
	destination_payload.coefficient_len = source_payload.coefficient_len
	destination_payload.exponent = source_payload.exponent
	destination_payload.negative = destination_negative
	destination_payload.explicit_positive_sign = false
	destination_payload.infinite = source_payload.infinite
	if literal_zero {
		destination_payload.native_cache = 0.0
	} else {
		destination_payload.native_cache = toggle_f64_sign(source_payload.native_cache)
	}
	copy(payload_coefficient(destination_payload), payload_coefficient(source_payload))
	return value_from_payload(.Number, destination_payload), nil, true
}

// number_add borrows both operands for the complete call and returns a new
// inline native number. jq converts literal-backed operands through their
// binary64 caches before addition, so no representation combination allocates.
// Nil, invalid, and non-number operands return an inert result and false.
number_add :: proc(left, right: ^Value) -> (result: Value, ok: bool) {
	left_number, left_ok := number_value_get(left)
	if !left_ok {
		return {}, false
	}
	right_number, right_ok := number_value_get(right)
	if !right_ok {
		return {}, false
	}
	left_nan := math.is_nan(left_number)
	right_nan := math.is_nan(right_number)
	if left_nan || right_nan {
		// Pinned jq's C addition selects the right NaN when both operands
		// are NaN, and otherwise propagates the sole NaN. Quiet the selected
		// operand exactly as the floating-point operation would, while keeping
		// its sign and payload independent of Odin's native operand selection.
		selected := right_number if right_nan else left_number
		selected_bits := transmute(u64)selected | u64(0x0008000000000000)
		return number_value(transmute(f64)selected_bits), true
	}
	return number_value(left_number + right_number), true
}

@(private)
quiet_nan :: proc(value: f64) -> f64 {
	return transmute(f64)(transmute(u64)value | u64(0x0008000000000000))
}

@(private)
binary_number_operands :: proc(left, right: ^Value) -> (
	left_number, right_number: f64,
	ok: bool,
) {
	left_ok: bool
	left_number, left_ok = number_value_get(left)
	if !left_ok {
		return 0, 0, false
	}
	right_ok: bool
	right_number, right_ok = number_value_get(right)
	if !right_ok {
		return 0, 0, false
	}
	return left_number, right_number, true
}

@(private)
negative_canonical_nan :: proc() -> f64 {
	return transmute(f64)u64(0xfff8000000000000)
}

// number_subtract borrows both operands and returns an independent inline
// native number. Literal identity ends when jq observes each binary64 cache.
number_subtract :: proc(left, right: ^Value) -> (
	result: Value,
	kind: Number_Arithmetic_Result_Kind,
) {
	a, b, ok := binary_number_operands(left, right)
	if !ok {
		return {}, .Invalid_Operands
	}
	if math.is_nan(a) {
		return number_value(quiet_nan(a)), .Success
	}
	if math.is_nan(b) {
		return number_value(quiet_nan(b)), .Success
	}
	value := a - b
	if math.is_nan(value) {
		// The pinned x86_64 jq oracle produces this for infinity-infinity.
		value = negative_canonical_nan()
	}
	return number_value(value), .Success
}

// number_multiply has the same borrowed, allocation-free ownership contract
// as number_subtract.
number_multiply :: proc(left, right: ^Value) -> (
	result: Value,
	kind: Number_Arithmetic_Result_Kind,
) {
	a, b, ok := binary_number_operands(left, right)
	if !ok {
		return {}, .Invalid_Operands
	}
	if math.is_nan(a) || math.is_nan(b) {
		// Pinned binop_multiply selects the right NaN when both are NaNs.
		selected := b if math.is_nan(b) else a
		return number_value(quiet_nan(selected)), .Success
	}
	value := a * b
	if math.is_nan(value) {
		// The pinned x86_64 jq oracle produces this for zero*infinity.
		value = negative_canonical_nan()
	}
	return number_value(value), .Success
}

// number_divide classifies either sign of binary64 zero before evaluating the
// quotient. A zero divisor returns no Value and cannot be confused with a
// successful infinity or NaN.
number_divide :: proc(left, right: ^Value) -> (
	result: Value,
	kind: Number_Arithmetic_Result_Kind,
) {
	a, b, ok := binary_number_operands(left, right)
	if !ok {
		return {}, .Invalid_Operands
	}
	if b == 0.0 {
		return {}, .Zero_Divisor
	}
	if math.is_nan(a) {
		return number_value(quiet_nan(a)), .Success
	}
	if math.is_nan(b) {
		return number_value(quiet_nan(b)), .Success
	}
	value := a / b
	if math.is_nan(value) {
		// The pinned x86_64 jq oracle produces this for infinity/infinity.
		value = negative_canonical_nan()
	}
	return number_value(value), .Success
}

@(private)
jq_intmax_from_binary64 :: proc(value: f64) -> i64 {
	lower := f64(-9_223_372_036_854_775_808)
	upper := f64(9_223_372_036_854_775_808)
	if value < lower {
		return min(i64)
	}
	if value > upper {
		return max(i64)
	}
	// The pinned C conversion yields INTMAX_MIN at the exactly representable
	// +2^63 boundary; spell it explicitly rather than invoke an out-of-range
	// Odin float-to-integer conversion.
	if value == upper {
		return min(i64)
	}
	return i64(value)
}

// number_modulo mirrors jq 1.8.1 binop_mod, which is integer remainder after
// saturating/truncating binary64-to-intmax conversion. It intentionally is not
// C fmod: fractional divisors with magnitude below one classify as zero.
number_modulo :: proc(left, right: ^Value) -> (
	result: Value,
	kind: Number_Arithmetic_Result_Kind,
) {
	a, b, ok := binary_number_operands(left, right)
	if !ok {
		return {}, .Invalid_Operands
	}
	if math.is_nan(a) || math.is_nan(b) {
		return number_value(transmute(f64)u64(0x7ff8000000000000)), .Success
	}
	// jq's binary64-to-intmax conversion is observable for infinity pairs:
	// the signed C conversion is followed by integer remainder, rather than
	// IEEE fmod. Preserve those four combinations before any Odin conversion.
	if math.is_inf(a) && math.is_inf(b) {
		if a < 0 && b > 0 do return number_value(-1), .Success
		if a > 0 && b < 0 do return number_value(f64(max(i64))), .Success
		return number_value(0), .Success
	}
	divisor := jq_intmax_from_binary64(b)
	if divisor == 0 {
		return {}, .Zero_Divisor
	}
	dividend := jq_intmax_from_binary64(a)
	remainder := i64(0)
	if divisor != -1 {
		remainder = dividend % divisor
	}
	return number_value(f64(remainder)), .Success
}

clone_value :: proc(value: ^Value) -> Value {
	if value == nil || value^ == nil {
		return {}
	}
	storage := value_storage_of(value)
	if storage.kind == .Invalid || !value_local_extent_valid(value) {
		return {}
	}
	if storage.owned_payload != nil {
		p := storage.owned_payload
		if (p.kind == .Array && p.array_retiring) ||
		   (p.kind == .Object && p.object_retiring) {
			return {}
		}
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

@(private)
value_is_retiring :: proc(value: ^Value) -> bool {
	if value == nil || value^ == nil do return false
	storage := value_storage_of(value)
	p := storage.owned_payload
	if p == nil do return false
	return (p.kind == .Array && p.array_retiring) ||
	       (p.kind == .Object && p.object_retiring)
}

take_value :: proc(source: ^Value) -> Value {
	if source == nil {
		return {}
	}
	result := source^
	source^ = {}
	return result
}

@(private)
teardown_next_owner :: proc(p: ^payload) -> (^Value, bool) {
	if p.kind == .Array {
		total_owned := p.array_initialized_length + p.array_retired_count
		if p.array_cleanup_at >= total_owned do return nil, false
		index := p.array_cleanup_at
		if index >= p.array_initialized_length {
			index = p.array_capacity + index - p.array_initialized_length
		}
		return &array_payload_values(p)[index], true
	}
	if p.kind == .Object {
		slots := object_payload_slots(p)
		for p.object_cleanup_at < p.object_capacity {
			slot := &slots[p.object_cleanup_at]
			if !p.object_cleanup_key_done do return &slot.key, true
			return &slot.value, true
		}
	}
	return nil, false
}

@(private)
teardown_advance :: proc(p: ^payload) {
	if p.kind == .Array {
		p.array_cleanup_at += 1
		return
	}
	if p.kind == .Object {
		if !p.object_cleanup_key_done {
			p.object_cleanup_key_done = true
		} else {
			p.object_cleanup_key_done = false
			p.object_cleanup_at += 1
		}
	}
}

// destroy_value retires one owning handle with an intrusive iterative walk.
// Final containers carry their parent continuation while retiring, so depth
// consumes heap payload state rather than process call stack or a separately
// allocated worklist. A failed Free leaves every cursor and owner reachable
// from the supplied root for an allocation-free retry.
destroy_value :: proc(value: ^Value) -> runtime.Allocator_Error {
	if value == nil || value^ == nil do return nil

	current_owner := value
	current_parent: ^payload
	for {
		if current_owner^ == nil || kind_of(current_owner) == .Invalid {
			if current_parent == nil do return nil
			teardown_advance(current_parent)
		} else {
			storage := value_storage_of(current_owner)
			if !value_local_extent_valid(current_owner, true) {
				return .Invalid_Pointer
			}
			p := storage.owned_payload
			if p == nil {
				current_owner^ = {}
				if current_parent == nil do return nil
				teardown_advance(current_parent)
			} else if p.references > 1 {
				p.references -= 1
				current_owner^ = {}
				if current_parent == nil do return nil
				teardown_advance(current_parent)
			} else if p.kind == .Array || p.kind == .Object {
				if p.kind == .Array {
					p.array_retiring = true
				} else {
					p.object_retiring = true
				}
				p.teardown_parent = current_parent
				nested_owner, has_nested := teardown_next_owner(p)
				if has_nested {
					current_parent = p
					current_owner = nested_owner
					continue
				}

				parent := p.teardown_parent
				free_error := runtime.mem_free_with_size(
					p, storage.payload_allocation_bound, p.allocator,
				)
				if free_error != nil && free_error != .Mode_Not_Implemented {
					return free_error
				}
				if free_error == .Mode_Not_Implemented do p.references = 0
				current_owner^ = {}
				if parent == nil do return nil
				current_parent = parent
				teardown_advance(parent)
			} else {
				free_error := runtime.mem_free_with_size(
					p, storage.payload_allocation_bound, p.allocator,
				)
				if free_error != nil && free_error != .Mode_Not_Implemented {
					return free_error
				}
				if free_error == .Mode_Not_Implemented do p.references = 0
				current_owner^ = {}
				if current_parent == nil do return nil
				teardown_advance(current_parent)
			}
		}

		next_owner, has_next := teardown_next_owner(current_parent)
		if has_next {
			current_owner = next_owner
			continue
		}
		current_owner = nil
		// The next iteration completes and frees current_parent. Use the Value
		// slot that owns it: the root or its unchanged parent cleanup cursor.
		parent := current_parent.teardown_parent
		current_parent = parent
		if parent == nil {
			current_owner = value
		} else {
			current_owner, _ = teardown_next_owner(parent)
		}
	}
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
	if !value_local_extent_valid(a) || !value_local_extent_valid(b) {
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
	if !value_local_extent_valid(a) || !value_local_extent_valid(b) {
		return false
	}
	if a_storage.kind != b_storage.kind {
		return false
	}
	switch a_storage.kind {
	case .Invalid:
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
	case .Array:
		return arrays_equal(a, b)
	case .Object:
		return objects_equal(a, b)
	}
	return false
}
