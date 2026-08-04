---
name: skill-validation-before-merge
description: No proxyme skill counts as "done" until it has run end to end in a real context.
---

## Rule
Before any proxyme skill is marked complete, it must have been executed once in a real context — not simulated, not read off a spec. The evidence of that run must be present as either (1) an inline test plan in the skill file, or (2) a `.test.sh` file in the same directory documenting what was tested and the result observed. A skill with no real-run evidence is work in progress.
