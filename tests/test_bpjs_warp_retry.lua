local f=assert(io.open('auto_malady_4aid.lua'));local s=f:read('*a');f:close()
local a=assert(s:find('        while b.status == BotStatus.online',1,true));local z=assert(s:find('        local function door',a,true));local src=s:sub(a,z-1)..'\nreturn true'
for _,disconnect in ipairs({false,true})do
 local t=0;local calls={};local b={status=1,world='FARM'}
 function b:isInWorld(w)return self.world==w end
 function b:warp(w)assert(self.status==1 and w=='BPJS');calls[#calls+1]=t;if not disconnect and #calls==3 then self.world=w end end
 local env=setmetatable({b=b,TARGET_WORLD='BPJS',BotStatus={online=1},sleep=function(ms)t=t+ms;if disconnect then b.status=0 end end,isHealthyState=function(bot,w)return bot.status==1 and bot.world==w end},{__index=_G})
 local result=assert(load(src,'@production-bpjs-retry','t',env))()
 if disconnect then assert(result==false and #calls==1)else assert(result==true and #calls==3 and calls[2]-calls[1]==4000 and calls[3]-calls[2]==4000)end
end
print('PASS BPJS retry every 4000ms until arrival; offline stops retries')
