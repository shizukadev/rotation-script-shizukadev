local f=assert(io.open('engine.lua'));local s=f:read('*a'):gsub('\r','');f:close()
local a=assert(s:find('local function checkAndDispatchHospital()',1,true));local z=assert(s:find('\nlocal farmLabel',a,true));local src=s:sub(a,z-1)..'\nreturn checkAndDispatchHospital'
local function run(id,manual)
 local enabled=true;local calls=0
 local mod={hasAnyMalady=function()return true,id end,checkNeedsHospital=function()return true,id end,runCure=function()error('hospital forbidden during Recovering')end}
 local env=setmetatable({bot={status=1,rotation={}},BotStatus={online=1},getHospitalModule=function()return mod end,recoveryStatus={active=true,known=true,checking=false},checkRecoveryStatus=function()return false end,hospitalPending=true,farmRunIntent=true,intentionalStop=manual,setRotationEnabled=function(v)enabled=v end,waitGemCutsWorld=function()end,gemWaitActive=false,gemWaitNextWarp=0,resumeFarming=function()if not manual then calls=calls+1;enabled=true end end},{__index=_G})
 assert(load(src,'@production-policy','t',env))()()
 return calls,enabled,env.hospitalPending
end
local c,on,p=run(2,false);assert(c==0 and on==false and p==true)
c,on,p=run(1,false);assert(c==1 and on==true and p==false)
c=run(1,true);assert(c==0)
print('PASS production dispatcher: Gem Cuts stays paused, Torn + Recovering resumes, manual stop respected, no hospital while Recovering')
