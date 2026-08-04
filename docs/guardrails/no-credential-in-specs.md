---
name: no-credential-in-specs
description: Specs, plans and docs never contain emails, API keys, tokens or paths holding personal data — use placeholders.
---

## Rule
No spec, plan, skill or README file may contain real email addresses, API keys, authentication tokens, account IDs, or absolute paths holding personal data (for example `/Users/real-name/...`). Where an example is needed, use explicit placeholders such as `[USER_EMAIL]`, `[API_KEY]`, `$HOME/[PROJECT]`. A violation is fixed before the file is committed or shared.
