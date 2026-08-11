# Decision 0183: retain fromjson parse diagnostics

`fromjson` parse failures use the existing owned `User_Error` transport so
their message is both printed by the CLI and supplied to a `catch` filter.
The bounded formatter covers invalid numeric literals and malformed quoted
object keys; other parser-error wording remains a follow-up.
