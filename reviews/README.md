# Adversarial reviews

Reviewer agents use one prompt from `reviews/prompts/` in a fresh environment.
They post findings on the pull request; they do not edit the author branch.

Each finding includes severity, file and line, violated behavior or invariant,
evidence, a reproduction command or test, and the smallest credible remedy.
An approval states what was examined and which commands ran.

