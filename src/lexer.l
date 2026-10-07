/*
 * Linter e extrator de métricas para miniLua - Trabalho 1
 * Integrantes:
 *   Francisco Eduardo Fontenele Ramos Neto (15452569)
 *   Guilherme Borges de Pádua Barbosa (15653045)
 *   Vinicius Botte (15522900)
 *
 * Analisador léxico do miniLua. Além de gerar os tokens, conta as linhas
 * físicas e marca quais linhas têm código (linhas lógicas). Comentários são
 * descartados aqui e nunca chegam ao parser.
 */

%{
#include <cstdio>
#include <string>

#include "analyzer.hpp"
#include "parser.tab.hpp"

static int cur_line = 1;
static int cur_col = 1;

/* Colchetes longos ([[...]], [==[...]==]) servem tanto para strings quanto
 * para comentários de bloco; o nível é a quantidade de '='. */
static int bracket_level = 0;
static bool bracket_is_string = false;
static YYLTYPE bracket_start;

static void advance(const char* text, int len)
{
    yylloc.first_line = yylloc.last_line = cur_line;
    yylloc.first_column = yylloc.last_column = cur_col;
    for (int i = 0; i < len; ++i) {
        yylloc.last_line = cur_line;
        yylloc.last_column = cur_col;
        if (text[i] == '\n') {
            ++cur_line;
            cur_col = 1;
        } else {
            ++cur_col;
        }
    }
    lint::on_text(text, len);
}

static int lex_error(const std::string& message)
{
    lint::error(yylloc.first_line, yylloc.first_column, "erro léxico: " + message);
    return T_LEXERROR;
}

static bool is_hex(char c)
{
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

/* Confere as sequências de escape de uma string entre aspas. Em caso de erro
 * devolve false e coloca a sequência inválida em bad. */
static bool check_escapes(const char* s, int len, std::string& bad)
{
    for (int i = 1; i < len - 1; ++i) {
        if (s[i] != '\\')
            continue;
        char c = s[++i];
        switch (c) {
        case 'a': case 'b': case 'f': case 'n': case 'r': case 't': case 'v':
        case '\\': case '"': case '\'': case '\n': case 'z':
            break;
        case '\r':
            if (s[i + 1] == '\n')
                ++i;
            break;
        case 'x':
            if (!is_hex(s[i + 1]) || !is_hex(s[i + 2])) {
                bad = std::string(s + i - 1, (i + 3 < len) ? 4 : len - i);
                return false;
            }
            i += 2;
            break;
        case 'u': {
            int j = i + 1;
            if (s[j] != '{' || !is_hex(s[j + 1])) {
                bad = "\\u";
                return false;
            }
            for (++j; is_hex(s[j]); ++j)
                ;
            if (s[j] != '}') {
                bad = "\\u";
                return false;
            }
            i = j;
            break;
        }
        default:
            if (c >= '0' && c <= '9') {
                int value = 0, j = i;
                for (; j < i + 3 && s[j] >= '0' && s[j] <= '9'; ++j)
                    value = value * 10 + (s[j] - '0');
                if (value > 255) {
                    bad = std::string(s + i - 1, j - i + 1);
                    return false;
                }
                i = j - 1;
            } else {
                bad = std::string("\\") + c;
                return false;
            }
        }
    }
    return true;
}

#define YY_USER_ACTION advance(yytext, (int)yyleng);
#define TOKEN(t) do { lint::mark_code(yylloc.first_line, yylloc.last_line); return (t); } while (0)
#define AT_EOF() do { yylloc.first_line = yylloc.last_line = cur_line; \
                      yylloc.first_column = yylloc.last_column = cur_col; \
                      lint::end_of_input(cur_line); } while (0)
%}

%option noyywrap nounput noinput never-interactive 8bit
%x LINE_COMMENT LONG_BRACKET

D        [0-9]
H        [0-9a-fA-F]
EXP      [eE][+-]?{D}+
HEXP     [pP][+-]?{D}+
 /* \z pula os espaços e quebras de linha que vêm depois dele (Lua 5.2+) */
ESC      \\(z[ \t\r\n\f\v]*|\r\n|.|\n)

%%

[ \t\r\f\v]+                ;
\n                          ;

"--"\[=*\[                  {
                                bracket_level = (int)yyleng - 4;
                                bracket_is_string = false;
                                bracket_start = yylloc;
                                BEGIN(LONG_BRACKET);
                            }
"--"                        { BEGIN(LINE_COMMENT); }
<LINE_COMMENT>[^\n]+        ;
<LINE_COMMENT>\n            { BEGIN(INITIAL); }
<LINE_COMMENT><<EOF>>       { BEGIN(INITIAL); AT_EOF(); yyterminate(); }

\[=*\[                      {
                                bracket_level = (int)yyleng - 2;
                                bracket_is_string = true;
                                bracket_start = yylloc;
                                BEGIN(LONG_BRACKET);
                            }
<LONG_BRACKET>\]=*\]        {
                                if ((int)yyleng - 2 == bracket_level) {
                                    BEGIN(INITIAL);
                                    if (bracket_is_string) {
                                        yylloc.first_line = bracket_start.first_line;
                                        yylloc.first_column = bracket_start.first_column;
                                        TOKEN(T_STRING);
                                    }
                                } else {
                                    /* "]=]]" com nível 0: o último ']' ainda pode fechar */
                                    yyless(yyleng - 1);
                                    --cur_col;
                                }
                            }
<LONG_BRACKET>[^\]\n]+      ;
<LONG_BRACKET>\n            ;
<LONG_BRACKET>\]            ;
<LONG_BRACKET><<EOF>>       {
                                BEGIN(INITIAL);
                                yylloc = bracket_start;
                                return lex_error(bracket_is_string ? "string longa não terminada"
                                                                   : "comentário de bloco não terminado");
                            }

"and"                       TOKEN(T_AND);
"break"                     TOKEN(T_BREAK);
"do"                        TOKEN(T_DO);
"else"                      TOKEN(T_ELSE);
"elseif"                    TOKEN(T_ELSEIF);
"end"                       TOKEN(T_END);
"false"                     TOKEN(T_FALSE);
"for"                       TOKEN(T_FOR);
"function"                  TOKEN(T_FUNCTION);
"if"                        TOKEN(T_IF);
"in"                        TOKEN(T_IN);
"local"                     TOKEN(T_LOCAL);
"nil"                       TOKEN(T_NIL);
"not"                       TOKEN(T_NOT);
"or"                        TOKEN(T_OR);
"repeat"                    TOKEN(T_REPEAT);
"return"                    TOKEN(T_RETURN);
"then"                      TOKEN(T_THEN);
"true"                      TOKEN(T_TRUE);
"until"                     TOKEN(T_UNTIL);
"while"                     TOKEN(T_WHILE);

[A-Za-z_][A-Za-z0-9_]*      { yylval.str = lint::intern(yytext); TOKEN(T_NAME); }

{D}+(\.{D}*)?{EXP}?         |
\.{D}+{EXP}?                |
0[xX]{H}+(\.{H}*)?{HEXP}?   |
0[xX]\.{H}+{HEXP}?          {
                                yylval.num = lint::number_literal(yytext, yylloc.first_line, yylloc.first_column);
                                TOKEN(T_NUMBER);
                            }
 /* Só vence as regras acima quando o número vem grudado em letras ou pontos,
  * como 3abc, 0x ou 1..2, que o Lua também rejeita. */
({D}|\.{D})[A-Za-z0-9_.]*   { return lex_error(std::string("número malformado '") + yytext + "'"); }

\"({ESC}|[^\\"\n])*\"       |
\'({ESC}|[^\\'\n])*\'       {
                                std::string bad;
                                if (!check_escapes(yytext, (int)yyleng, bad))
                                    return lex_error("sequência de escape inválida '" + bad + "' na string");
                                TOKEN(T_STRING);
                            }
\"({ESC}|[^\\"\n])*         |
\'({ESC}|[^\\'\n])*         { return lex_error("string não terminada"); }

"..."                       TOKEN(T_DOTS);
".."                        TOKEN(T_CONCAT);
"=="                        TOKEN(T_EQ);
"~="                        TOKEN(T_NE);
"<="                        TOKEN(T_LE);
">="                        TOKEN(T_GE);
"//"                        TOKEN(T_IDIV);
[-+*/%^#<>=(){}\[\];:,.]    TOKEN(yytext[0]);

.                           { return lex_error(std::string("caractere inválido '") + yytext + "'"); }

<<EOF>>                     { AT_EOF(); yyterminate(); }

%%

void lexer_reset(FILE* in)
{
    cur_line = 1;
    cur_col = 1;
    BEGIN(INITIAL);
    yyrestart(in);
}
