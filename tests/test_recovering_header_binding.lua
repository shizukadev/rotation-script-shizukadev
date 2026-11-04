local f=assert(io.open('engine.lua'));local s=f:read('*a'):gsub('\\r','');f:close()
local block=assert(s:match('(local recoveryStatus = .-)\nlocal lastSpamCheck'))
local function scenario(messages)
 local now=100;local handlers={}
 local bot={status=1,name='TESTBOT'}
 function bot:isInWorld()return true end
 function bot:say()end
 local env=setmetatable({bot=bot,BotStatus={online=1},Event={game_message=1,variantlist=2},
  os={time=function()return now end},print=function()end,
  addEvent=function(e,fn)handlers[e]=fn end,
  listenEvents=function()now=now+1;if messages then for _,m in ipairs(messages)do handlers[1](m)end;messages=nil end end},
  {__index=_G})
 local check=assert(load(block..'\nreturn checkRecoveryStatus','@production-guard','t',env))()
 local clear=false
 for i=1,9 do clear=check()end
 return clear
end

-- Regresi 1: jumlah mod tanpa header identitas tidak boleh memberi clearance.
assert(scenario({'msg|0 mods active'})==false,'headerless zero mods tidak boleh clear')

-- Regresi 2: header sendiri -> 0 mods -> header asing tidak boleh clear.
assert(scenario({"msg|TESTBOT's Status:",'msg|0 mods active',"msg|OTHER's Status:"})==false,
 'header asing setelah daftar lengkap harus membatalkan clearance')

-- Kontrol positif: header bot sendiri + daftar lengkap = clear.
assert(scenario({"msg|TESTBOT's Status:",'msg|0 mods active'})==true,'header sendiri + 0 mods harus clear')

-- Kontrol: Recovering pada blok bot sendiri tidak clear.
assert(scenario({"msg|TESTBOT's Status:",'msg|1 mods active:','msg|Recovering (5 mins left)'})==false,
 'Recovering aktif tidak boleh clear')

-- Regresi 3: count baru membatalkan completion lama (0 mods lalu count parsial).
assert(scenario({"msg|TESTBOT's Status:",'msg|0 mods active','msg|2 mods active:','msg|Enhanced Digging'})==false,
 'count baru harus menghitung ulang completion, bukan memakai nilai lama')

print('PASS parser: header wajib, header asing membatalkan completion, Recovering tetap menahan')
