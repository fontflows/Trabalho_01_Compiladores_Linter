function f(a)
  local x = a; local y = a
  local z = a local w = a
  if a then return x end
  if a then x = y; y = x end
  for i = 1, a do imprime(i) end
  return x + y + z + w
end
local p = f(1) f(2)
