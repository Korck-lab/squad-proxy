---
name: no-credential-in-specs
description: Specs, plans e docs nunca contêm emails, API keys, tokens ou paths com dados pessoais — usar placeholders.
---

## Rule
Nenhum arquivo de spec, plan, skill ou README pode conter: endereços de email reais, API keys, tokens de autenticação, account IDs, ou paths absolutos com dados pessoais (ex: `/Users/nome-real/...`). Quando necessário exemplificar, usar placeholders explícitos como `[USER_EMAIL]`, `[API_KEY]`, `$HOME/[PROJECT]`. Violação deve ser corrigida antes de qualquer commit ou compartilhamento do arquivo.
