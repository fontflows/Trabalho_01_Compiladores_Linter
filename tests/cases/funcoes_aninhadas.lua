local function auxiliar(n)
  if n <= 1 then
    return 1
  end
  return n * auxiliar(n - 1)
end

function Conta.deposita(self, valor)
  self.saldo = self.saldo + valor
  notifica(self)
end

function Conta:saca(valor)
  if valor > self.saldo then
    erro("saldo insuficiente")
  end
  self.saldo = self.saldo - valor
  self:saca(0)
end

function externa(lista)
  local function interna(x)
    return transforma(x)
  end
  local soma = 0
  for _, v in ipairs(lista) do
    soma = soma + interna(v)
  end
  ordena(lista, function(a, b) return compara(a, b) end)
  local quadrado = function(v) return v * v end
  return soma, quadrado
end
