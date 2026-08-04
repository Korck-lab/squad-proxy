---
name: no-overthink-automation
description: Skills and specs carrying more than 5 conditionals are over-engineered — simplify until one session can execute them.
---

## Rule
Any Claude Code skill, spec or automation plan holding more than 5 distinct conditionals (if/else, special cases, chained fallbacks) is refactored before it counts as ready. The test: can a fresh agent execute it start to finish in a single session with no ambiguity? If not, it is too complex. Remove layers until the answer is yes.
