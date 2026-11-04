local f=assert(io.open('engine.lua'));local s=f:read('*a');f:close()
s=s:gsub('\r','')
local dispatchStart=assert(s:find('local function checkAndDispatchHospital()',1,true))
s=s:sub(dispatchStart)
local a=assert(s:find('    local recoveryClear = checkRecoveryStatus()',1,true))
local z=assert(s:find('    -- Evaluasi',a,true))
local gate=s:sub(a,z-1)
local function run(active,checking,clear,pending,intent,manual)
 local resumed=0
 local env=setmetatable({checkRecoveryStatus=function()return clear end,recoveryStatus={active=active,checking=checking},hospitalPending=pending,shouldResumeAfterCure=true,curId=1,farmRunIntent=intent,intentionalStop=manual,resumeFarming=function()resumed=resumed+1 end},{__index=_G})
 local result=assert(load(gate..'\nreturn "admission"','@production-gate','t',env))()
 return result,resumed,env.hospitalPending
end
local result,resumed,pending=run(true,false,false,true,true,false)
assert(result==false and resumed==1 and pending==false)
local _,stopped=run(true,false,false,true,true,true);assert(stopped==0)
assert(run(false,false,false,false,true,false)==false)
assert(run(false,false,true,false,true,false)=='admission')
print('PASS hospital production gate: Recovering resumes pending farming, manual stop preserved, unknown blocks, confirmed clearance permits admission checks')
