local f=assert(io.open('engine.lua'));local s=f:read('*a');f:close()
local block=assert(s:match('(local recoveryStatus = .-)\nlocal lastSpamCheck'))
local function scenario(messages,offline,fail)
 local now=100;local handlers={};local says=0;local logs={}
 local bot={status=offline and 0 or 1,name='TESTBOT'}
 function bot:isInWorld()return true end
 function bot:say(v)assert(v=='/status');says=says+1 end
 local env=setmetatable({bot=bot,BotStatus={online=1},Event={game_message=1,variantlist=2},os={time=function()return now end},print=function(v)logs[#logs+1]=v end,addEvent=function(e,fn)handlers[e]=fn end,listenEvents=function(seconds)
  assert(seconds==1);now=now+1
  if fail then error('event failure')end
  if messages then for _,m in ipairs(messages)do handlers[1](m)end;messages=nil end
 end},{__index=_G})
 local check=assert(load(block..'\nreturn checkRecoveryStatus','@production-guard','t',env))()
 local clear=false
 for i=1,9 do clear=check()end
 return clear,says,env,check,bot
end
assert(not scenario({'msg|Status:', 'msg|Recovering (1 hour 50 mins left)'}))
assert(not scenario({'msg|Status:'}))
assert(not scenario(nil))
assert(not scenario({'msg|mods active: 1'}))
assert(not scenario({'msg|mods active: 0', 'msg|Recovering (2 minutes left)'}))
assert(not scenario({'msg|mods active: 0'},false,true))
local clear,says= scenario(nil,true);assert(not clear and says==0)
local valid,_,_,check,bot=scenario({"msg|TESTBOT's Status:",'msg|mods active: 0'})
assert(valid);bot.status=0;assert(not check());bot.status=1;assert(not check())
print('PASS production Recovering guard: active, incomplete, timeout, event error, offline, explicit zero mods, reconnect')
