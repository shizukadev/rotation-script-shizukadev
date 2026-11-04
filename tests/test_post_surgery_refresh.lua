local f=assert(io.open('engine.lua'));local s=f:read('*a'):gsub('\r','');f:close()
local a=assert(s:find('        -- /status is asynchronous:',1,true));local z=assert(s:find('        if sick == true and id == 2 then',a,true))
local src=s:sub(a,z-1)..'\nreturn sick,id'
for _,valid in ipairs({true,false})do
 local calls,reads=0,0
 local state={known=false,checking=false,active=true}
 local env=setmetatable({bot={status=1,rotation={}},BotStatus={online=1},recoveryStatus=state,lockoutTriggered=false,sleep=function()end,print=function()end,setRotationEnabled=function(on)assert(not on)end,checkRecoveryStatus=function()calls=calls+1;state.checking=false;state.known=valid end,mod={hasAnyMalady=function()assert(calls>0 and state.known);reads=reads+1;return true,1 end}},{__index=_G})
 local sick,id=assert(load(src,'@production-refresh','t',env))()
 if valid then assert(sick==true and id==1 and reads==1)else assert(sick==false and reads==0 and env.hospitalPending)end
end
print('PASS post-surgery: status refresh precedes malady API; invalid refresh keeps pause without reading stale disease')
