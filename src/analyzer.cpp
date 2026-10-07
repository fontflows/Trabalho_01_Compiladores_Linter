/*
 * Linter e extrator de métricas para miniLua - Trabalho 1
 * Integrantes:
 *   Francisco Eduardo Fontenele Ramos Neto (15452569)
 *   Guilherme Borges de Pádua Barbosa (15653045)
 *   Vinicius Botte (15522900)
 *
 * Estado da análise: métricas por função, tabela de símbolos por bloco,
 * alertas e geração do relatório.
 */
#include "analyzer.hpp"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <utility>
#include <vector>

namespace lint {
namespace {

/* Limites dos alertas extras (--extra). */
const int MAX_PARAMS = 5;
const int MAX_DEPTH = 4;
const int MAX_COMPLEXITY = 10;
const int MAX_LOGICAL_LINES = 50;

struct Symbol {
    std::string name;
    int line;
    int col;
    int reads;
    SymKind kind;
};

/* Uma variável ou prefixo de chamada (x, t.campo, t[i], f(...)). Só os nomes
 * simples (bare) podem ser alvo de atribuição a variável. */
struct Ref {
    std::string name;
    int sym;
    bool bare;
    bool call;
    int line;
    int col;
};

struct NumberLiteral {
    std::string text;
    int line;
    int col;
    bool exempt;
    bool equality;
};

struct NameAt {
    int str;
    int line;
    int col;
};

struct Call {
    std::string name;
    int line;
    int col;
};

struct Function {
    std::string name;
    bool anonymous;
    bool named_later;
    int first_line;
    int last_line;
    std::vector<std::string> params;
    std::vector<Call> calls;
    std::vector<std::string> path;
    std::vector<std::string> deepest;
    /* estruturas de controle na ordem em que aparecem pela primeira vez */
    std::vector<std::pair<std::string, int> > structures;
    int ands;
    int ors;

    Function() : anonymous(false), named_later(false), first_line(0), last_line(0), ands(0), ors(0) {}
};

struct Warning {
    int line;
    int order;
    int col;
    std::string text;
};

struct State {
    std::string file;
    bool extra;
    bool error;

    int newlines;
    bool any_text;
    char last_char;
    int eof_line;
    std::set<int> code_lines;

    std::vector<std::string> strings;
    std::map<std::string, int> string_ids;
    std::vector<NameAt> names;
    std::vector<std::vector<int> > lists;
    std::vector<std::vector<ExpVal> > explists;
    std::vector<Ref> refs;
    std::vector<NumberLiteral> numbers;

    Function global;
    std::vector<Function> functions;
    std::vector<int> stack;
    int last_closed;

    std::vector<Symbol> symbols;
    std::vector<std::vector<int> > scopes;
    std::vector<int> pending;

    std::vector<Warning> warnings;
    std::vector<Warning> extra_warnings;
    std::set<int> multi_lines;

    /* blocos abertos (palavra-chave, linha), para a mensagem de "end" faltando */
    std::vector<std::pair<std::string, int> > blocks;

    State() : extra(false), error(false), newlines(0), any_text(false), last_char(0), eof_line(0), last_closed(-1) {}
};

State S;

Function& current()
{
    return S.stack.empty() ? S.global : S.functions[S.stack.back()];
}

const std::string& text_of(int str)
{
    return S.strings[str];
}

void warn(int line, int order, int col, const std::string& text)
{
    Warning w = { line, order, col, text };
    S.warnings.push_back(w);
}

void warn_extra(int line, int col, const std::string& text)
{
    Warning w = { line, 1, col, text };
    S.extra_warnings.push_back(w);
}

int new_symbol(const std::string& name, int line, int col, SymKind kind)
{
    Symbol s = { name, line, col, 0, kind };
    S.symbols.push_back(s);
    return (int)S.symbols.size() - 1;
}

int resolve(const std::string& name)
{
    for (size_t i = S.scopes.size(); i-- > 0;) {
        const std::vector<int>& scope = S.scopes[i];
        for (size_t j = scope.size(); j-- > 0;)
            if (S.symbols[scope[j]].name == name)
                return scope[j];
    }
    return -1;
}

void declare(const std::string& name, int line, int col, SymKind kind)
{
    S.scopes.back().push_back(new_symbol(name, line, col, kind));
}

void name_function(int fn, const std::string& name)
{
    if (fn < 0)
        return;
    Function& f = S.functions[fn];
    if (f.anonymous && !f.named_later) {
        f.name = name;
        f.named_later = true;
    }
}

std::string join_list(const std::vector<std::string>& items)
{
    std::string out;
    for (size_t i = 0; i < items.size(); ++i) {
        if (i)
            out += ", ";
        out += items[i];
    }
    return out;
}

/* Chamada da própria função não é externa. Para métodos, "self:m" dentro de
 * "Classe:m" também é recursão. */
bool is_recursive(const Function& f, const std::string& callee)
{
    if (callee == f.name)
        return true;
    std::string::size_type colon = f.name.find(':');
    return colon != std::string::npos && callee == "self" + f.name.substr(colon);
}

std::vector<std::string> external_calls(const Function& f)
{
    std::vector<Call> calls = f.calls;
    /* As chamadas são registradas quando a regra é reduzida, o que põe f(g())
     * na ordem g, f. Ordenar pela posição devolve a ordem do texto. */
    std::stable_sort(calls.begin(), calls.end(), [](const Call& a, const Call& b) {
        return a.line != b.line ? a.line < b.line : a.col < b.col;
    });
    std::vector<std::string> out;
    for (size_t i = 0; i < calls.size(); ++i)
        if (!is_recursive(f, calls[i].name))
            out.push_back(calls[i].name);
    return out;
}

int decisions(const Function& f)
{
    int n = f.ands + f.ors;
    for (size_t i = 0; i < f.structures.size(); ++i)
        n += f.structures[i].second;
    return n;
}

int logical_lines_between(int first, int last)
{
    int n = 0;
    for (std::set<int>::const_iterator it = S.code_lines.lower_bound(first);
         it != S.code_lines.end() && *it <= last; ++it)
        ++n;
    return n;
}

void print_metrics(std::ostream& out, const Function& f)
{
    std::vector<std::string> calls = external_calls(f);
    out << "Chamadas de Funções Externas: " << calls.size();
    if (!calls.empty())
        out << " (" << join_list(calls) << ")";
    out << "\n";

    int depth = (int)f.deepest.size();
    out << "Profundidade Máxima de Aninhamento: " << depth;
    if (depth >= 3) {
        out << " (";
        for (size_t i = 0; i < f.deepest.size(); ++i)
            out << (i ? " -> " : "") << f.deepest[i];
        out << ")";
    }
    out << "\n";

    int nd = decisions(f);
    out << "Complexidade Ciclomática: " << 1 + nd;
    if (nd > 0) {
        out << " (1 base";
        for (size_t i = 0; i < f.structures.size(); ++i)
            out << " + " << f.structures[i].second << " " << f.structures[i].first;
        if (f.ands)
            out << " + " << f.ands << " and";
        if (f.ors)
            out << " + " << f.ors << " or";
        out << ")";
    }
    out << "\n";
}

void function_extra_warnings(const Function& f)
{
    std::ostringstream msg;
    int params = (int)f.params.size();
    if (params > MAX_PARAMS) {
        msg.str("");
        msg << "Função '" << f.name << "' tem " << params << " parâmetros (limite: " << MAX_PARAMS << ").";
        warn_extra(f.first_line, 0, msg.str());
    }
    int depth = (int)f.deepest.size();
    if (depth > MAX_DEPTH) {
        msg.str("");
        msg << "Função '" << f.name << "' tem profundidade de aninhamento " << depth << " (limite: " << MAX_DEPTH << ").";
        warn_extra(f.first_line, 0, msg.str());
    }
    int complexity = 1 + decisions(f);
    if (complexity > MAX_COMPLEXITY) {
        msg.str("");
        msg << "Função '" << f.name << "' tem complexidade ciclomática " << complexity << " (limite: " << MAX_COMPLEXITY << ").";
        warn_extra(f.first_line, 0, msg.str());
    }
    int lines = logical_lines_between(f.first_line, f.last_line);
    if (lines > MAX_LOGICAL_LINES) {
        msg.str("");
        msg << "Função '" << f.name << "' tem " << lines << " linhas lógicas (limite: " << MAX_LOGICAL_LINES << ").";
        warn_extra(f.first_line, 0, msg.str());
    }
}

bool is_zero_or_one(const std::string& text)
{
    double v = std::strtod(text.c_str(), 0);
    return v == 0.0 || v == 1.0;
}

} // namespace

void reset(const std::string& file_name, bool extra)
{
    S = State();
    S.file = file_name;
    S.extra = extra;
    S.global.name = "(escopo global)";
    S.global.path.push_back("global");
    S.global.deepest = S.global.path;
}

void on_text(const char* text, int len)
{
    for (int i = 0; i < len; ++i)
        if (text[i] == '\n')
            ++S.newlines;
    if (len > 0) {
        S.any_text = true;
        S.last_char = text[len - 1];
    }
}

void mark_code(int first_line, int last_line)
{
    for (int l = first_line; l <= last_line; ++l)
        S.code_lines.insert(l);
}

void end_of_input(int line)
{
    S.eof_line = line;
}

int intern(const char* text)
{
    std::map<std::string, int>::iterator it = S.string_ids.find(text);
    if (it != S.string_ids.end())
        return it->second;
    S.strings.push_back(text);
    int id = (int)S.strings.size() - 1;
    S.string_ids[text] = id;
    return id;
}

int number_literal(const char* text, int line, int col)
{
    NumberLiteral n = { text, line, col, false, false };
    S.numbers.push_back(n);
    return (int)S.numbers.size() - 1;
}

void error(int line, int col, const std::string& message)
{
    if (S.error)
        return;
    S.error = true;
    std::cerr << S.file << ":" << line << ":" << col << ": " << message << "\n";
}

bool had_error()
{
    return S.error;
}

int name_at(int str, int line, int col)
{
    NameAt n = { str, line, col };
    S.names.push_back(n);
    return (int)S.names.size() - 1;
}

int list_new(int item)
{
    S.lists.push_back(std::vector<int>(1, item));
    return (int)S.lists.size() - 1;
}

int list_add(int list, int item)
{
    S.lists[list].push_back(item);
    return list;
}

int explist_new(ExpVal e)
{
    S.explists.push_back(std::vector<ExpVal>(1, e));
    return (int)S.explists.size() - 1;
}

int explist_add(int list, ExpVal e)
{
    S.explists[list].push_back(e);
    return list;
}

int join(int left, const char* sep, int right)
{
    return intern((text_of(left) + sep + text_of(right)).c_str());
}

ExpVal exp_none()
{
    ExpVal e = { -1, -1 };
    return e;
}

ExpVal exp_number(int lit)
{
    ExpVal e = { lit, -1 };
    return e;
}

ExpVal exp_negate(ExpVal e)
{
    ExpVal r = { e.lit, -1 };
    return r;
}

ExpVal exp_function()
{
    ExpVal e = { -1, S.last_closed };
    return e;
}

void exempt(ExpVal e)
{
    if (e.lit >= 0)
        S.numbers[e.lit].exempt = true;
}

void equality_operand(ExpVal e)
{
    if (e.lit >= 0)
        S.numbers[e.lit].equality = true;
}

void table_field(int key_name, ExpVal value)
{
    exempt(value);
    if (key_name >= 0)
        name_function(value.fn, text_of(key_name));
}

int ref_name(int str, int line, int col)
{
    Ref r = { text_of(str), resolve(text_of(str)), true, false, line, col };
    /* Toda referência conta como leitura; se for alvo de atribuição, a regra
     * de atribuição desfaz a contagem. */
    if (r.sym >= 0)
        ++S.symbols[r.sym].reads;
    S.refs.push_back(r);
    return (int)S.refs.size() - 1;
}

int ref_index(int prefix)
{
    Ref p = S.refs[prefix];
    Ref r = { p.name + "[...]", -1, false, false, p.line, p.col };
    S.refs.push_back(r);
    return (int)S.refs.size() - 1;
}

int ref_field(int prefix, int str)
{
    Ref p = S.refs[prefix];
    Ref r = { p.name + "." + text_of(str), -1, false, false, p.line, p.col };
    S.refs.push_back(r);
    return (int)S.refs.size() - 1;
}

int ref_paren()
{
    Ref r = { "(...)", -1, false, false, 0, 0 };
    S.refs.push_back(r);
    return (int)S.refs.size() - 1;
}

int call(int prefix, int method, int line, int col)
{
    std::string name = S.refs[prefix].name;
    if (method >= 0)
        name += ":" + text_of(method);
    Call c = { name, line, col };
    current().calls.push_back(c);
    Ref r = { name + "(...)", -1, false, true, line, col };
    S.refs.push_back(r);
    return (int)S.refs.size() - 1;
}

bool is_call(int ref)
{
    return S.refs[ref].call;
}

void statement(int prev_last_line, int first_line)
{
    if (prev_last_line == first_line && S.multi_lines.insert(first_line).second)
        warn(first_line, 0, 0, "Múltiplos comandos na mesma linha detectados.");
}

void assignment(int varlist, int explist)
{
    const std::vector<int>& vars = S.lists[varlist];
    const std::vector<ExpVal>& exps = S.explists[explist];
    for (size_t i = 0; i < vars.size(); ++i) {
        const Ref& r = S.refs[vars[i]];
        if (r.bare) {
            if (r.sym >= 0)
                --S.symbols[r.sym].reads;
            else if (!S.stack.empty())
                warn_extra(r.line, r.col, "Atribuição à variável global '" + r.name +
                                              "' dentro de função. Declare-a com 'local' se não for intencional.");
        }
        if (i < exps.size())
            name_function(exps[i].fn, r.name);
    }
    for (size_t i = 0; i < exps.size(); ++i)
        exempt(exps[i]);
}

void local_declaration(int namelist, int explist)
{
    const std::vector<int>& names = S.lists[namelist];
    if (explist >= 0) {
        const std::vector<ExpVal>& exps = S.explists[explist];
        for (size_t i = 0; i < exps.size(); ++i) {
            exempt(exps[i]);
            if (i < names.size())
                name_function(exps[i].fn, text_of(S.names[names[i]].str));
        }
    }
    /* Em Lua, "local x = x" lê o x de fora; por isso a declaração vem depois
     * da expressão. */
    for (size_t i = 0; i < names.size(); ++i) {
        const NameAt& n = S.names[names[i]];
        declare(text_of(n.str), n.line, n.col, SymKind::Local);
    }
}

void declare_local_function(int str, int line, int col)
{
    declare(text_of(str), line, col, SymKind::LocalFunction);
}

void declare_next(int name, SymKind kind)
{
    const NameAt& n = S.names[name];
    S.pending.push_back(new_symbol(text_of(n.str), n.line, n.col, kind));
}

void declare_next_list(int namelist, SymKind kind)
{
    const std::vector<int>& names = S.lists[namelist];
    for (size_t i = 0; i < names.size(); ++i)
        declare_next(names[i], kind);
}

void open_scope()
{
    S.scopes.push_back(S.pending);
    S.pending.clear();
}

void close_scope()
{
    const std::vector<int>& scope = S.scopes.back();
    for (size_t i = 0; i < scope.size(); ++i) {
        const Symbol& s = S.symbols[scope[i]];
        if (s.reads > 0 || s.name[0] == '_')
            continue;
        switch (s.kind) {
        case SymKind::Local:
            warn_extra(s.line, s.col, "Variável local '" + s.name + "' declarada e não utilizada.");
            break;
        case SymKind::Param:
            warn_extra(s.line, s.col, "Parâmetro '" + s.name + "' não utilizado.");
            break;
        case SymKind::LoopVar:
            warn_extra(s.line, s.col, "Variável de laço '" + s.name + "' não utilizada (use '_' se for intencional).");
            break;
        case SymKind::LocalFunction:
            warn_extra(s.line, s.col, "Função local '" + s.name + "' definida e não utilizada.");
            break;
        case SymKind::Implicit:
            break;
        }
    }
    S.scopes.pop_back();
}

void begin_function(int name, int line)
{
    Function f;
    f.anonymous = name < 0;
    if (f.anonymous) {
        std::ostringstream label;
        label << "(anônima, linha " << line << ")";
        f.name = label.str();
    } else {
        f.name = text_of(name);
    }
    f.first_line = line;
    f.path.push_back("função");
    f.deepest = f.path;
    S.functions.push_back(f);
    S.stack.push_back((int)S.functions.size() - 1);
    open_block("function", line);
    if (f.name.find(':') != std::string::npos && !f.anonymous)
        S.pending.push_back(new_symbol("self", line, 0, SymKind::Implicit));
}

void add_param(int str, int line, int col)
{
    current().params.push_back(text_of(str));
    S.pending.push_back(new_symbol(text_of(str), line, col, SymKind::Param));
}

void add_vararg()
{
    current().params.push_back("...");
}

void end_function(int last_line)
{
    current().last_line = last_line;
    S.last_closed = S.stack.back();
    S.stack.pop_back();
    close_block();
}

void decision(const char* kind)
{
    Function& f = current();
    std::string k = kind;
    if (k == "and") {
        ++f.ands;
    } else if (k == "or") {
        ++f.ors;
    } else {
        for (size_t i = 0; i < f.structures.size(); ++i) {
            if (f.structures[i].first == k) {
                ++f.structures[i].second;
                return;
            }
        }
        f.structures.push_back(std::make_pair(k, 1));
    }
}

void push_control(const char* kind, int line)
{
    decision(kind);
    Function& f = current();
    f.path.push_back(kind);
    if (f.path.size() > f.deepest.size())
        f.deepest = f.path;
    open_block(kind, line);
}

void pop_control()
{
    current().path.pop_back();
    close_block();
}

void open_block(const char* kind, int line)
{
    S.blocks.push_back(std::make_pair(std::string(kind), line));
}

void close_block()
{
    S.blocks.pop_back();
}

std::string unclosed_block()
{
    if (S.blocks.empty())
        return "";
    const std::pair<std::string, int>& b = S.blocks.back();
    std::ostringstream msg;
    if (b.first == "function")
        msg << "a função da linha " << b.second << " não foi fechada com 'end'";
    else if (b.first == "repeat")
        msg << "o 'repeat' da linha " << b.second << " não foi fechado com 'until'";
    else
        msg << "o '" << b.first << "' da linha " << b.second << " não foi fechado com 'end'";
    return msg.str();
}

void print_report(std::ostream& out)
{
    out << "=== RELATÓRIO DE ANÁLISE ===\n";
    out << "Arquivo: " << S.file << "\n";
    out << "Linhas Físicas: " << S.newlines << "\n";
    out << "Linhas Lógicas: " << S.code_lines.size() << "\n";
    out << "Funções Definidas: " << S.functions.size() << "\n";

    for (size_t i = 0; i < S.functions.size(); ++i) {
        const Function& f = S.functions[i];
        out << "\n--- Função: " << f.name << " ---\n";
        out << "Parâmetros: " << f.params.size();
        if (!f.params.empty())
            out << " (" << join_list(f.params) << ")";
        out << "\n";
        print_metrics(out, f);
    }

    /* O trecho fora de funções só aparece quando tem algo a medir, para não
     * poluir arquivos que só definem funções. */
    if (!S.global.calls.empty() || decisions(S.global) > 0) {
        out << "\n--- Escopo Global (fora de funções) ---\n";
        print_metrics(out, S.global);
    }

    std::vector<Warning> all = S.warnings;
    for (size_t i = 0; i < S.numbers.size(); ++i) {
        const NumberLiteral& n = S.numbers[i];
        /* O exemplo teste2 do enunciado não aponta o 2 de "tipo_cliente == 2":
         * comparado por igualdade, o literal funciona como rótulo de um caso,
         * como num switch. Só o modo --extra aponta esses também. */
        if (n.exempt || is_zero_or_one(n.text) || (n.equality && !S.extra))
            continue;
        Warning w = { n.line, 1, n.col,
                      "'Magic Number' detectado (" + n.text + "). Considere extrair para uma constante." };
        all.push_back(w);
    }
    if (S.extra) {
        for (size_t i = 0; i < S.functions.size(); ++i)
            function_extra_warnings(S.functions[i]);
        if (S.any_text && S.last_char != '\n')
            warn_extra(S.eof_line, 0, "Arquivo não termina com quebra de linha; a última linha não entra na contagem de linhas físicas.");
        all.insert(all.end(), S.extra_warnings.begin(), S.extra_warnings.end());
    }
    std::stable_sort(all.begin(), all.end(), [](const Warning& a, const Warning& b) {
        if (a.line != b.line)
            return a.line < b.line;
        if (a.order != b.order)
            return a.order < b.order;
        return a.col < b.col;
    });

    out << "\n--- Alertas do Linter ---\n";
    if (all.empty())
        out << "Nenhuma infração de estilo detectada.\n";
    for (size_t i = 0; i < all.size(); ++i)
        out << "[Aviso] Linha " << all[i].line << ": " << all[i].text << "\n";
    out << "============================\n";
}

} // namespace lint
