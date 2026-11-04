local M=assert(loadfile('webhook_monitor.lua'))()
local disk,out={},{}
local t=100
local fio={open=function(path,mode)
 if mode=='w' then return {write=function(_,s)disk[path]=s end,close=function()end}end
 if not disk[path]then return nil end
 return {read=function()return disk[path]:gsub('\n$','')end,close=function()end}
end}
local function bot(n)return {name=n,status=1,malady=0,gem_count=1,rotation={enabled=true,status=2},isInWorld=function()return false end}end
local a,b=bot('A'),bot('B');a.index=1;b.index=2
local function api()return {os={time=function()return t end,getenv=function()return 'VIRTUAL' end},io=fio,BotStatus={online=1},RotationStatus={farm=2,plant=3},getBots=function()error('native enumeration forbidden')end,Webhook={new=function()return {edit=function(self)out[#out+1]=self.content;return true end,send=function()error('POST forbidden')end}end}}end
local cfg={MULTI_BOT={startbot=1,endbot=11},WEBHOOK={ENABLED=true,URL='https://example.invalid/h',GLOBAL=true,MESSAGE_ID='123',UPDATE_INTERVAL_SECONDS=5}}
local ma,mb=M.new(a,cfg,api()),M.new(b,cfg,api())
mb.tick();ma.tick();assert(#out==0);t=110;mb.tick();ma.tick();assert(#out==1)
assert(out[1]:find('2 Online, 0 Offline, 0 Unknown',1,true))
t=115;b.rotation.status=3;mb.tick();ma.tick();assert(out[2]:find('ON plant',1,true))
b.status=0;b.malady=nil;setmetatable(b,{__index=function(_,k)if k=='malady'then error('offline malady forbidden')end end})
t=120;mb.tick();ma.tick();assert(out[3]:find('1 Online, 1 Offline, 0 Unknown',1,true))
t=180;ma.tick();assert(out[#out]:find('1 Online, 0 Offline, 0 Unknown',1,true))
print('PASS separate VM APIs, self snapshots, no getBots, offline malady guard, non-leader phase, stale UNKNOWN')
