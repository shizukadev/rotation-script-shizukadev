local f=assert(io.open('engine.lua'));local s=f:read('*a'):gsub('\r','');f:close()
local a=assert(s:find('local gemWaitActive =',1,true));local z=assert(s:find('-- Melanjutkan farming',a,true))
local helper=s:sub(a,z-1)
local b={status=1,rotation={},world='4AID'};local warps=0;local enabled=true;local now=100
function b:isInWorld(w)return self.world==w end
function b:warp(w)assert(w=='luacid');warps=warps+1 end
local env=setmetatable({bot=b,BotStatus={online=1},lockoutTriggered=false,os={time=function()return now end},print=function()end,setRotationEnabled=function(v)enabled=v end},{__index=_G})
local wait=assert(load(helper..'\nreturn waitGemCutsWorld','@production-wait','t',env))()
wait();assert(warps==1 and enabled==false)
now=110;wait();assert(warps==1)
now=131;wait();assert(warps==2)
b.world='luacid';now=170;wait();assert(warps==2)
b.status=0;b.world='4AID';now=210;wait();assert(warps==2)
b.status=1;env.lockoutTriggered=true;wait();assert(warps==2)
assert(s:find('if sick == true and id == 2 then\n            gemWaitActive = true',1,true))
assert(s:find('if gemWaitActive then\n        if anySick == false then',1,true))
print('PASS luacid wait: rotation OFF, exact destination, bounded retries, no warp offline/lockout; valid-clearance state branch present')
