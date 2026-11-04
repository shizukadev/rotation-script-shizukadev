local f=assert(io.open('engine.lua'));local s=f:read('*a'):gsub('\r','');f:close()
local a=assert(s:find('    if gemWaitActive then',1,true));local z=assert(s:find('\n    if anySick == false then',a,true));local code=s:sub(a,z-1)..'\nreturn "continue"'
local function test(clear,sick,id)
 local waits=0
 local env=setmetatable({gemWaitActive=true,gemWaitNextWarp=999,lastHospitalAttempt=999,anySick=sick,curId=id,checkRecoveryStatus=function()return clear end,waitGemCutsWorld=function()waits=waits+1 end,print=function()end},{__index=_G})
 local result=assert(load(code,'@production-wait-state','t',env))()
 return result,env,waits
end
local r,e,w=test(false,true,2);assert(r==false and e.gemWaitActive and w==1)
r,e,w=test(true,true,2);assert(r=='continue' and not e.gemWaitActive and e.lastHospitalAttempt==0 and w==0)
r,e,w=test(false,'unknown',nil);assert(r==false and e.gemWaitActive and w==1)
r,e,w=test(false,false,0);assert(r=='continue' and not e.gemWaitActive)
print('PASS luacid: active/unknown recovery waits, verified recovery clearance with Gem Cuts permits hospital retry, Healthy exits waiting')
