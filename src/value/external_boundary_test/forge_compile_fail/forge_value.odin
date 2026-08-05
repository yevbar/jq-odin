package forge_value

import value "jq:value"

forge_value_storage :: proc() {
	forged: value.Value = value.Value_Handle{1, 2, 3, 4, 5, 6}
	_ = forged
}
