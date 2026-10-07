--[[ Comentário de bloco
     com várias linhas; nada aqui conta como código
     local x = 99 ]]
--[==[
  nível 2: o ]] abaixo não fecha o comentário
  ]]
]==]
---[[ três hífens: isto é só um comentário de linha
function soma(a, b) --[[ comentário no meio ]] return a + b end

--[[ fechado ]] local fator = 7
-- linha comum com ; e -- dentro
function dobro(x)
  return x * 2 -- o 2 aqui é magic number
end
