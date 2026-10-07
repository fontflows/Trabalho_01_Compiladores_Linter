/*
 * Linter e extrator de métricas para miniLua - Trabalho 1
 * Integrantes:
 *   Francisco Eduardo Fontenele Ramos Neto (15452569)
 *   Guilherme Borges de Pádua Barbosa (15653045)
 *   Vinicius Botte (15522900)
 *
 * Interface entre o lexer/parser e o estado da análise. As ações do Bison
 * chamam estas funções; nada aqui conhece a gramática.
 */
#ifndef MINILUA_ANALYZER_HPP
#define MINILUA_ANALYZER_HPP

#include <ostream>
#include <string>

namespace lint {

/* Valor semântico de uma expressão. Precisa ser POD porque vive dentro da
 * %union do parser C gerado pelo Bison. */
struct ExpVal {
    int lit; /* literal numérico, se a expressão é só um número (ou -número); senão -1 */
    int fn;  /* função anônima, se a expressão é uma definição de função; senão -1 */
};

enum class SymKind { Local, Param, LoopVar, LocalFunction, Implicit };

void reset(const std::string& file_name, bool extra);

/* Lexer */
void on_text(const char* text, int len);
void mark_code(int first_line, int last_line);
void end_of_input(int line);
int intern(const char* text);
int number_literal(const char* text, int line, int col);

/* Erros (léxicos e sintáticos). Só o primeiro é mostrado. */
void error(int line, int col, const std::string& message);
bool had_error();

/* Listas auxiliares usadas como valores semânticos */
int name_at(int str, int line, int col);
int list_new(int item);
int list_add(int list, int item);
int explist_new(ExpVal e);
int explist_add(int list, ExpVal e);
int join(int left, const char* sep, int right);

/* Expressões */
ExpVal exp_none();
ExpVal exp_number(int lit);
ExpVal exp_negate(ExpVal e);
ExpVal exp_function();
void exempt(ExpVal e);
void equality_operand(ExpVal e);
void table_field(int key_name, ExpVal value);

/* Variáveis, prefixos e chamadas */
int ref_name(int str, int line, int col);
int ref_index(int prefix);
int ref_field(int prefix, int str);
int ref_paren();
int call(int prefix, int method, int line, int col);
bool is_call(int ref);

/* Comandos */
void statement(int prev_last_line, int first_line);
void assignment(int varlist, int explist);
void local_declaration(int namelist, int explist);
void declare_local_function(int str, int line, int col);
void declare_next(int name, SymKind kind);
void declare_next_list(int namelist, SymKind kind);

/* Escopos léxicos (blocos) */
void open_scope();
void close_scope();

/* Funções e estruturas de controle */
void begin_function(int name, int line);
void add_param(int str, int line, int col);
void add_vararg();
void end_function(int last_line);
void push_control(const char* kind, int line);
void pop_control();
void open_block(const char* kind, int line);
void close_block();
std::string unclosed_block();
void decision(const char* kind);

void print_report(std::ostream& out);

} // namespace lint

#endif
