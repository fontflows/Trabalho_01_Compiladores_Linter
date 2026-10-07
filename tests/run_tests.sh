#!/bin/sh
# Linter e extrator de métricas para miniLua - Trabalho 1
# Integrantes:
#   Francisco Eduardo Fontenele Ramos Neto (15452569)
#   Guilherme Borges de Pádua Barbosa (15653045)
#   Vinicius Botte (15522900)
#
# Roda o linter em cada tests/cases/*.lua, no modo normal e com --extra, e
# compara com tests/cases/*.out (saída padrão, erros e código de saída).
#
# Uso: sh tests/run_tests.sh [caminho-do-linter] [--update]
#   --update  regrava os .out com a saída atual (conferir o diff antes de commitar)

LINTER=${1:-./linter}
UPDATE=$2

case "$LINTER" in
    /*) ;;
    *) LINTER=$(pwd)/$LINTER ;;
esac

cd "$(dirname "$0")/cases" || exit 1

tmp=${TMPDIR:-/tmp}/minilua-teste.$$
trap 'rm -f "$tmp"' EXIT

pass=0
fail=0
for input in *.lua; do
    name=${input%.lua}
    {
        printf '$ linter %s\n' "$input"
        "$LINTER" "$input" 2>&1
        printf '[código de saída: %s]\n\n' "$?"
        printf '$ linter --extra %s\n' "$input"
        "$LINTER" --extra "$input" 2>&1
        printf '[código de saída: %s]\n' "$?"
    } > "$tmp"

    if [ "$UPDATE" = "--update" ]; then
        cp "$tmp" "$name.out"
        echo "atualizado: $name.out"
    elif cmp -s "$tmp" "$name.out"; then
        pass=$((pass + 1))
        echo "ok     $name"
    else
        fail=$((fail + 1))
        echo "FALHOU $name"
        if [ -f "$name.out" ]; then
            diff -u "$name.out" "$tmp" | head -40
        else
            echo "  (falta o arquivo $name.out)"
        fi
    fi
done

[ "$UPDATE" = "--update" ] && exit 0
echo
echo "$pass casos passaram, $fail falharam."
[ "$fail" -eq 0 ]
