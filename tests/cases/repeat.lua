function espera(fila)
  local tentativas = 0
  repeat
    tentativas = tentativas + 1
    if fila:vazia() then
      while not fila:pronta() do
        aguarda()
      end
    end
  until tentativas >= 3 or fila:pronta()
  return tentativas
end
