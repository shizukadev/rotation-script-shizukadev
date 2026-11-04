for _,name in ipairs({'engine.lua','rotation_final.lua'})do
 local f=assert(io.open(name));local s=f:read('*a'):gsub('\r','');f:close()
 local a=assert(s:find('local function hospitalForLevel',1,true));local z=assert(s:find('local function checkAndDispatchHospital',a,true))
 local choose=assert(load(s:sub(a,z-1)..'return hospitalForLevel'))()
 assert(choose(1)=='4AID' and choose(12)=='4AID' and choose(15)=='4AID' and choose(16)=='4AID' and choose(36)=='4AID' and choose(100)=='4AID')
 assert(choose(nil)==nil and choose('36')==nil and choose(35.5)==nil and choose(0/0)==nil)
 local p=assert(s:find('    local levelOK, currentLevel',z,true));local q=assert(s:find('\n    lastHospitalAttempt = now',p,true))
 local env=setmetatable({bot={level=12,rotation={}},hospitalForLevel=choose,fourAidFails=0,FOUR_AID_MAX_FAILS=5,print=function()end},{__index=_G})
 local world=assert(load(s:sub(p,q-1)..'\nreturn hospitalWorld','@production-level-gate','t',env))()
 assert(world=='4AID','level 12 harus memakai 4AID, dapat '..tostring(world))
 print('PASS '..name..': semua level valid memakai 4AID, level invalid nil')
end
