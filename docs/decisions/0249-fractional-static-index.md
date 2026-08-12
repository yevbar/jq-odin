# Fractional static array assignment indices

Static numeric array assignment truncates fractional indices toward zero before
delegating to the existing owned array mutation path, matching jq. NaN,
infinity, dynamic indices, and nested path mutation remain deferred.
