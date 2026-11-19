-- The recipes in use: the CSV chosen in the Plug-in Manager, or recipes.csv shipped with the
-- plugin. The file is read again when its modification date changes, so an edited CSV
-- applies to the next photos read without reloading the plugin.
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local Csv = dofile(LrPathUtils.child(_PLUGIN.path, 'RecipeCsv.lua'))
local M = {}
local loaded

function M.defaultPath()
    return LrPathUtils.child(_PLUGIN.path, 'recipes.csv')
end

function M.path()
    local chosen = LrPrefs.prefsForPlugin().recipesPath
    if type(chosen) == 'string' and chosen ~= '' then return chosen end
    return M.defaultPath()
end

-- { path, recipes, errors }: errors lists the lines left out, or why the file was not read.
function M.load(path)
    local file = io.open(path, 'rb')
    if not file then return { path = path, recipes = {}, errors = { 'Fichier introuvable : ' .. path } } end
    local text = file:read('*a')
    file:close()
    local recipes, errors = Csv.parse(text)
    return { path = path, recipes = recipes, errors = errors }
end

-- The same table while the file is unchanged: callers compare it to know when to recompute.
function M.current()
    local path = M.path()
    local attributes = LrFileUtils.fileAttributes(path)
    local stamp = attributes and attributes.fileModificationDate
    if not loaded or loaded.path ~= path or loaded.stamp ~= stamp then
        loaded = M.load(path)
        loaded.stamp = stamp
    end
    return loaded
end

return M
