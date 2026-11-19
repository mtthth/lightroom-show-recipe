-- Matches camera settings (FujiFormat.settings) with the recipes of Recipes.lua.
-- The camera does not store the recipe name: a recipe is recognized when every
-- setting it specifies is equal. A setting a recipe leaves out matches anything
-- (DR priority replaces DR and tones, monochrome has no colour).
local M = {}
local fields = {
    { 'film', 'Simulation' }, { 'dr', 'Plage dynamique' }, { 'drPriority', 'Priorité DR' },
    { 'wb', 'Balance des blancs' }, { 'kelvin', 'Température' },
    { 'shiftR', 'Décalage WB R' }, { 'shiftB', 'Décalage WB B' },
    { 'highlight', 'Hautes lumières' }, { 'shadow', 'Ombres' }, { 'color', 'Couleur' },
    { 'grain', 'Grain' }, { 'grainSize', 'Taille du grain' },
    { 'chrome', 'Color Chrome' }, { 'chromeBlue', 'Color Chrome Blue' },
    { 'sharpness', 'Netteté' }, { 'noise', 'Bruit' }, { 'clarity', 'Clarté' },
}
local nearLimit = 3

local function same(a, b)
    if type(a) == 'number' and type(b) == 'number' then return math.abs(a - b) < 1e-6 end
    return a == b
end

-- Labels of the settings that differ; an absent setting differs from a specified one.
function M.differences(recipe, settings)
    local result = {}
    for _, field in ipairs(fields) do
        local expected = recipe[field[1]]
        if expected ~= nil and not same(expected, settings[field[1]]) then
            result[#result + 1] = field[2]
        end
    end
    return result
end

-- matches: recipes with no difference. Otherwise near: the recipe differing by
-- the fewest settings (at most nearLimit), with their labels in differences.
function M.find(recipes, settings)
    local result = { matches = {} }
    for _, recipe in ipairs(recipes) do
        local differences = M.differences(recipe, settings)
        if #differences == 0 then
            result.matches[#result.matches + 1] = recipe
        elseif #differences <= nearLimit and
            (not result.near or #differences < #result.differences) then
            result.near, result.differences = recipe, differences
        end
    end
    return result
end

return M
