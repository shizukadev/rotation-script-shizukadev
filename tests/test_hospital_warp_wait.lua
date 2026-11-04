local f=assert(io.open('auto_malady_4aid.lua'));local src=f:read('*a');f:close()
local a=assert(src:find('local function waitOnline',1,true));local z=assert(src:find('local function walkTo',a,true))
local function test(arrive,drop)
 local tick=0;local b={status=1,world='HOME'}
 function b:isInWorld(w) return self.world~='' and (w==nil or self.world==w) end
 function b:warp() self.status=0;self.world='' end
 local env={BotStatus={online=1},print=function() end,sleep=function() tick=tick+1;if tick>=arrive then b.status=1;b.world='4AID' end;if drop and tick==arrive+1 then b.status=0;b.world='' end end}
 setmetatable(env,{__index=_G})
 local warp=assert(load(src:sub(a,z-1)..'\nreturn warpTo','@production-warp','t',env))()
 return warp(b,'4AID'),tick
end
local ok,t=test(4);assert(ok and t==5,'must wait through transition and stabilize')
local ok2,t2=test(100);assert(not ok2 and t2==30,'must time out')
local ok3,t3=test(4,true);assert(ok3 and t3==7,'destination loss must reset stability')
print('PASS production warp: delayed arrival, timeout, destination loss resets stability')
