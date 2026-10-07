-- Função 1: Validação complexa de regras de negócio
function valida_usuario(idade, status, pontuacao)
  if idade < 18 or status == "bloqueado" then
    return false
  end

  if pontuacao > 1000 and status == "vip" then
    registra_evento("Usuario VIP validado")
    return true
  elseif pontuacao > 500 then
    registra_evento("Usuario padrao validado")
    return true
  else
    return false
  end
end

-- Função 2: Processamento de Matriz com alto aninhamento
function processa_matriz(linhas, colunas)
  local matriz = cria_matriz_vazia()

  for i = 1, linhas do
    for j = 1, colunas do
      if i == j then
        matriz[i][j] = 1
      else
        matriz[i][j] = 0; log_operacao("zerando indice")
      end
    end
  end

  return matriz
end

-- Função 3: Busca iterativa e alerta
function busca_limite(valores, limite_maximo)
  local i = 1
  while valores[i] ~= nil do
    if valores[i] > limite_maximo then
      alerta_limite(valores[i], 999)
      break
    end
    i = i + 1
  end
end