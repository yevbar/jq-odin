// Package syntax owns jq tokens, source syntax, and parsing.
package syntax

import "base:runtime"
import diagnostic "jq:diagnostic"

// Token_Kind names jq language tokens. Assignment kinds describe jq path and
// stream operators; they are not Odin storage-assignment operations.
Token_Kind :: enum {
	Invalid,

	Dot,
	Question,
	Assign,
	Semicolon,
	Comma,
	Colon,
	Pipe,
	Plus,
	Minus,
	Multiply,
	Divide,
	Modulo,
	Dollar,
	Less,
	Greater,

	Open_Bracket,
	Close_Bracket,
	Open_Brace,
	Close_Brace,
	Open_Paren,
	Close_Paren,

	Not_Equal,
	Equal,
	As,
	Import,
	Include,
	Module,
	Def,
	If,
	Then,
	Else,
	Else_If,
	And,
	Or,
	End,
	Reduce,
	Foreach,
	Defined_Or,
	Try,
	Catch,
	Label,
	Break,
	Location,
	Assign_Pipe,
	Assign_Plus,
	Assign_Minus,
	Assign_Multiply,
	Assign_Divide,
	Assign_Modulo,
	Assign_Defined_Or,
	Less_Equal,
	Greater_Equal,
	Recurse,
	Alternation,

	Identifier,
	Binding,
	Format,
	Field,

	// Reserved for later evidence-backed literal scanning. This milestone does
	// not emit these disputed token kinds.
	Number_Placeholder,
	String_Placeholder,
}

// Token is a non-owning description of bytes in the scanner's borrowed Source.
// value_span is present only when has_value_span is true, and then is contained
// in span. The caller keeps the exact Source and its backing strings alive and
// unchanged while resolving either span.
Token :: struct {
	kind:           Token_Kind,
	span:           diagnostic.Span,
	value_span:     diagnostic.Span,
	has_value_span: bool,
}

Scan_Outcome_Kind :: enum {
	Token,
	End_Of_Input,
	Lexical_Error,
	Resource_Failure,
}

// Scan_Outcome contains token only for .Token. error_span is present only for
// .Lexical_Error. Resource failure is deliberately not an input diagnostic.
Scan_Outcome :: struct {
	kind:           Scan_Outcome_Kind,
	token:          Token,
	error_span:     diagnostic.Span,
	has_error_span: bool,
}

Delimiter :: enum u8 {
	Paren,
	Bracket,
	Brace,
}

Scanner_State :: enum u8 {
	Uninitialized,
	Active,
	Resource_Failed,
	Destroyed,
}

// Scanner incrementally scans one borrowed Source.
//
// delimiters is owned by the scanner and allocated with allocator. The
// allocator and all of its backing state must remain valid until
// destroy_scanner. A live Scanner must stay at the address passed to
// init_scanner: copying it with Odin `=` is forbidden. Operations assert this
// address invariant so an accidental live copy cannot free or mutate shared
// scanner storage.
Scanner :: struct {
	source:     diagnostic.Source,
	offset:     int,
	delimiters: [dynamic]Delimiter,
	allocator:  runtime.Allocator,
	state:      Scanner_State,
	self:       ^Scanner,
}

// init_scanner initializes scanner without allocating. It rejects an invalid
// or stale Source. scanner must be destroyed before it is initialized again.
init_scanner :: proc(
	scanner: ^Scanner,
	source: diagnostic.Source,
	allocator: runtime.Allocator,
) -> bool {
	if scanner == nil ||
	   scanner.state == .Active ||
	   scanner.state == .Resource_Failed {
		return false
	}
	if _, ok := diagnostic.make_span(source, 0, 0); !ok {
		return false
	}

	scanner^ = {}
	scanner.source = source
	scanner.allocator = allocator
	scanner.delimiters.allocator = allocator
	scanner.state = .Active
	scanner.self = scanner
	return true
}

// destroy_scanner releases scanner-owned delimiter storage with the allocator
// recorded by init_scanner. It is idempotent for the original Scanner value.
destroy_scanner :: proc(scanner: ^Scanner) {
	if scanner == nil || scanner.state == .Destroyed ||
	   scanner.state == .Uninitialized {
		return
	}
	assert(scanner.self == scanner, "a live syntax.Scanner was copied")
	delete(scanner.delimiters)
	scanner.delimiters = nil
	scanner.source = {}
	scanner.offset = 0
	scanner.allocator = {}
	scanner.state = .Destroyed
	scanner.self = nil
}

// next_token advances exactly once. Resource failure is terminal, atomic, and
// repeatable: later calls return .Resource_Failure without consuming input or
// allocating. Lexical errors consume the one-byte offending input, except that
// a mismatched closer consumes that closer as one complete offending token.
next_token :: proc(scanner: ^Scanner) -> Scan_Outcome {
	assert(scanner != nil && scanner.self == scanner,
	       "syntax.Scanner must be initialized and must not be copied")
	assert(scanner.state != .Destroyed, "syntax.Scanner was destroyed")

	if scanner.state == .Resource_Failed {
		return Scan_Outcome{kind = .Resource_Failure}
	}

	bytes := diagnostic.source_bytes(scanner.source)
	for scanner.offset < len(bytes) {
		byte := bytes[scanner.offset]
		if is_whitespace(byte) {
			scanner.offset += 1
			continue
		}
		if byte == '#' {
			skip_comment(scanner, bytes)
			continue
		}
		break
	}

	if scanner.offset == len(bytes) {
		return Scan_Outcome{kind = .End_Of_Input}
	}

	start := scanner.offset

	if bytes[start] == '@' && start + 1 < len(bytes) &&
	   is_format_byte(bytes[start+1]) {
		end := start + 2
		for end < len(bytes) && is_format_byte(bytes[end]) {
			end += 1
		}
		scanner.offset = end
		return valued_token_outcome(scanner.source, .Format, start, end, start+1, end)
	}

	if bytes[start] == '$' && start + 1 < len(bytes) &&
	   is_identifier_start(bytes[start+1]) {
		end, valid := scan_namespaced_identifier(bytes, start+1)
		if valid {
			scanner.offset = end
			if bytes[start:end] == "$__loc__" {
				return token_outcome(scanner.source, .Location, start, end)
			}
			return valued_token_outcome(scanner.source, .Binding, start, end, start+1, end)
		}
	}

	if bytes[start] == '.' && start + 1 < len(bytes) &&
	   is_identifier_start(bytes[start+1]) {
		end := scan_identifier_segment(bytes, start+1)
		scanner.offset = end
		return valued_token_outcome(scanner.source, .Field, start, end, start+1, end)
	}

	if is_identifier_start(bytes[start]) {
		end, valid := scan_namespaced_identifier(bytes, start)
		if valid {
			spelling := bytes[start:end]
			kind := reserved_word_kind(spelling)
			scanner.offset = end
			if kind == .Invalid {
				kind = .Identifier
			}
			return token_outcome(scanner.source, kind, start, end)
		}
	}

	if kind, width, matched := match_fixed(bytes, start); matched {
		if is_opener(kind) {
			delimiter := delimiter_for_opener(kind)
			_, append_error := append_elem(&scanner.delimiters, delimiter)
			if append_error != nil {
				scanner.state = .Resource_Failed
				return Scan_Outcome{kind = .Resource_Failure}
			}
		} else if is_closer(kind) {
			expected := delimiter_for_closer(kind)
			if len(scanner.delimiters) == 0 ||
			   scanner.delimiters[len(scanner.delimiters)-1] != expected {
				scanner.offset += width
				return lexical_error(scanner.source, start, start + width)
			}
			pop(&scanner.delimiters)
		}

		scanner.offset += width
		return token_outcome(scanner.source, kind, start, start + width)
	}

	scanner.offset += 1
	return lexical_error(scanner.source, start, start + 1)
}

@(private="package")
skip_comment :: proc(scanner: ^Scanner, bytes: string) {
	scanner.offset += 1 // '#'
	for scanner.offset < len(bytes) {
		i := scanner.offset
		if bytes[i] == '\\' && i + 1 < len(bytes) {
			if bytes[i+1] == '\\' || bytes[i+1] == '\n' {
				scanner.offset += 2
				continue
			}
			if bytes[i+1] == '\r' && i + 2 < len(bytes) &&
			   bytes[i+2] == '\n' {
				scanner.offset += 3
				continue
			}
		}
		if bytes[i] == '\n' {
			scanner.offset += 1
			return
		}
		if bytes[i] == '\r' && i + 1 < len(bytes) &&
		   bytes[i+1] == '\n' {
			scanner.offset += 2
			return
		}
		scanner.offset += 1
	}
}

@(private="package")
match_fixed :: proc(bytes: string, start: int) -> (Token_Kind, int, bool) {
	Fixed :: struct {
		text: string,
		kind: Token_Kind,
	}
	// Longest spellings precede their prefixes, matching flex's longest-match
	// rule and rule-order tie breaking.
	fixed := [?]Fixed{
		{"//=", .Assign_Defined_Or},
		{"?//", .Alternation},
		{"!=", .Not_Equal},
		{"==", .Equal},
		{"//", .Defined_Or},
		{"|=", .Assign_Pipe},
		{"+=", .Assign_Plus},
		{"-=", .Assign_Minus},
		{"*=", .Assign_Multiply},
		{"/=", .Assign_Divide},
		{"%=", .Assign_Modulo},
		{"<=", .Less_Equal},
		{">=", .Greater_Equal},
		{"..", .Recurse},
		{".", .Dot},
		{"?", .Question},
		{"=", .Assign},
		{";", .Semicolon},
		{",", .Comma},
		{":", .Colon},
		{"|", .Pipe},
		{"+", .Plus},
		{"-", .Minus},
		{"*", .Multiply},
		{"/", .Divide},
		{"%", .Modulo},
		{"$", .Dollar},
		{"<", .Less},
		{">", .Greater},
		{"[", .Open_Bracket},
		{"]", .Close_Bracket},
		{"{", .Open_Brace},
		{"}", .Close_Brace},
		{"(", .Open_Paren},
		{")", .Close_Paren},
	}
	for item in fixed {
		if has_prefix_at(bytes, start, item.text) {
			return item.kind, len(item.text), true
		}
	}
	return .Invalid, 0, false
}

@(private="package")
reserved_word_kind :: proc(word: string) -> Token_Kind {
	switch word {
	case "as":      return .As
	case "import":  return .Import
	case "include": return .Include
	case "module":  return .Module
	case "def":     return .Def
	case "if":      return .If
	case "then":    return .Then
	case "else":    return .Else
	case "elif":    return .Else_If
	case "and":     return .And
	case "or":      return .Or
	case "end":     return .End
	case "reduce":  return .Reduce
	case "foreach": return .Foreach
	case "try":     return .Try
	case "catch":   return .Catch
	case "label":   return .Label
	case "break":   return .Break
	}
	return .Invalid
}

@(private="package")
scan_namespaced_identifier :: proc(bytes: string, start: int) -> (int, bool) {
	end := scan_identifier_segment(bytes, start)
	for end + 2 <= len(bytes) &&
	    bytes[end] == ':' && bytes[end+1] == ':' {
		next := end + 2
		if next >= len(bytes) || !is_identifier_start(bytes[next]) {
			return end, true
		}
		end = scan_identifier_segment(bytes, next)
	}
	return end, true
}

@(private="package")
scan_identifier_segment :: proc(bytes: string, start: int) -> int {
	end := start + 1
	for end < len(bytes) && is_identifier_continue(bytes[end]) {
		end += 1
	}
	return end
}

@(private="package")
token_outcome :: proc(
	source: diagnostic.Source,
	kind: Token_Kind,
	start, end: int,
) -> Scan_Outcome {
	span, ok := diagnostic.make_span(source, start, end)
	assert(ok)
	return Scan_Outcome{
		kind = .Token,
		token = Token{kind = kind, span = span},
	}
}

@(private="package")
valued_token_outcome :: proc(
	source: diagnostic.Source,
	kind: Token_Kind,
	start, end, value_start, value_end: int,
) -> Scan_Outcome {
	span, span_ok := diagnostic.make_span(source, start, end)
	value_span, value_ok := diagnostic.make_span(source, value_start, value_end)
	assert(span_ok && value_ok)
	return Scan_Outcome{
		kind = .Token,
		token = Token{
			kind = kind,
			span = span,
			value_span = value_span,
			has_value_span = true,
		},
	}
}

@(private="package")
lexical_error :: proc(
	source: diagnostic.Source,
	start, end: int,
) -> Scan_Outcome {
	span, ok := diagnostic.make_span(source, start, end)
	assert(ok)
	return Scan_Outcome{
		kind = .Lexical_Error,
		error_span = span,
		has_error_span = true,
	}
}

@(private="package")
has_prefix_at :: proc(bytes: string, start: int, prefix: string) -> bool {
	if start < 0 || len(bytes) - start < len(prefix) {
		return false
	}
	return bytes[start:start+len(prefix)] == prefix
}

@(private="package")
is_whitespace :: proc(byte: u8) -> bool {
	return byte == ' ' || byte == '\r' || byte == '\n' || byte == '\t'
}

@(private="package")
is_identifier_start :: proc(byte: u8) -> bool {
	return byte == '_' ||
	       byte >= 'a' && byte <= 'z' ||
	       byte >= 'A' && byte <= 'Z'
}

@(private="package")
is_identifier_continue :: proc(byte: u8) -> bool {
	return is_identifier_start(byte) || byte >= '0' && byte <= '9'
}

@(private="package")
is_format_byte :: proc(byte: u8) -> bool {
	return is_identifier_continue(byte)
}

@(private="package")
is_opener :: proc(kind: Token_Kind) -> bool {
	return kind == .Open_Paren || kind == .Open_Bracket || kind == .Open_Brace
}

@(private="package")
is_closer :: proc(kind: Token_Kind) -> bool {
	return kind == .Close_Paren || kind == .Close_Bracket || kind == .Close_Brace
}

@(private="package")
delimiter_for_opener :: proc(kind: Token_Kind) -> Delimiter {
	#partial switch kind {
	case .Open_Paren:   return .Paren
	case .Open_Bracket: return .Bracket
	case .Open_Brace:   return .Brace
	}
	unreachable()
}

@(private="package")
delimiter_for_closer :: proc(kind: Token_Kind) -> Delimiter {
	#partial switch kind {
	case .Close_Paren:   return .Paren
	case .Close_Bracket: return .Bracket
	case .Close_Brace:   return .Brace
	}
	unreachable()
}
