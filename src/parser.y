/*
 * Linter e extrator de métricas para miniLua - Trabalho 1
 * Integrantes:
 *   Francisco Eduardo Fontenele Ramos Neto (15452569)
 *   Guilherme Borges de Pádua Barbosa (15653045)
 *   Vinicius Botte (15522900)
 *
 * Gramática do miniLua. Não há AST: as ações semânticas atualizam direto o
 * estado da análise (analyzer.cpp). O escopo de cada função é aberto por uma
 * ação no meio da regra, antes do corpo, e fechado quando o "end" é reduzido;
 * as estruturas de controle fazem o mesmo com a pilha de aninhamento.
 */

%code requires {
#include "analyzer.hpp"
}

%code provides {
int yylex(void);
void yyerror(const char* msg);
}

%{
#include <string>
#include <vector>
%}

%locations
%define parse.error verbose
%define parse.lac full
%expect 0

%union {
    int num;
    int str;
    int ref;
    int list;
    lint::ExpVal exp;
}

%token T_AND T_BREAK T_DO T_ELSE T_ELSEIF T_END T_FALSE T_FOR T_FUNCTION T_IF
%token T_IN T_LOCAL T_NIL T_NOT T_OR T_REPEAT T_RETURN T_THEN T_TRUE T_UNTIL
%token T_WHILE
%token T_CONCAT T_DOTS T_EQ T_NE T_LE T_GE T_IDIV
%token <str> T_NAME
%token <num> T_NUMBER
%token T_STRING T_LEXERROR

%type <num> stats
%type <str> funcname dotted
%type <ref> var prefixexp functioncall
%type <list> varlist namelist explist
%type <exp> exp

/* Lua tem uma ambiguidade conhecida: em "a = f\n(g)()" o "(" pode ser o
 * argumento de uma chamada a f ou o início de um novo comando. Como o Lua 5.2+,
 * o parser sempre continua a chamada; PREFIXEXP dá às reduções de prefixexp
 * precedência menor que "(" para que o Bison escolha o shift sem conflito. */
%precedence PREFIXEXP
%precedence '('

%left T_OR
%left T_AND
%left '<' '>' T_LE T_GE T_NE T_EQ
%right T_CONCAT
%left '+' '-'
%left '*' '/' T_IDIV '%'
%precedence T_NOT '#' UNARY
%right '^'

%%

chunk
    : block
    ;

block
    : open_scope body                           { lint::close_scope(); }
    ;

open_scope
    : %empty                                    { lint::open_scope(); }
    ;

body
    : stats
    | stats retstat                             { lint::statement($1, @2.first_line); }
    ;

/* O valor é a última linha do comando anterior do mesmo bloco (0 se não há),
 * usado para detectar dois comandos na mesma linha física. */
stats
    : %empty                                    { $$ = 0; }
    | stats stat                                { lint::statement($1, @2.first_line); $$ = @2.last_line; }
    | stats ';'                                 { $$ = $1; }
    ;

retstat
    : T_RETURN
    | T_RETURN ';'
    | T_RETURN explist
    | T_RETURN explist ';'
    ;

stat
    : varlist '=' explist                       { lint::assignment($1, $3); }
    | prefixexp %prec PREFIXEXP
        {
            if (!lint::is_call($1)) {
                lint::error(@1.first_line, @1.first_column,
                            "erro de sintaxe: comando incompleto, esperada atribuição ou chamada de função");
                YYERROR;
            }
        }
    | T_DO                                      { lint::open_block("do", @1.first_line); }
      block T_END                               { lint::close_block(); }
    | T_WHILE exp T_DO                          { lint::push_control("while", @1.first_line); }
      block T_END                               { lint::pop_control(); }
    | T_REPEAT                                  { lint::push_control("repeat", @1.first_line); lint::open_scope(); }
      body T_UNTIL exp                          { lint::close_scope(); lint::pop_control(); }
    | T_IF exp T_THEN                           { lint::push_control("if", @1.first_line); }
      block elseifs else_part T_END             { lint::pop_control(); }
    | T_FOR T_NAME '=' exp ',' exp T_DO
        {
            lint::push_control("for", @1.first_line);
            lint::declare_next(lint::name_at($2, @2.first_line, @2.first_column), lint::SymKind::LoopVar);
        }
      block T_END                               { lint::pop_control(); }
    | T_FOR T_NAME '=' exp ',' exp ',' exp T_DO
        {
            lint::push_control("for", @1.first_line);
            lint::declare_next(lint::name_at($2, @2.first_line, @2.first_column), lint::SymKind::LoopVar);
        }
      block T_END                               { lint::pop_control(); }
    | T_FOR namelist T_IN explist T_DO
        {
            lint::push_control("for", @1.first_line);
            lint::declare_next_list($2, lint::SymKind::LoopVar);
        }
      block T_END                               { lint::pop_control(); }
    | T_FUNCTION funcname                       { lint::begin_function($2, @1.first_line); }
      funcbody
    | T_LOCAL T_FUNCTION T_NAME
        {
            lint::declare_local_function($3, @3.first_line, @3.first_column);
            lint::begin_function($3, @1.first_line);
        }
      funcbody
    | T_LOCAL namelist                          { lint::local_declaration($2, -1); }
    | T_LOCAL namelist '=' explist              { lint::local_declaration($2, $4); }
    | T_BREAK
    ;

elseifs
    : %empty
    | elseifs T_ELSEIF exp T_THEN               { lint::decision("elseif"); }
      block
    ;

else_part
    : %empty
    | T_ELSE block
    ;

funcname
    : dotted                                    { $$ = $1; }
    | dotted ':' T_NAME                         { $$ = lint::join($1, ":", $3); }
    ;

dotted
    : T_NAME                                    { $$ = $1; }
    | dotted '.' T_NAME                         { $$ = lint::join($1, ".", $3); }
    ;

funcbody
    : '(' params ')' block T_END                { lint::end_function(@5.last_line); }
    ;

params
    : %empty
    | parlist
    | parlist ',' T_DOTS                        { lint::add_vararg(); }
    | T_DOTS                                    { lint::add_vararg(); }
    ;

parlist
    : T_NAME                                    { lint::add_param($1, @1.first_line, @1.first_column); }
    | parlist ',' T_NAME                        { lint::add_param($3, @3.first_line, @3.first_column); }
    ;

varlist
    : var                                       { $$ = lint::list_new($1); }
    | varlist ',' var                           { $$ = lint::list_add($1, $3); }
    ;

namelist
    : T_NAME                                    { $$ = lint::list_new(lint::name_at($1, @1.first_line, @1.first_column)); }
    | namelist ',' T_NAME                       { $$ = lint::list_add($1, lint::name_at($3, @3.first_line, @3.first_column)); }
    ;

explist
    : exp                                       { $$ = lint::explist_new($1); }
    | explist ',' exp                           { $$ = lint::explist_add($1, $3); }
    ;

exp
    : T_NIL                                     { $$ = lint::exp_none(); }
    | T_FALSE                                   { $$ = lint::exp_none(); }
    | T_TRUE                                    { $$ = lint::exp_none(); }
    | T_NUMBER                                  { $$ = lint::exp_number($1); }
    | T_STRING                                  { $$ = lint::exp_none(); }
    | T_DOTS                                    { $$ = lint::exp_none(); }
    | T_FUNCTION                                { lint::begin_function(-1, @1.first_line); }
      funcbody                                  { $$ = lint::exp_function(); }
    | prefixexp %prec PREFIXEXP                 { $$ = lint::exp_none(); }
    | tableconstructor                          { $$ = lint::exp_none(); }
    | exp T_OR exp                              { lint::decision("or"); $$ = lint::exp_none(); }
    | exp T_AND exp                             { lint::decision("and"); $$ = lint::exp_none(); }
    | exp '<' exp                               { $$ = lint::exp_none(); }
    | exp '>' exp                               { $$ = lint::exp_none(); }
    | exp T_LE exp                              { $$ = lint::exp_none(); }
    | exp T_GE exp                              { $$ = lint::exp_none(); }
    | exp T_NE exp                              { lint::equality_operand($1); lint::equality_operand($3); $$ = lint::exp_none(); }
    | exp T_EQ exp                              { lint::equality_operand($1); lint::equality_operand($3); $$ = lint::exp_none(); }
    | exp T_CONCAT exp                          { $$ = lint::exp_none(); }
    | exp '+' exp                               { $$ = lint::exp_none(); }
    | exp '-' exp                               { $$ = lint::exp_none(); }
    | exp '*' exp                               { $$ = lint::exp_none(); }
    | exp '/' exp                               { $$ = lint::exp_none(); }
    | exp T_IDIV exp                            { $$ = lint::exp_none(); }
    | exp '%' exp                               { $$ = lint::exp_none(); }
    | exp '^' exp                               { $$ = lint::exp_none(); }
    | T_NOT exp                                 { $$ = lint::exp_none(); }
    | '#' exp                                   { $$ = lint::exp_none(); }
    | '-' exp %prec UNARY                       { $$ = lint::exp_negate($2); }
    ;

prefixexp
    : var                                       { $$ = $1; }
    | functioncall                              { $$ = $1; }
    | '(' exp ')'                               { $$ = lint::ref_paren(); }
    ;

var
    : T_NAME                                    { $$ = lint::ref_name($1, @1.first_line, @1.first_column); }
    | prefixexp '[' exp ']'                     { $$ = lint::ref_index($1); }
    | prefixexp '.' T_NAME                      { $$ = lint::ref_field($1, $3); }
    ;

functioncall
    : prefixexp args                            { $$ = lint::call($1, -1, @1.first_line, @1.first_column); }
    | prefixexp ':' T_NAME args                 { $$ = lint::call($1, $3, @1.first_line, @1.first_column); }
    ;

args
    : '(' ')'
    | '(' explist ')'
    | tableconstructor
    | T_STRING
    ;

tableconstructor
    : '{' '}'
    | '{' fieldlist '}'
    | '{' fieldlist fieldsep '}'
    ;

fieldlist
    : field
    | fieldlist fieldsep field
    ;

field
    : '[' exp ']' '=' exp                       { lint::exempt($2); lint::table_field(-1, $5); }
    | T_NAME '=' exp                            { lint::table_field($1, $3); }
    | exp                                       { lint::table_field(-1, $1); }
    ;

fieldsep
    : ','
    | ';'
    ;

%%

/* Traduz a mensagem do modo "verbose" do Bison, que tem sempre a forma
 * "syntax error, unexpected X, expecting A or B or C", trocando os nomes
 * internos dos tokens pelo texto que aparece no código. */
static std::string token_text(const std::string& name)
{
    static const char* const table[][2] = {
        { "T_AND", "'and'" },       { "T_BREAK", "'break'" },   { "T_DO", "'do'" },
        { "T_ELSE", "'else'" },     { "T_ELSEIF", "'elseif'" }, { "T_END", "'end'" },
        { "T_FALSE", "'false'" },   { "T_FOR", "'for'" },       { "T_FUNCTION", "'function'" },
        { "T_IF", "'if'" },         { "T_IN", "'in'" },         { "T_LOCAL", "'local'" },
        { "T_NIL", "'nil'" },       { "T_NOT", "'not'" },       { "T_OR", "'or'" },
        { "T_REPEAT", "'repeat'" }, { "T_RETURN", "'return'" }, { "T_THEN", "'then'" },
        { "T_TRUE", "'true'" },     { "T_UNTIL", "'until'" },   { "T_WHILE", "'while'" },
        { "T_CONCAT", "'..'" },     { "T_DOTS", "'...'" },      { "T_EQ", "'=='" },
        { "T_NE", "'~='" },         { "T_LE", "'<='" },         { "T_GE", "'>='" },
        { "T_IDIV", "'//'" },       { "T_NAME", "identificador" },
        { "T_NUMBER", "número" },   { "T_STRING", "string" },
        { "$end", "fim do arquivo" }, { "end of file", "fim do arquivo" },
    };
    for (size_t i = 0; i < sizeof table / sizeof table[0]; ++i)
        if (name == table[i][0])
            return table[i][1];
    return name;
}

static std::vector<std::string> split(const std::string& s, const std::string& sep)
{
    std::vector<std::string> parts;
    std::string::size_type start = 0, pos;
    while ((pos = s.find(sep, start)) != std::string::npos) {
        parts.push_back(s.substr(start, pos - start));
        start = pos + sep.size();
    }
    parts.push_back(s.substr(start));
    return parts;
}

void yyerror(const char* msg)
{
    /* Depois de um erro léxico o parser recebe T_LEXERROR e também reclama;
     * a mensagem do lexer é a que interessa. */
    if (lint::had_error())
        return;

    const std::string prefix = "syntax error, unexpected ";
    std::string m = msg;
    if (m.compare(0, prefix.size(), prefix) != 0) {
        lint::error(yylloc.first_line, yylloc.first_column, m == "syntax error" ? "erro de sintaxe" : "erro: " + m);
        return;
    }
    std::vector<std::string> parts = split(m.substr(prefix.size()), ", expecting ");
    std::string unexpected = token_text(parts[0]);
    std::string open = lint::unclosed_block();
    if (unexpected == "fim do arquivo" && !open.empty()) {
        lint::error(yylloc.first_line, yylloc.first_column, "erro de sintaxe: fim do arquivo inesperado; " + open);
        return;
    }
    std::string out = "erro de sintaxe: encontrado " + unexpected;
    if (parts.size() > 1) {
        std::vector<std::string> expected = split(parts[1], " or ");
        out += ", esperado ";
        for (size_t i = 0; i < expected.size(); ++i) {
            if (i > 0)
                out += (i + 1 == expected.size()) ? " ou " : ", ";
            out += token_text(expected[i]);
        }
    }
    lint::error(yylloc.first_line, yylloc.first_column, out);
}
