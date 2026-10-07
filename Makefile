# Linter e extrator de métricas para miniLua - Trabalho 1
# Integrantes:
#   Francisco Eduardo Fontenele Ramos Neto (15452569)
#   Guilherme Borges de Pádua Barbosa (15653045)
#   Vinicius Botte (15522900)
#
# Alvos: all (padrão), test, conflicts, zip, clean.

# O make do MSYS2 não repassa a variável OS, por isso o uname também é olhado.
UNAME := $(shell uname -s 2>/dev/null)
ifneq ($(OS)$(findstring MINGW,$(UNAME))$(findstring MSYS,$(UNAME))$(findstring CYGWIN,$(UNAME)),)
  WINDOWS := 1
endif

# No macOS o bison do sistema é o 2.3, velho demais; se o do Homebrew estiver
# instalado, ele é usado automaticamente.
ifeq ($(origin BISON),undefined)
  BISON := bison
  ifeq ($(UNAME),Darwin)
    BREW_BISON := $(firstword $(wildcard /opt/homebrew/opt/bison/bin/bison /usr/local/opt/bison/bin/bison))
    ifneq ($(BREW_BISON),)
      BISON := $(BREW_BISON)
    endif
  endif
endif
FLEX     ?= flex
CXX      ?= g++
CXXFLAGS ?= -std=c++11 -O2 -Wall -Wextra

ifdef WINDOWS
  EXE := .exe
  # Sem -static o .exe depende das DLLs do MSYS2 e falha fora do terminal dele.
  LDFLAGS += -static
endif

TARGET := linter$(EXE)
B      := build
OBJS   := $(B)/parser.tab.o $(B)/lexer.yy.o $(B)/analyzer.o $(B)/main.o
INC    := -Isrc -I$(B)

DIST      := trabalho1-linter-minilua
DIST_SRC  := README.md Makefile relatorio.pdf .gitattributes \
             src/analyzer.hpp src/analyzer.cpp src/main.cpp src/lexer.l src/parser.y \
             tests/run_tests.sh
DIST_TEST := $(wildcard tests/cases/*.lua tests/cases/*.out)

.PHONY: all test conflicts zip clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJS) $(LDFLAGS)

$(B):
	mkdir -p $(B)

# Sem esta checagem, o bison 2.3 do macOS falha com um erro de sintaxe obscuro.
$(B)/parser.tab.cpp: src/parser.y | $(B)
	@v=`$(BISON) --version | sed -n '1s/.* \([0-9][0-9]*\)\.[0-9].*/\1/p'`; \
	if [ -z "$$v" ] || [ "$$v" -lt 3 ]; then \
	  echo "Erro: é preciso o Bison 3.0 ou mais novo; encontrado: `$(BISON) --version | head -1`"; \
	  echo "No macOS: brew install bison (o Makefile acha o do Homebrew sozinho)"; \
	  exit 1; \
	fi
	$(BISON) -Wall -d -o $@ $<

$(B)/parser.tab.hpp: $(B)/parser.tab.cpp

$(B)/lexer.yy.cpp: src/lexer.l $(B)/parser.tab.hpp | $(B)
	$(FLEX) -o $@ $<

$(B)/parser.tab.o: $(B)/parser.tab.cpp src/analyzer.hpp
	$(CXX) $(CXXFLAGS) $(INC) -c -o $@ $<

$(B)/lexer.yy.o: $(B)/lexer.yy.cpp src/analyzer.hpp
	$(CXX) $(CXXFLAGS) $(INC) -c -o $@ $<

$(B)/analyzer.o: src/analyzer.cpp src/analyzer.hpp | $(B)
	$(CXX) $(CXXFLAGS) $(INC) -c -o $@ $<

$(B)/main.o: src/main.cpp src/analyzer.hpp $(B)/parser.tab.hpp
	$(CXX) $(CXXFLAGS) $(INC) -c -o $@ $<

test: $(TARGET)
	sh tests/run_tests.sh ./$(TARGET)

# Mostra contraexemplos caso a gramática passe a ter conflitos (Bison 3.7+).
conflicts: | $(B)
	$(BISON) -Wall -Wcounterexamples -d -o $(B)/conflicts.tab.cpp src/parser.y

zip:
	rm -rf $(B)/dist $(DIST).zip
	mkdir -p $(B)/dist/$(DIST)
	for f in $(DIST_SRC) $(DIST_TEST); do \
	  mkdir -p $(B)/dist/$(DIST)/`dirname $$f` && cp $$f $(B)/dist/$(DIST)/$$f || exit 1; \
	done
	cd $(B)/dist && if command -v zip >/dev/null 2>&1; then \
	  zip -qr ../../$(DIST).zip $(DIST); \
	else \
	  python3 -m zipfile -c ../../$(DIST).zip $(DIST); \
	fi
	@echo "Gerado $(DIST).zip"

clean:
	rm -rf $(B) linter linter.exe $(DIST).zip
