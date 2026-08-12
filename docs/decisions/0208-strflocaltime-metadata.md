# Decision 0208: preserve strflocaltime identity

The compiled strftime instruction carries a dedicated boolean alias bit so
`strflocaltime` can report its jq-compatible runtime error without overloading
literal metadata or changing opcode discriminants.
