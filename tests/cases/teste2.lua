function processa_pagamento(valor, tipo_cliente)
  local desconto = 0; local taxa = 0

  if tipo_cliente == 1 then
    desconto = valor * 0.15
  elseif tipo_cliente == 2 then
    desconto = valor * 0.05
  end

  for i = 1, 3 do
    registra_log("Processando parcela")
  end

  return (valor - desconto) + taxa
end
