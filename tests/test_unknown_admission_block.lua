local f=assert(io.open('engine.lua'));local s=f:read('*a'):gsub('\\r','');f:close()
local a=assert(s:find('local function checkAndDispatchHospital()',1,true))
local z=assert(s:find('\nlocal farmLabel',a,true))
local code=s:sub(a,z-1)..'\nreturn checkAndDispatchHospital'
local function run(clear,state)
 local cured,routed,enabled=0,0,true
 local env=setmetatable({
  bot={status=1,rotation={},level=50,name='T'},
  BotStatus={online=1},
  getHospitalModule=function()return{
   hasAnyMalady=function()return true,1 end,
   checkNeedsHospital=function()return true,1 end,
   runCure=function()routed=routed+1;cured=cured+1;return 'cured' end}end,
  checkRecoveryStatus=function()return clear end,
  recoveryStatus=state,
  hospitalPending=false,shouldResumeAfterCure=true,farmRunIntent=true,intentionalStop=false,
  beginSpamRecovery=function()end,
  resumeFarming=function()return true end,
  setRotationEnabled=function(v)enabled=v end,
  updateWebhook=function()end,sendWebhookNotification=function()end,
  updateNativeMaladyForLevel=function()return true end,
  hospitalForLevel=function(lv)if lv>=36 then return '4AID' end if lv>=16 then return 'BPJS' end return nil end,
  HOSPITAL_COOLDOWN=180,lastHospitalAttempt=0,
  os={time=function()return 1000 end},print=function()end,
 },{__index=_G})
 assert(load(code,'@unknown-admission','t',env))()()
 return routed,enabled,env.hospitalPending
end

-- UNKNOWN (respons belum terverifikasi): admission WAJIB ditahan.
local routed,enabled,pending=run(false,{active=false,known=false,checking=true})
assert(routed==0,'UNKNOWN tidak boleh dispatch ke rumah sakit')
assert(enabled==false and pending==true,'UNKNOWN harus menahan rotasi dan menandai pending')

-- Sedang memeriksa (checking) juga belum boleh lolos.
routed=run(false,{active=false,known=true,checking=true})
assert(routed==0,'status masih diperiksa tidak boleh dispatch')

-- Build tanpa fasilitas event: UNKNOWN, admission tetap ditahan.
routed,enabled,pending=run(false,{active=false,known=false,checking=false})
assert(routed==0,'tanpa event tidak boleh menganggap Recovering hilang')
assert(enabled==false and pending==true,'tanpa event harus menahan rotasi dan pending')

print('PASS dispatcher penuh: UNKNOWN/checking/tanpa-event menahan admission')
