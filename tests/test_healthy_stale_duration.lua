local m=assert(loadfile('auto_malady_4aid.lua'))('module')
local b={malady=0,getMaladyDuration=function()return 5392 end}
local sick,id=m.hasAnyMalady(b);assert(sick==false and id==0)
b.malady=1;sick,id=m.hasAnyMalady(b);assert(sick==true and id==1)
b.malady=2;sick,id=m.hasAnyMalady(b);assert(sick==true and id==2)
b.malady=nil;assert(m.hasAnyMalady(b)=='unknown')
b.malady=-1;assert(m.hasAnyMalady(b)=='unknown')
print('PASS explicit Healthy ID 0 remains Healthy with positive stale duration; Torn/Gem remain sick; invalid stays unknown')
