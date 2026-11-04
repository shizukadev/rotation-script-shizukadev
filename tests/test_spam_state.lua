local f=assert(io.open('engine.lua'));local s=f:read('*a');f:close()
local a=assert(s:find('local spamRecoveryUntil = 0',1,true));local z=assert(s:find('local webhookMonitor',a,true))
local values={};local b={name='TEST',status=1,malady=0,world='FARM'}
b.auto_spam=setmetatable({}, {__index=values,__newindex=function(_,k,v) assert(k=='enabled','must not modify '..k);values[k]=v end})
function b:isInWorld(w) return w == nil or self.world==w end
function b:say(text) assert(text=='/status') end
local cfg={AUTO_SPAM={ENABLED=true}}
local env=setmetatable({bot=b,CONFIG=cfg,BotStatus={online=1}},{__index=_G})
local tmpdir=os.getenv('TEMP') or os.getenv('TMP') or '.'
local statefile=tmpdir..'/lucifer_spam_recovery.txt'
os.remove(statefile)
local now=100
 env.os={time=function() return now end,getenv=function(k) if k=='TEMP' or k=='TMP' then return tmpdir end return os.getenv(k) end,date=os.date}
local rawUpdate,recover=assert(load(s:sub(a,z-1)..'return updateSpamState, beginSpamRecovery','@production-spam','t',env))()
local handlers={}
env.Event={game_message=1,variantlist=2}
env.addEvent=function(e,fn) handlers[e]=fn end
env.listenEvents=function() now=now+8; handlers[1]("msg|TEST's Status:"); handlers[1]('msg|0 mods active:') end
-- Recreate after installing the documented event stubs.
rawUpdate,recover=assert(load(s:sub(a,z-1)..'return updateSpamState, beginSpamRecovery','@production-spam','t',env))()
local function update() now=now+5; rawUpdate() end
update() -- request/response window; stays OFF until completed
update();assert(values.enabled==true)
for id=1,11 do b.malady=id;update();assert(values.enabled==false) end
b.malady=0;b.world='4AID';update();assert(values.enabled==false)
b.world='FARM';update();assert(values.enabled==true)
b.malady='invalid';update();assert(values.enabled==false)
b.malady=nil;b.status=0
setmetatable(b,{__index=function(_,key) if key=='malady' then error('offline malady read prohibited') end end})
update();assert(values.enabled==false)
setmetatable(b,nil);b.malady=0
b.status=1;cfg.AUTO_SPAM.ENABLED=false;update();assert(values.enabled==false)
cfg.AUTO_SPAM.ENABLED=true;recover();local curedAt=now;update();assert(values.enabled==false)
now=curedAt+3500;update();assert(values.enabled==false)
now=curedAt+3600;update();update();assert(values.enabled==true)
print('PASS recovery blocks spam until 3600 seconds elapsed')
print('PASS spam toggle only: healthy outside hospital ON; all disease IDs/hospital/unknown/offline/config OFF')

-- Regresi QC: validasi ketat respons /status terhadap Recovering
do
    os.remove(statefile)
    b.name = "TEST"
    b.malady = 0
    now = now + 100
    env.listenEvents = function()
        now = now + 8
        handlers[1]("msg|OTHER's Status:")
        handlers[1]("msg|0 mods active:")
    end
    update()
    update()
    assert(values.enabled == false, "Header milik orang lain TIDAK boleh memberikan clearance!")

    -- Kasus 2: Respons parsial (dijanjikan 3 mods, hanya 1 tiba sampai timeout) -> tetap UNKNOWN, spam OFF
    now = now + 100
    env.listenEvents = function()
        now = now + 10 -- timeout lewat deadline
        handlers[1]("msg|TEST's Status:")
        handlers[1]("msg|3 mods active:")
        handlers[1]("msg|Enhanced Digging")
        -- mod 2 dan 3 tidak pernah tiba
    end
    update()
    update()
    assert(values.enabled == false, "Respons parsial/timeout TIDAK boleh dianggap bebas Recovering!")

    -- Kasus 3: Recovering aktif diikuti mod lain/log acak TIDAK boleh ditimpa menjadi false
    now = now + 100
    env.listenEvents = function()
        now = now + 8
        handlers[1]("msg|TEST's Status:")
        handlers[1]("msg|2 mods active:")
        handlers[1]("msg|Recovering (1 hour left)")
        handlers[1]("msg|Enhanced Digging")
        handlers[1]("msg|Some unrelated chat message")
    end
    update()
    update()
    assert(values.enabled == false, "Recovering aktif TIDAK boleh ditimpa menjadi false oleh baris berikutnya!")

    -- Kasus 4: Respons lengkap valid tanpa Recovering -> sukses clearance, spam ON
    now = now + 4000 -- waktu maju melampaui sisa durasi recovering kasus 3
    env.listenEvents = function()
        now = now + 8
        handlers[1]("msg|TEST's Status:")
        handlers[1]("msg|1 mod active:")
        handlers[1]("msg|Enhanced Digging")
    end
    update()
    update()
    assert(values.enabled == true, "Respons lengkap valid tanpa Recovering HARUS memberikan clearance dan mengaktifkan spam!")
    print("PASS 4 regresi validasi respons /status dan proteksi status Recovering")
end
