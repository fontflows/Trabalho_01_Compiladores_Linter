local VERSAO = "1.0"
local nao_usada = 10

local function auxiliar_esquecida()
  return VERSAO
end

function muitos_parametros(a, b, c, d, e, f)
  return a + b + c + d + e
end

function classifica(x, y, _ignorado)
  total = 0
  local resultado = nil
  if x > 0 and y > 0 then
    resultado = "q1"
  elseif x < 0 and y > 0 then
    resultado = "q2"
  elseif x < 0 and y < 0 then
    resultado = "q3"
  elseif x > 0 and y < 0 then
    resultado = "q4"
  elseif x == 0 or y == 0 then
    resultado = "eixo"
  end
  for _, v in ipairs({x, y}) do
    while v > 0 do
      if v % 2 == 0 then
        repeat
          v = v - 1
        until v < 10
      end
      v = v - 1
    end
  end
  return resultado
end
