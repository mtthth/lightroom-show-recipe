-- Matches camera settings (FujiFormat.settings) with the recipes of the recipe CSV.
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

-- Differences that still name the recipe: the dynamic range is chosen for the light of the
-- scene, and a clarity above the recipe's is accepted (clarity slows the camera down, so it
-- is often left closer to 0 than the recipe says).
local tolerated = {
    dr = function() return true end,
    clarity = function(expected, actual) return type(actual) == 'number' and actual > expected end,
}

-- Labels of the settings that differ; an absent setting differs from a specified one.
-- The second list holds the keys of the differences, in the same order.
function M.differences(recipe, settings)
    local labels, keys = {}, {}
    for _, field in ipairs(fields) do
        local expected = recipe[field[1]]
        if expected ~= nil and not same(expected, settings[field[1]]) then
            labels[#labels + 1] = field[2]
            keys[#keys + 1] = field[1]
        end
    end
    return labels, keys
end

-- matches: recipes with no difference. Otherwise closeMatches: recipes whose only
-- differences are tolerated (see above); the photo's own DR is in dr. Otherwise near: the
-- recipe differing by the fewest settings (at most nearLimit), with their labels in differences.
function M.find(recipes, settings)
    local result = { matches = {}, closeMatches = {}, dr = settings.dr }
    for _, recipe in ipairs(recipes) do
        local labels, keys = M.differences(recipe, settings)
        local close = #keys > 0
        for _, key in ipairs(keys) do
            if not (tolerated[key] and tolerated[key](recipe[key], settings[key])) then close = false end
        end
        if #labels == 0 then
            result.matches[#result.matches + 1] = recipe
        elseif close then
            result.closeMatches[#result.closeMatches + 1] = recipe
        elseif #labels <= nearLimit and
            (not result.near or #labels < #result.differences) then
            result.near, result.differences = recipe, labels
        end
    end
    return result
end

return M
