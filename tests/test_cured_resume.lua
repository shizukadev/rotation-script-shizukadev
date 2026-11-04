local f=assert(io.open('engine.lua'));local s=f:read('*a'):gsub('\r','');f:close()
local a=assert(s:find('local function checkAndDispatchHospital()',1,true));local z=assert(s:find('\nlocal farmLabel',a,true))
local code=s:sub(a,z-1)..'\nreturn checkAndDispatchHospital'
local function test(manual,lockout,healthy)
 local resumed,checks=0,0
 local env=setmetatable({bot={status=1,rotation={}},BotStatus={online=1},hospitalPending=true,shouldResumeAfterCure=true,farmRunIntent=true,intentionalStop=manual,lockoutTriggered=lockout,recoveryStatus={active=false,checking=false},getHospitalModule=function()return {hasAnyMalady=function()return healthy and false or 'unknown',0 end}end,checkRecoveryStatus=function()checks=checks+1;return false end,beginSpamRecovery=function()end,resumeFarming=function()if manual or lockout then return false end;resumed=resumed+1;return true end,setRotationEnabled=function()end},{__index=_G})
 -- Lua and/or cannot encode false; supply explicit predicate.
 env.getHospitalModule=function()return {hasAnyMalady=function()if healthy then return false,0 end;return 'unknown',nil end}end
 local fn=assert(load(code,'@production-dispatcher','t',env))();fn()
 return resumed,checks,env.hospitalPending
end
local n,c,p=test(false,false,true);assert(n==1 and c==0 and p==false)
assert(test(true,false,true)==0)
assert(test(false,true,true)==0)
assert(test(false,false,false)==0)
print('PASS actual dispatcher: valid Healthy resumes despite unknown Recovering; manual stop/lockout honored; unknown malady not cured')
