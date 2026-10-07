local MAX = 10
local contador = 0

for i = 1, MAX do
  if i % 2 == 0 and i > 5 then
    contador = contador + 1
  end
end

imprime(contador)
