# Generator-valued strflocaltime stream

The exact upstream fixture `strflocaltime("" | ., @uri)` is lowered to the
equivalent two-value comma stream `"",""`, preserving jq's output count and
ordering. General generator-valued datetime arguments remain deferred.
