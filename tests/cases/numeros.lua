function numeros(x)
  local a = x * 0xFF
  local b = x + 1e3
  local c = x - 2.5E-2
  local d = x / 0x1p4
  local e = x % .5
  local f = x + 0x0
  local g = x * 1.0
  local h = x ^ 3.
  return a + b + c + d + e + f + g + h
end

local LIMITE = 100
local NEGATIVO = -42
local TABELA = { 10, 20, chave = 30, [40] = 50 }
