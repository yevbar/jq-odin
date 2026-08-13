# NaN slice/index bounds

NaN slice bounds clamp to the corresponding open endpoint, while a NaN scalar
index yields null as jq does.
