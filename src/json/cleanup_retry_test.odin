package json

@(private)
SCALAR_PARSE_CLEANUP_RETRY_LIMIT :: 3

@(private)
scalar_parse_cleanup_retry_result :: enum {
	Terminal,
	Non_Retryable,
	Exhausted,
}

@(private)
retry_scalar_parse_error_cleanup :: proc(err: ^Scalar_Parse_Error) -> (
	result: scalar_parse_cleanup_retry_result,
	retries: int,
) {
	// Callers require Terminal and an inert error. Returning a distinct result
	// makes non-retryable and exhausted errors fail deterministically in the
	// calling test instead of entering an unbounded control loop.
	if err == nil {
		return .Non_Retryable, 0
	}
	if err.kind == .None {
		return .Terminal, 0
	}
	if err.kind != .Scratch_Cleanup_Failure {
		return .Non_Retryable, 0
	}
	for retries < SCALAR_PARSE_CLEANUP_RETRY_LIMIT {
		_ = destroy_scalar_parse_error(err)
		retries += 1
		if err.kind == .None {
			return .Terminal, retries
		}
		if err.kind != .Scratch_Cleanup_Failure {
			return .Non_Retryable, retries
		}
	}
	return .Exhausted, retries
}
