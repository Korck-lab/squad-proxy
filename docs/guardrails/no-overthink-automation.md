---
name: no-overthink-automation
description: Skills e specs com mais de 5 condicionais são sobre-engenharia — simplificar até ser executável em uma sessão.
---

## Rule
Qualquer skill, spec ou plano de automação Claude Code que contenha mais de 5 condicionais distintos (if/else, casos especiais, fallbacks em cadeia) deve ser refatorado antes de ser considerado pronto. O critério é: um agente novo consegue executar do início ao fim em uma única sessão sem ambiguidade? Se não, está complexo demais. Remover camadas até que a resposta seja sim.
