"""A Lupa runtime offering the little of Lightroom the plugin's modules need to find each other."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.test-deps'))
from lupa.lua51 import LuaRuntime


def runtime(**options):
    lua = LuaRuntime(**options)
    lua.globals().pluginPath = str(ROOT / 'show-recipe.lrplugin').replace('\\', '/')
    lua.execute('''
        _PLUGIN = { path = pluginPath }
        import = function(name)
            assert(name == 'LrPathUtils', name)
            return { child = function(a, b) return a .. '/' .. b end }
        end
    ''')
    return lua
