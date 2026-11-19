-- Reads a recipe CSV (same columns as recipes.csv) into the recipes RecipeMatch compares.
-- SDK independent. A row with an unknown or contradictory value is left out and reported:
-- one bad line never hides the other recipes.
local M = {}

-- CSV names -> film simulation labels of FujiFormat.lua.
M.films = {
    ['Provia/Standard'] = 'PROVIA', ['Astia/Soft'] = 'ASTIA', ['Velvia/Vivid'] = 'VELVIA',
    ['PRO Neg. Std'] = 'PRO NEG. STD', ['PRO Neg. Hi'] = 'PRO NEG. HI',
    ['Classic Chrome'] = 'CLASSIC CHROME', ['Eterna/Cinema'] = 'ETERNA',
    ['Classic Negative'] = 'CLASSIC NEG.', ['Eterna Bleach Bypass'] = 'BLEACH BYPASS',
    ['Nostalgic Negative'] = 'NOSTALGIC NEG.', ['Reala Ace'] = 'REALA ACE',
    ['Monochrome'] = 'MONOCHROME', ['Monochrome+R'] = 'MONOCHROME +R',
    ['Monochrome+Ye'] = 'MONOCHROME +Y', ['Monochrome+G'] = 'MONOCHROME +G', ['Sepia'] = 'SEPIA',
    ['Acros'] = 'ACROS', ['Acros+R'] = 'ACROS +R', ['Acros+Ye'] = 'ACROS +Y', ['Acros+G'] = 'ACROS +G',
}
-- The numbered fluorescent presets stay distinct (see FujiFormat.lua); a value such as 5500K
-- is a colour temperature.
M.whites = {
    ['Auto'] = 'auto', ['Auto (White Priority)'] = 'auto-white',
    ['Auto (Ambience Priority)'] = 'auto-ambience', ['Daylight'] = 'daylight', ['Shade'] = 'shade',
    ['Fluorescent 1'] = 'fluorescent-1', ['Fluorescent 2'] = 'fluorescent-2',
    ['Fluorescent 3'] = 'fluorescent-3', ['Incandescent'] = 'incandescent',
    ['Underwater'] = 'underwater',
}
local dynamicRanges = { ['Auto'] = 'auto', ['DR100'] = 100, ['DR200'] = 200, ['DR400'] = 400 }
local levels = { ['Off'] = 'off', ['Weak'] = 'weak', ['Strong'] = 'strong' }
local sizes = { ['Small'] = 'small', ['Large'] = 'large' }
local required = { 'nom', 'film_simulation', 'dr_priority', 'white_balance', 'grain_effect',
    'color_chrome_effect', 'color_chrome_fx_blue' }

-- Rows of fields; quoted fields may hold commas, line breaks and doubled quotes.
function M.rows(text)
    text = text:gsub('^\239\187\191', ''):gsub('\r\n', '\n'):gsub('\r', '\n')
    local rows, row, field, i, n = {}, {}, {}, 1, #text
    local quoted = false
    while i <= n do
        local c = text:sub(i, i)
        if quoted then
            if c == '"' then
                if text:sub(i + 1, i + 1) == '"' then field[#field + 1] = '"'; i = i + 1
                else quoted = false end
            else
                field[#field + 1] = c
            end
        elseif c == '"' then
            quoted = true
        elseif c == ',' then
            row[#row + 1] = table.concat(field); field = {}
        elseif c == '\n' then
            row[#row + 1] = table.concat(field); field = {}
            rows[#rows + 1] = row; row = {}
        else
            field[#field + 1] = c
        end
        i = i + 1
    end
    if #field > 0 or #row > 0 then
        row[#row + 1] = table.concat(field)
        rows[#rows + 1] = row
    end
    return rows
end

local function trim(value) return (value or ''):gsub('^%s+', ''):gsub('%s+$', '') end

local function keys(map)
    local list = {}
    for key in pairs(map) do list[#list + 1] = key end
    table.sort(list)
    return table.concat(list, ', ')
end

-- One recipe in the vocabulary of FujiFormat.settings; blank settings are left out.
-- Raises a message for an unknown or contradictory value.
-- mono_color_wc and mono_color_mg are not compared: only 0 is validated in the MakerNotes.
function M.convert(row)
    local function value(column) return trim(row[column]) end
    local function choose(column, map)
        local text = value(column)
        if text == '' then return nil end
        if map[text] == nil then
            error(column .. ' « ' .. text .. ' » inconnu ; valeurs connues : ' .. keys(map), 0)
        end
        return map[text]
    end
    local function number(column)
        local text = value(column)
        if text == '' then return nil end
        local result = tonumber(text)
        if not result then error(column .. ' « ' .. text .. ' » n’est pas un nombre', 0) end
        return result
    end
    for _, column in ipairs(required) do
        if value(column) == '' then error(column .. ' est vide', 0) end
    end
    local priority = choose('dr_priority', levels)
    local dr = choose('dynamic_range', dynamicRanges)
    if priority ~= 'off' and dr ~= nil then
        error('la priorité DR remplace la plage dynamique, qui doit rester vide', 0)
    end
    local kelvin = value('white_balance'):match('^(%d%d%d%d%d?)K$')
    return {
        name = value('nom'), source = value('source') ~= '' and value('source') or nil,
        film = choose('film_simulation', M.films),
        dr = dr, drPriority = priority,
        wb = kelvin and 'kelvin' or choose('white_balance', M.whites),
        kelvin = kelvin and tonumber(kelvin) or nil,
        shiftR = number('wb_shift_red'), shiftB = number('wb_shift_blue'),
        highlight = number('highlight'), shadow = number('shadow'), color = number('color'),
        grain = choose('grain_effect', levels), grainSize = choose('grain_size', sizes),
        chrome = choose('color_chrome_effect', levels),
        chromeBlue = choose('color_chrome_fx_blue', levels),
        sharpness = number('sharpness'), noise = number('high_iso_nr'), clarity = number('clarity'),
    }
end

-- recipes, errors: the valid recipes, and one message per line left out.
function M.parse(text)
    local rows = M.rows(text or '')
    local recipes, errors, seen = {}, {}, {}
    local header = rows[1]
    if not header then return recipes, { 'fichier vide' } end
    local columns = {}
    for i, name in ipairs(header) do columns[i] = trim(name) end
    for line = 2, #rows do
        local cells, blank = {}, true
        for i, name in ipairs(columns) do
            cells[name] = rows[line][i]
            if trim(rows[line][i]) ~= '' then blank = false end
        end
        if not blank then
            local ok, recipe = pcall(M.convert, cells)
            local name = trim(cells.nom)
            if not ok then
                errors[#errors + 1] = 'Ligne ' .. line .. (name ~= '' and (' (' .. name .. ')') or '') ..
                    ' : ' .. tostring(recipe)
            elseif seen[name] then
                errors[#errors + 1] = 'Ligne ' .. line .. ' : nom « ' .. name .. ' » déjà utilisé'
            else
                seen[name] = true
                recipes[#recipes + 1] = recipe
            end
        end
    end
    return recipes, errors
end

return M
