for _,name in ipairs({'engine.lua','rotation_final.lua'})do
 local f=assert(io.open(''..name));local s=f:read('*a'):gsub('\r','');f:close()
 local a=assert(s:find('local function hospitalForLevel',1,true));local z=assert(s:find('local function checkAndDispatchHospital',a,true))
 local choose=assert(load(s:sub(a,z-1)..'return hospitalForLevel'))()
 assert(choose(11)==nil and choose(15)==nil and choose(16)=='BPJS' and choose(35)=='BPJS' and choose(36)=='4AID' and choose(100)=='4AID')
 assert(choose(nil)==nil and choose('36')==nil and choose(35.5)==nil and choose(0/0)==nil)
 local p=assert(s:find('    local levelOK, currentLevel',z,true));local q=assert(s:find('\n    lastHospitalAttempt = now',p,true))
 local calls=0;local env=setmetatable({bot={level=12,rotation={}},hospitalForLevel=choose,farmRunIntent=true,intentionalStop=false,now=100,setRotationEnabled=function(on)assert(on==false);calls=calls+1 end,print=function()end},{__index=_G})
 assert(load(s:sub(p,q-1)..'\nreturn "4aid"','@production-level-gate','t',env))() -- returns false before route
 assert(env.hospitalPending and calls==1)
 print('PASS '..name..': level boundaries, invalid levels, BPJS pauses without executing 4AID')
end
