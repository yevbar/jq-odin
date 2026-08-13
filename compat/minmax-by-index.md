# Bounded min_by/max_by index keys

Literal nonnegative index keys are lowered through tuple materialization,
existing sort, and indexed selection. General key filters remain deferred.
