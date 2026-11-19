local M = {}
local films = {
    [0] = 'PROVIA', [0x120] = 'ASTIA', [0x200] = 'VELVIA', [0x400] = 'VELVIA',
    [0x500] = 'PRO NEG. STD', [0x501] = 'PRO NEG. HI', [0x600] = 'CLASSIC CHROME',
    [0x700] = 'ETERNA', [0x800] = 'CLASSIC NEG.', [0x900] = 'BLEACH BYPASS',
    [0xa00] = 'NOSTALGIC NEG.', [0xb00] = 'REALA ACE',
}
local monochrome = {
    [0x300] = 'MONOCHROME', [0x301] = 'MONOCHROME +R', [0x302] = 'MONOCHROME +Y',
    [0x303] = 'MONOCHROME +G', [0x310] = 'SEPIA', [0x500] = 'ACROS',
    [0x501] = 'ACROS +R', [0x502] = 'ACROS +Y', [0x503] = 'ACROS +G',
}
local wb = {
    [0] = 'AUTO', [1] = 'AUTO BLANC', [2] = 'AUTO AMBIANCE', [0x100] = 'JOUR',
    [0x200] = 'NUAGEUX', [0x300] = 'FLUO 1', [0x301] = 'FLUO 2',
    [0x302] = 'FLUO 3', [0x303] = 'FLUO CHAUD', [0x304] = 'FLUO SALON',
    [0x400] = 'INCANDESCENT', [0x500] = 'FLASH', [0x600] = 'SOUS-MARIN',
    [0xf00] = 'PERSO 1', [0xf01] = 'PERSO 2', [0xf02] = 'PERSO 3',
    [0xf03] = 'PERSO 4', [0xf04] = 'PERSO 5',
}
local saturation = { [0] = 0, [0x80] = 1, [0x100] = 2, [0xc0] = 3, [0xe0] = 4,
    [0x180] = -1, [0x400] = -2, [0x4c0] = -3, [0x4e0] = -4 }
local sharpness = { [0] = -4, [1] = -3, [2] = -2, [3] = 0, [4] = 2,
    [5] = 3, [6] = 4, [0x82] = -1, [0x84] = 1 }
local noise = { [0] = 0, [0x100] = 2, [0x180] = 1, [0x1c0] = 3, [0x1e0] = 4,
    [0x200] = -2, [0x280] = -1, [0x2c0] = -3, [0x2e0] = -4 }
local strength = { [0] = 'off', [32] = 'faible', [64] = 'fort' }
-- Vocabulary of Recipes.lua (scripts/build_recipes.py), used to match recipes.
-- Fluorescent 1/2/3 follow Exiv2's Fuji table (daylight / warm white / cool white).
-- The additional legacy codes stay distinct; they cannot stand in for a numbered preset.
local whiteKinds = { [0] = 'auto', [1] = 'auto-white', [2] = 'auto-ambience',
    [0x100] = 'daylight', [0x200] = 'shade', [0x300] = 'fluorescent-1',
    [0x301] = 'fluorescent-2', [0x302] = 'fluorescent-3', [0x303] = 'fluorescent-warm-white',
    [0x304] = 'fluorescent-living-room', [0x400] = 'incandescent', [0x600] = 'underwater',
    [0xff0] = 'kelvin' }
local levels = { [0] = 'off', [32] = 'weak', [64] = 'strong' }
-- 16 and 48 already carry the small size; 32 and 64 take it from tag 0x104c.
local grains = { [0] = 'off', [16] = 'weak', [32] = 'weak', [48] = 'strong', [64] = 'strong' }
local grainSizes = { [16] = 'small', [32] = 'large' }
local priorities = { [1] = 'weak', [2] = 'strong' }
local priorityNames = { [1] = 'FAIBLE', [2] = 'FORTE', [3] = 'PLUS' }

local function drPriority(t)
    if t[0x1443] == nil then return 'off' end
    if t[0x1443] == 0 then return 'auto' end
    if t[0x1443] == 1 then return priorities[t[0x1445]] end
end
local function number(n)
    if n == nil then return '?' end
    if n > 0 then return '+' .. tostring(n) end
    return tostring(n):gsub('^-', '−')
end
local function divide(n, divisor) if n ~= nil then return n / divisor end end

function M.describe(data)
    local t = data.tags
    local film = monochrome[t[0x1003]] or films[t[0x1401]] or 'Simulation inconnue'
    local drValue = t[0x1403] or t[0x140b]
    local dr = drValue and ('DR' .. tostring(drValue)) or
        (t[0x1400] == 1 and 'DR100' or 'DR ?')
    if t[0x1402] == 0 and not drValue then dr = 'DR AUTO' end
    if t[0x1443] ~= nil then
        if t[0x1443] == 0 then
            dr = 'PRIORITÉ DR AUTO (' .. (priorityNames[t[0x1444]] or '?') .. ')'
        else
            dr = 'PRIORITÉ DR ' ..
                (t[0x1443] == 1 and priorities[t[0x1445]] and priorityNames[t[0x1445]] or '?')
        end
    end
    local white = wb[t[0x1002]] or 'INCONNUE'
    if t[0x1002] == 0xff0 then white = t[0x1005] and (t[0x1005] .. ' K') or 'KELVIN ?' end
    local shift = t[0x100a]
    local shiftText = type(shift) == 'table' and
        ('R ' .. number(divide(shift[1], 20)) .. ' / B ' .. number(divide(shift[2], 20))) or 'décalage ?'
    local first = film .. ' · ' .. dr .. ' · WB ' .. white
    if type(shift) == 'table' and (shift[1] ~= 0 or shift[2] ~= 0) then
        first = first .. ' · ' .. shiftText
    end
    local second = 'H ' .. number(divide(t[0x1041], -16)) ..
        ' · S ' .. number(divide(t[0x1040], -16)) ..
        ' · Couleur ' .. (monochrome[t[0x1003]] and 'N/B' or number(saturation[t[0x1003]])) ..
        ' · Netteté ' .. number(sharpness[t[0x1001]])
    local grain = ({ [0] = 'off', [16] = 'faible/petit', [32] = 'faible',
        [48] = 'fort/petit', [64] = 'fort' })[t[0x1047]] or '?'
    if t[0x1047] ~= 0 then
        local size = ({ [16] = 'petit', [32] = 'grand' })[t[0x104c]]
        if size and not grain:find('/', 1, true) then grain = grain .. '/' .. size end
    end
    return {
        first = first, second = second,
        details = 'Grain ' .. grain .. ' · Chrome ' .. (strength[t[0x1048]] or '?') ..
            ' · Bleu ' .. (strength[t[0x104e]] or '?') .. '\n' ..
            'Bruit ' .. number(noise[t[0x100e]]) .. ' · Clarté ' .. number(divide(t[0x100f], 1000)) ..
            ' · WB ' .. shiftText .. (t[0x1402] == 0 and ' · DR réglé sur Auto' or ''),
    }
end

-- Settings in the vocabulary of Recipes.lua; nil when absent or not recognized.
-- DR priority records its mode in 0x1443 and its auto/fixed strength in 0x1444/0x1445.
function M.settings(data)
    local t = data.tags
    local shift = type(t[0x100a]) == 'table' and t[0x100a] or {}
    local grain, size = grains[t[0x1047]], grainSizes[t[0x104c]]
    if t[0x1047] == 16 or t[0x1047] == 48 then size = 'small' end
    if grain == 'off' then size = nil end
    return {
        film = monochrome[t[0x1003]] or films[t[0x1401]],
        dr = t[0x1402] == 0 and 'auto' or t[0x1403] or t[0x140b],
        drPriority = drPriority(t),
        wb = whiteKinds[t[0x1002]],
        kelvin = t[0x1002] == 0xff0 and t[0x1005] or nil,
        shiftR = divide(shift[1], 20), shiftB = divide(shift[2], 20),
        highlight = divide(t[0x1041], -16), shadow = divide(t[0x1040], -16),
        color = saturation[t[0x1003]],
        grain = grain, grainSize = size,
        chrome = levels[t[0x1048]], chromeBlue = levels[t[0x104e]],
        sharpness = sharpness[t[0x1001]], noise = noise[t[0x100e]],
        clarity = divide(t[0x100f], 1000),
    }
end

local function drText(dr)
    if dr == 'auto' then return 'DR AUTO' end
    return dr and ('DR' .. tostring(dr)) or 'DR ?'
end

-- Recipe and Source fields, one line each, for a RecipeMatch.find result. A recipe that
-- differs only by its dynamic range is still named; Source says which DR the photo used.
-- Without a recipe, Source names the closest one and what differs.
function M.recipe(result)
    local names, sources, seen = {}, {}, {}
    local function add(recipe, note)
        names[#names + 1] = recipe.name
        local source = (recipe.source or '') .. (note or '')
        if source ~= '' and not seen[source] then
            seen[source] = true
            sources[#sources + 1] = source
        end
    end
    for _, recipe in ipairs(result.matches) do add(recipe) end
    if #names == 0 then
        for _, recipe in ipairs(result.drMatches or {}) do
            add(recipe, (recipe.source and ' · ' or '') .. drText(result.dr) .. ' au lieu de ' .. drText(recipe.dr))
        end
    end
    if #names > 0 then return table.concat(names, ' / '), table.concat(sources, ' / ') end
    if result.near then
        return 'Recette non identifiée', 'Plus proche : ' .. result.near.name ..
            ' (écarts : ' .. table.concat(result.differences, ', ') .. ')'
    end
    return 'Recette non identifiée', 'Aucune recette proche'
end
return M
