local m=assert(loadfile('auto_malady_4aid.lua'))('module')
BotStatus={online=1};printLog={};sleep=function()end
local function run(fail)
 local packets,paths={},{};local b={status=1,malady=1,x=0,y=0,world='FARM'}
 function b:isInWorld(w)return w and self.world==w or (not w and self.world~='')end
 function b:warp(w)assert(w=='BPJS');self.world=w end
 function b:findPath(x,y)paths[#paths+1]=x..','..y;self.x=x;self.y=y;return true end
 function b:enter()end
 function b:hit()error('BPJS must not hit adventure key')end
 function b:sendPacket(t,p)
 assert(t==2);packets[#packets+1]=p
 if fail then return end
 if #packets==1 then self.x=4;self.y=18 else self.x=62;self.y=29 end
 end
 local result=m.runCure(b,nil,function()return true end,'BPJS')
 if fail then assert(result==false and #packets==1) else
 assert(result=='recovering' and #packets==2)
 assert(packets[1]:find('tilex|8|',1,true) and packets[1]:find('tiley|20|',1,true) and packets[1]:find('buttonClicked|button3',1,true))
 assert(packets[2]:find('tiley|18|',1,true) and packets[2]:find('buttonClicked|button0',1,true))
 assert(paths[#paths]=='73,29')
 end
end
run(false);run(true)
print('PASS BPJS real module: two dialogs, no hit, bed 73,29, Recovering exit; rejected teleport aborts')
