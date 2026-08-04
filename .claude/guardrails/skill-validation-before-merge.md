---
name: skill-validation-before-merge
description: Nenhuma skill proxyme é considerada "feita" sem ter rodado de ponta a ponta em contexto real.
---

## Rule
Antes de marcar qualquer skill proxyme como completa, ela deve ter sido executada uma vez em contexto real (não simulado, não leitura de spec). A evidência de execução deve estar presente como: (1) test-plan inline no arquivo de skill, ou (2) arquivo `.test.sh` no mesmo diretório documentando o que foi testado e o resultado observado. Skill sem evidência de execução real = work in progress.
