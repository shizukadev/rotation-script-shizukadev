local f=assert(io.open('engine.lua'));local s=f:read('*a');f:close()
local block=assert(s:match('(local recoveryStatus = .-)\nlocal lastSpamCheck'))
local now=100;local handler;local requests=0;local queue={}
local b={name='ZUCYNOOFRQ',status=1};function b:isInWorld()return true end;function b:say()requests=requests+1 end
local env=setmetatable({bot=b,BotStatus={online=1},Event={game_message=1},os={time=function()return now end},print=function()end,addEvent=function(_,fn)handler=fn end,listenEvents=function()now=now+1;for _,v in ipairs(queue)do handler('action|log\nmsg|'..v)end;queue={}end},{__index=_G})
local check,parse,state=assert(load(block..'\nreturn checkRecoveryStatus,parseRecoveringSeconds,recoveryStatus','@production','t',env))()
assert(parse('Recovering (1 hour, 21 mins, 15 secs left)')==4875)
assert(parse('Recovering (45 mins left)')==2700)
assert(parse('Recovering (30 secs left)')==30)
assert(parse('Recovering (unknown)')==nil)
queue={"ZUCYNOOFRQ's Status:",'3 mods active:','Enhanced Digging','Recovering (1 hour, 21 mins, 15 secs left)'}
for i=1,9 do assert(not check())end
assert(state.active and state.untilTs==4976 and requests==1)
now=4975;assert(not check());assert(requests==1)
now=4976;assert(not check());assert(requests==2)
for i=1,9 do assert(not check())end -- timeout cannot clear
now=state.nextCheck;queue={"ZUCYNOOFRQ's Status:",'0 mods active:'}
for i=1,9 do check()end
assert(check())
print('PASS production duration parsing, deadline, no early request, expiry recheck, timeout OFF, explicit zero mods')
