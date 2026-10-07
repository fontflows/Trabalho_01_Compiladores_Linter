local M = {}

M.config = { nome = "app", portas = { 80, 443 }, ["chave"] = true; extra = nil, }

M.formata = function(fmt, ...)
  return string.format(fmt, ...)
end

function M.processa(itens)
  local n = #itens
  local partes = {}
  for i = n, 1, -1 do
    partes[#partes + 1] = M.formata("%d", itens[i]) .. ";"
  end
  local texto = table.concat(partes)
  io.write(texto, "\n");
  print "fim"
  registra { total = n }
  local ok = not (n == 0) and n // 2 >= 1 or false
  do
    local tmp = -n ^ 2
    ok = ok and tmp < 0
  end
  return ok, texto:upper():sub(1, 3)
end

local a, b = 1, 2;;
a, b = b, a
return M
