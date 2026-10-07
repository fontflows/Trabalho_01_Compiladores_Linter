/*
 * Linter e extrator de métricas para miniLua - Trabalho 1
 * Integrantes:
 *   Francisco Eduardo Fontenele Ramos Neto (15452569)
 *   Guilherme Borges de Pádua Barbosa (15653045)
 *   Vinicius Botte (15522900)
 *
 * Ponto de entrada: lê as opções, analisa cada arquivo e imprime o relatório.
 */
#include <cstdio>
#include <cstring>
#include <iostream>
#include <string>
#include <vector>

#include "analyzer.hpp"
#include "parser.tab.hpp"

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#include <windows.h>
#endif

void lexer_reset(FILE* in);
int yylex_destroy(void);

static const char* const USAGE =
    "Uso: linter [--extra] [arquivo.lua ...]\n"
    "\n"
    "Analisa código miniLua e imprime métricas por função e alertas de estilo.\n"
    "Sem arquivos (ou com \"-\"), lê da entrada padrão.\n"
    "\n"
    "Opções:\n"
    "  -e, --extra   ativa alertas adicionais (funções longas, muitos parâmetros,\n"
    "                aninhamento ou complexidade altos, variáveis não usadas,\n"
    "                atribuição a globais dentro de funções)\n"
    "  -h, --help    mostra esta ajuda\n";

static std::string display_name(const std::string& path)
{
    if (path == "-")
        return "(entrada padrão)";
    std::string::size_type slash = path.find_last_of("/\\");
    return slash == std::string::npos ? path : path.substr(slash + 1);
}

static bool analyze(const std::string& path, bool extra)
{
    FILE* in = path == "-" ? stdin : std::fopen(path.c_str(), "rb");
    if (!in) {
        std::cerr << path << ": erro: não foi possível abrir o arquivo\n";
        return false;
    }
    lint::reset(display_name(path), extra);
    lexer_reset(in);
    int status = yyparse();
    if (in != stdin)
        std::fclose(in);
    if (status != 0 || lint::had_error())
        return false;
    lint::print_report(std::cout);
    return true;
}

int main(int argc, char** argv)
{
#ifdef _WIN32
    /* Acentos corretos no console e "\n" sem virar "\r\n", para a saída ser
     * idêntica à do Linux. */
    SetConsoleOutputCP(CP_UTF8);
    _setmode(_fileno(stdout), _O_BINARY);
    _setmode(_fileno(stderr), _O_BINARY);
    _setmode(_fileno(stdin), _O_BINARY);
#endif
    bool extra = false;
    bool options_done = false;
    std::vector<std::string> files;
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (!options_done && (arg == "-e" || arg == "--extra")) {
            extra = true;
        } else if (!options_done && (arg == "-h" || arg == "--help")) {
            std::cout << USAGE;
            return 0;
        } else if (!options_done && arg == "--") {
            options_done = true;
        } else if (!options_done && arg.size() > 1 && arg[0] == '-') {
            std::cerr << "linter: opção desconhecida '" << arg << "'\n\n" << USAGE;
            return 2;
        } else {
            files.push_back(arg);
        }
    }
    if (files.empty())
        files.push_back("-");

    int status = 0;
    for (size_t i = 0; i < files.size(); ++i) {
        if (i > 0)
            std::cout << "\n";
        if (!analyze(files[i], extra))
            status = 1;
        std::cout.flush();
    }
    yylex_destroy();
    return status;
}
