-- Reuse host fixture, but execute the real engine and real dispatcher.
local f=assert(io.open('tests/test_engine_rotation.lua'));local fixture=f:read('*a');f:close()
fixture=fixture:sub(1,assert(fixture:find('-- 1. Registrasi world',1,true))-1)
fixture=fixture:gsub('rotation = rotation, auto_malady = malady,','rotation = rotation, auto_malady = malady, malady = 1,')
local a=assert(fixture:find('        sleep = function()',1,true))
local b=assert(fixture:find('        print = function',a,true))
fixture=fixture:sub(1,a-1)..[[
        require = function(name)
            if name ~= 'auto_malady_4aid' then error('not installed') end
            return {
                hasAnyMalady=function(b) return b.malady > 0,b.malady end,
                checkNeedsHospital=function(b) return b.malady==1,b.malady end,
                runCure=function(b)
                    assert(b.rotation.enabled==false,'rotation must pause before hospital')
                    st.hospitalVisits=(st.hospitalVisits or 0)+1
                    b.malady=0
                    return 'cured'
                end,
            }
        end,
        sleep = function()
            st.ticks=(st.ticks or 0)+1
            if st.ticks==1 then rotation.enabled=false end
            if st.ticks>4 then error('TERMINATE_TEST_LOOP') end
        end,
]]..fixture:sub(b)
fixture=fixture..[[
local result=boot()
assert(result.hospitalVisits==1,'hospital must run once despite stopped rotation: '..result.text)
assert(result.rotation.enabled==false,'manual farm stop must remain after cure')
print('PASS stopped farm + ID 1: hospital dispatched once; farm remains stopped after cure')
]]
assert(load(fixture,'@hospital-stopped-fixture'))()
local failedSetup = fixture:gsub('setTrashList = function', 'setTrashList = function')
failedSetup = failedSetup:gsub('getWorldManager = function%(%) return manager end,', 'getWorldManager = function() error("SIMULATED setup API failure") end,')
-- Force applyBotSettings to throw on an optional module field.
failedSetup = failedSetup:gsub('auto_malady = malady,', 'auto_malady = setmetatable({}, {__newindex=function() error("SIMULATED unsupported host property") end}),')
assert(load(failedSetup,'@hospital-startup-failure-fixture'))()
print('PASS hospital supervisor survives bot setup exception')
