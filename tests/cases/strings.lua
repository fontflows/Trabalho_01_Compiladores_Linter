function mensagens(nome)
  local a = "texto com -- que não é comentário"
  local b = 'aspas simples; com ponto e vírgula'
  local c = "escapes: \n \t \\ \" \' \65 \x41 \u{48} \z
             continua"
  local d = [[string longa
com 42 e -- dentro
e mais uma linha]]
  local e = [==[com ]] no meio]==]
  local f = "quebra com barra \
continua aqui"
  imprime(a .. b .. c .. d .. e .. f .. nome)
end
