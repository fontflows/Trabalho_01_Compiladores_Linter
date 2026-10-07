# Linter e extrator de métricas para miniLua

Trabalho 1 de Compiladores. Integrantes:

- Francisco Eduardo Fontenele Ramos Neto (15452569)
- Guilherme Borges de Pádua Barbosa (15653045)
- Vinicius Botte (15522900)

O programa lê código miniLua (o subconjunto de Lua do enunciado) e imprime um relatório com linhas físicas e lógicas, as funções definidas e, para cada uma, parâmetros, chamadas externas, profundidade máxima de aninhamento e complexidade ciclomática, seguido dos alertas de estilo (magic numbers e comandos múltiplos na mesma linha). O analisador léxico é feito em Flex e o sintático em Bison; as métricas são calculadas nas ações da gramática, sem construir AST.

O relatório com as escolhas de projeto está em `relatorio.pdf`.

## Dependências

Flex (2.5.35 ou mais novo), Bison (3.0 ou mais novo), um compilador C++11 e GNU make.

- **Debian/Ubuntu:** `sudo apt install build-essential flex bison`
- **Fedora:** `sudo dnf install gcc-c++ make flex bison`
- **macOS:** `xcode-select --install` (traz clang, make e flex) e `brew install bison`. O bison do sistema é o 2.3, velho demais; o Makefile encontra sozinho o do Homebrew em `/opt/homebrew` ou `/usr/local`.
- **Windows:** instale o [MSYS2](https://www.msys2.org), abra o terminal "MSYS2 UCRT64" e rode `pacman -S mingw-w64-ucrt-x86_64-gcc make flex bison`. No Windows o executável é linkado com `-static`, então roda fora do terminal do MSYS2 também.

## Compilar

```sh
make
```

Gera o executável `linter` (`linter.exe` no Windows). Os arquivos gerados pelo Flex e pelo Bison ficam em `build/`. `make clean` apaga tudo.

## Rodar

```sh
./linter tests/cases/teste2.lua          # um arquivo
./linter a.lua b.lua                     # vários, um relatório para cada
./linter < programa.lua                  # entrada padrão
./linter --extra tests/cases/extras.lua  # com os alertas adicionais
```

O código de saída é 0 quando a análise termina (mesmo com alertas), 1 em erro léxico, sintático ou de leitura de arquivo, e 2 em opção inválida. Erros saem na saída de erro no formato `arquivo:linha:coluna: mensagem`, por exemplo:

```text
erro_sintaxe.lua:6:1: erro de sintaxe: fim do arquivo inesperado; a função da linha 1 não foi fechada com 'end'
```

Saída real para o exemplo II.2 do enunciado:

```text
$ ./linter tests/cases/teste2.lua
=== RELATÓRIO DE ANÁLISE ===
Arquivo: teste2.lua
Linhas Físicas: 15
Linhas Lógicas: 12
Funções Definidas: 1

--- Função: processa_pagamento ---
Parâmetros: 2 (valor, tipo_cliente)
Chamadas de Funções Externas: 1 (registra_log)
Profundidade Máxima de Aninhamento: 2
Complexidade Ciclomática: 4 (1 base + 1 if + 1 elseif + 1 for)

--- Alertas do Linter ---
[Aviso] Linha 2: Múltiplos comandos na mesma linha detectados.
[Aviso] Linha 5: 'Magic Number' detectado (0.15). Considere extrair para uma constante.
[Aviso] Linha 7: 'Magic Number' detectado (0.05). Considere extrair para uma constante.
[Aviso] Linha 10: 'Magic Number' detectado (3). Considere extrair para uma constante.
============================
```

## Testes

```sh
make test
```

O script `tests/run_tests.sh` roda o linter em cada `tests/cases/*.lua`, no modo normal e com `--extra`, e compara saída, erros e código de saída com o `.out` correspondente. O resultado esperado é:

```text
23 casos passaram, 0 falharam.
```

Os casos `teste1`, `teste2` e `teste3` são os exemplos do enunciado. Os `.lua` de teste são dados de entrada e não levam o cabeçalho com os nomes do grupo, porque um comentário a mais mudaria as linhas que eles testam (e o `vazio.lua` deixaria de ser vazio). Os outros cobrem comentários de bloco (inclusive com nível, `--[==[ ]==]`), `--` e `;` dentro de strings, escapes, strings longas, arquivo com CRLF, arquivo sem quebra de linha final, arquivo vazio, só comentários, números hexadecimais e em notação científica, funções aninhadas, anônimas, locais e métodos, `repeat`, código fora de funções, comandos múltiplos, os alertas extras e erros léxicos e sintáticos.

## Alertas extras (`--extra`)

Com `--extra` o linter também aponta:

- função com mais de 5 parâmetros, profundidade de aninhamento maior que 4, complexidade ciclomática maior que 10 ou mais de 50 linhas lógicas;
- variável local, parâmetro, variável de laço ou função local que nunca é lida (nomes começando com `_` são ignorados);
- atribuição a variável global dentro de função (provável `local` esquecido);
- literal comparado com `==` ou `~=` (veja a decisão sobre magic numbers abaixo);
- arquivo que não termina com quebra de linha.

Esses alertas ficam atrás da opção para que a saída padrão dos três exemplos continue igual à do enunciado.

## Decisões de interpretação e inconsistências do enunciado

**Linhas físicas** são o número de quebras de linha do arquivo, como no `wc -l`. É a única regra que dá as 44 linhas do teste3, cujo código tem 45 linhas: o arquivo original não terminava em quebra de linha, e o `teste3.lua` daqui também não termina. Uma última linha sem `\n` não entra na contagem de linhas físicas, mas entra na de lógicas se tiver código; o `--extra` avisa quando isso acontece.

**Linhas lógicas** são as linhas com pelo menos um token. O enunciado diz 11 para o teste2, mas o código tem 12 linhas que não estão em branco nem são comentário, e não achamos regra que dê 11 sem quebrar os outros dois exemplos. Consideramos erro do enunciado; o linter imprime 12.

**Contagem de funções.** O item I.1 pede a contagem de funções, mas os exemplos não têm essa linha. Acrescentamos `Funções Definidas: N` logo depois das linhas lógicas. Fora isso e das 12 linhas lógicas do teste2, a saída dos três exemplos é igual à do enunciado.

**Magic numbers.** Qualquer literal diferente de 0 e 1 é apontado, exceto quando ele é a expressão inteira atribuída a uma variável ou campo (`local x = 5`, `x = -5`, `{ limite = 10 }`, `{ 10, 20 }`). Isso pega o `3` de `for i = 1, 3` e o `999` passado como argumento, como nos exemplos. O teste2 não aponta o `2` de `tipo_cliente == 2`, mas o teste3 aponta o `18` de `idade < 18`; a regra que reproduz os dois é isentar literais comparados por igualdade, que funcionam como o rótulo de um caso num `switch`. Com `--extra` esses literais também são apontados.

**Profundidade.** O enunciado cita `if`, `while` e `for` e não fala do `repeat`. Tratamos o `repeat` como os outros laços (soma 1). `elseif` e `else` não somam, e um bloco `do ... end` também não, por não ser estrutura de controle. Função aninhada tem a própria contagem, começando em 1, e não altera a da função de fora. A cadeia `(função -> for -> for -> if)` só aparece a partir de profundidade 3, como nos exemplos.

**Complexidade.** O detalhamento lista as estruturas na ordem em que aparecem pela primeira vez na função, depois `and` e depois `or`, que é a ordem dos quatro exemplos.

**Chamadas externas.** Chamadas recursivas não contam (inclusive `self:m()` dentro de `function Classe:m()`). As chamadas dentro de uma função aninhada ou anônima pertencem a ela, não à de fora. Os nomes aparecem como no código (`string.format`, `fila:pronta`), na ordem do texto, com repetições.

**Comandos múltiplos.** O alerta sai quando um comando começa na mesma linha em que o comando anterior do mesmo bloco termina, como em `a = 1; b = 2` ou `a = 1 b = 2`. Um bloco inteiro numa linha, como `if x then return end`, não é apontado, porque o `return` é o único comando do bloco dele.

**Código fora de funções.** Se houver chamadas ou estruturas de controle no nível do arquivo, aparece uma seção `--- Escopo Global (fora de funções) ---` com as mesmas métricas. Arquivos que só definem funções, como os três exemplos, não têm essa seção.

**Além do miniLua.** Para analisar código Lua comum, a gramática também aceita tabelas, indexação (`t[i]`, `t.campo`), chamadas de método (`obj:m()`), `for ... in`, `local function`, funções anônimas, `...`, `//` e strings longas. Uma função anônima atribuída a uma variável ou campo recebe o nome dele no relatório. A ambiguidade de Lua com `(` no início de linha é resolvida como no Lua 5.2: a chamada continua.

## Arquivos

```text
src/lexer.l        analisador léxico (Flex)
src/parser.y       gramática e ações semânticas (Bison)
src/analyzer.cpp   métricas, tabela de símbolos, alertas e relatório
src/analyzer.hpp   interface usada pelas ações do lexer e do parser
src/main.cpp       opções de linha de comando e laço pelos arquivos
tests/             casos de teste e script que os executa
relatorio.pdf      relatório do trabalho
```

`make zip` gera o arquivo de entrega `trabalho1-linter-minilua.zip` só com fontes, testes e documentação. `make conflicts` roda o Bison com `-Wcounterexamples` (precisa do Bison 3.7+) para depurar a gramática caso ela passe a ter conflitos; hoje ela não tem nenhum, e o `%expect 0` faz o build falhar se aparecer algum.
