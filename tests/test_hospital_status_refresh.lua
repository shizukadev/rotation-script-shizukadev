local t,calls=0,{}
local b={status=1,malady=1,x=0,y=0,currentWorld=''}
function b:isInWorld(w)return w and self.currentWorld==w or (not w and self.currentWorld~='')end
function b:warp(w)self.currentWorld=w end
function b:findPath(x,y)self.x=x;self.y=y;return true end
function b:hit()end
function b:enter()end
function b:sendPacket()end
function b:say(s)
 assert(s=='/status' and self.status==1 and self.currentWorld=='4AID')
 calls[#calls+1]=t
 if #calls==3 then self.malady=0 end
end
local env=setmetatable({BotStatus={online=1},sleep=function(ms)t=t+ms end,print=function()end,addEvent=function()end,Event={variantlist=1}},{__index=_G})
local f=assert(io.open('auto_malady_4aid.lua'));local src=f:read('*a');f:close()
local m=assert(load(src,'@malady','t',env))('module')
assert(m.runCure(b)=='cured')
assert(#calls==3 and calls[2]-calls[1]==5000 and calls[3]-calls[2]==5000)
print('PASS hospital /status requests every 5000ms; valid Healthy required')
