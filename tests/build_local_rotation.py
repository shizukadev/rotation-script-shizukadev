"""Build a self-contained Lucifer entrypoint from the local reviewed sources."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT
loader = (PROJECT / 'loader.lua').read_text(encoding='utf-8-sig')
config = loader.split('-- 2. LOADER DARI GITHUB RAW')[0]
parts = ['-- LOCAL BUNDLE: no engine/module download. Edit CONFIG below.\n', config]
parts.append('\nlocal bundledModules = {}\n')
for name in ('auto_malady_4aid', 'webhook_monitor'):
    source = (PROJECT / (name + '.lua')).read_text(encoding='utf-8-sig')
    parts.append('bundledModules["' + name + '"] = (function(...)\n' + source + '\nend)("module")\n')
parts.append('local hostRequire = require\nlocal function require(name)\n if bundledModules[name] then return bundledModules[name] end\n if hostRequire then return hostRequire(name) end\n error("Module unavailable: " .. tostring(name))\nend\n')
parts.append('local function runEngine(...)\n' + (PROJECT / 'engine.lua').read_text(encoding='utf-8-sig') + '\nend\nrunEngine(CONFIG)\n')
out = PROJECT / 'rotation_local.lua'
out.write_text(''.join(parts), encoding='utf-8')
print('Built ' + str(out))
