-- Panasonic maker-note tags as the Metadata panel text: look and mode, adjustments only when off normal.
local M = {}
local styles = {
    [0] = 'AUTO', [1] = 'STANDARD', [2] = 'VIF', [3] = 'NATUREL', [4] = 'MONOCHROME', [5] = 'PAYSAGE',
    [6] = 'PORTRAIT', [8] = 'CINELIKE D', [9] = 'CINELIKE V', [11] = 'L.MONOCHROME', [12] = 'LIKE709',
    [15] = 'L.MONOCHROME D', [17] = 'V-LOG', [18] = 'CINELIKE D2',
}
local films = {
    [1] = 'STANDARD', [2] = 'DYNAMIQUE', [3] = 'NATURE', [4] = 'DOUX', [5] = 'STANDARD N&B',
    [6] = 'DYNAMIQUE N&B', [7] = 'DOUX N&B', [10] = 'NOSTALGIQUE', [11] = 'VIBRANT',
}
local effects = { [2] = 'CHAUD', [3] = 'FROID', [4] = 'N&B', [5] = 'SÉPIA', [6] = 'HAPPY', [8] = 'VIVID' }
local wb = {
    [1] = 'AUTO', [2] = 'JOUR', [3] = 'NUAGEUX', [4] = 'INCANDESCENT', [5] = 'MANUEL', [8] = 'FLASH',
    [10] = 'N&B', [11] = 'MANUEL 2', [12] = 'OMBRE', [13] = 'KELVIN', [14] = 'MANUEL 3',
    [15] = 'MANUEL 4', [19] = 'AUTO FROID',
}
local modes = {
    [1] = 'Normal', [2] = 'Portrait', [3] = 'Paysage', [4] = 'Sport', [5] = 'Portrait de nuit',
    [6] = 'Programme', [7] = 'Priorité ouverture', [8] = 'Priorité vitesse', [9] = 'Macro',
    [11] = 'Manuel', [21] = 'Paysage de nuit', [22] = 'Gastronomie', [24] = 'Peau douce',
    [37] = 'Auto intelligent', [45] = 'Ma couleur', [59] = 'Contrôle créatif', [60] = 'Auto intelligent +',
}
local strength = { [0] = 'off', [1] = 'faible', [2] = 'standard', [3] = 'fort', [4] = 'étendu' }
-- The encoding of the noise reduction value differs between models; this is ExifTool's table.
local noise = { [0] = 0, [1] = -1, [2] = 1, [3] = -2, [4] = 2, [5] = 5, [6] = 6,
    [65531] = -5, [65532] = -4, [65533] = -3, [65534] = -2, [65535] = -1 }
local adjustments = { { 0x39, 'Contraste' }, { 0x40, 'Saturation' }, { 0x41, 'Netteté' } }

local function signed(n)
    if type(n) == 'number' and n >= 32768 then return n - 65536 end
    return n
end
local function number(n)
    if n > 0 then return '+' .. tostring(n) end
    return (tostring(n):gsub('^-', '−'))
end

function M.describe(data)
    local t = data.tags
    local first, second, details = {}, {}, {}
    local style
    if t[0x89] ~= nil then
        style = styles[t[0x89]] or 'STYLE ?'
    elseif t[0x42] ~= nil and t[0x42] ~= 0 then
        style = films[t[0x42]] or 'MODE FILM ?'
    end
    if style then first[#first + 1] = style end
    if t[0x28] ~= nil and t[0x28] ~= 1 then first[#first + 1] = effects[t[0x28]] or 'EFFET ?' end
    first[#first + 1] = 'WB ' .. (wb[t[0x03]] or '?')

    if t[0x1f] ~= nil then second[#second + 1] = modes[t[0x1f]] or 'Mode ?' end
    local values = {}
    for _, item in ipairs(adjustments) do
        local value = signed(t[item[1]])
        if type(value) == 'number' then
            values[#values + 1] = item[2] .. ' ' .. number(value)
            if value ~= 0 then second[#second + 1] = values[#values] end
        end
    end
    if t[0x2d] ~= nil then
        local value = noise[t[0x2d]]
        values[#values + 1] = 'Bruit ' .. (value and number(value) or '?')
        if value ~= 0 then second[#second + 1] = values[#values] end
    end

    if t[0x89] == 1 then details[#details + 1] = 'Style standard ou personnalisé : le boîtier ne précise pas.' end
    if t[0x1f] ~= nil and not modes[t[0x1f]] then
        details[#details + 1] = 'Mode de prise de vue : code ' .. tostring(t[0x1f])
    end
    if #values > 0 then details[#details + 1] = table.concat(values, ' · ') end
    local smart = {}
    for _, item in ipairs({ { 0x70, 'i.Résolution' }, { 0x79, 'i.Dynamique' }, { 0x5d, 'Exposition intelligente' } }) do
        if t[item[1]] ~= nil then smart[#smart + 1] = item[2] .. ' ' .. (strength[t[item[1]]] or '?') end
    end
    if t[0x49] ~= nil then
        smart[#smart + 1] = 'Bruit pose longue ' .. (({ [1] = 'off', [2] = 'on' })[t[0x49]] or '?')
    end
    if #smart > 0 then details[#details + 1] = table.concat(smart, ' · ') end
    return {
        first = table.concat(first, ' · '), second = table.concat(second, ' · '),
        details = table.concat(details, '\n'),
    }
end

return M
