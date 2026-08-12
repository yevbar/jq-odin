# Object destructuring compatibility shard

The bounded object pattern supports one or two simple named entries, such as
`. as {a:$x,b:$y} | [$x,$y]`. Each entry is lowered to an ordinary `Field`
producer followed by a lexical `Binding`; missing fields therefore preserve
jq's null behavior. Iterator-fed, nested, dynamic-key, and `?//` patterns are
not included in this contract.
