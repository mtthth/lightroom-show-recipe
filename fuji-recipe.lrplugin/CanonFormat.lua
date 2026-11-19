-- Canon maker-note tags as the Metadata panel text: look and mode, adjustments only when off normal.
local M = {}
local styles = {
    [0x01] = 'STANDARD', [0x02] = 'PORTRAIT', [0x03] = 'FORTE SATURATION', [0x04] = 'ADOBE RGB',
    [0x05] = 'FAIBLE SATURATION', [0x06] = 'CM SET 1', [0x07] = 'CM SET 2', [0x21] = 'UTILISATEUR 1',
    [0x22] = 'UTILISATEUR 2', [0x23] = 'UTILISATEUR 3', [0x41] = 'PC 1', [0x42] = 'PC 2', [0x43] = 'PC 3',
    [0x81] = 'STANDARD', [0x82] = 'PORTRAIT', [0x83] = 'PAYSAGE', [0x84] = 'NEUTRE', [0x85] = 'FIDÈLE',
    [0x86] = 'MONOCHROME', [0x87] = 'AUTO', [0x88] = 'DÉTAIL FIN',
}
-- Sharpness (0 to 7) of the styles that were seen at their defaults in real files.
local sharpnessDefault = { [0x81] = 3, [0x82] = 2, [0x83] = 4 }
local wb = {
    [0] = 'AUTO', [1] = 'JOUR', [2] = 'NUAGEUX', [3] = 'TUNGSTÈNE', [4] = 'FLUO', [5] = 'FLASH',
    [6] = 'PERSO', [7] = 'N&B', [8] = 'OMBRE', [10] = 'PC 1', [11] = 'PC 2', [12] = 'PC 3',
    [14] = 'FLUO JOUR', [15] = 'PERSO 1', [16] = 'PERSO 2', [17] = 'SOUS-MARIN', [18] = 'PERSO 3',
    [19] = 'PERSO 4', [20] = 'PC 4', [21] = 'PC 5', [23] = 'AUTO AMBIANCE',
}
local exposures = {
    [1] = 'Programme', [2] = 'Priorité vitesse', [3] = 'Priorité ouverture', [4] = 'Manuel',
    [5] = 'Profondeur de champ', [7] = 'Pose B', [8] = 'Priorité flexible',
}
-- Shown when the exposure mode is "easy": the scene or full-auto mode of the mode dial.
local easy = {
    [0] = 'Auto', [1] = 'Manuel', [2] = 'Paysage', [3] = 'Vitesse rapide', [4] = 'Vitesse lente',
    [5] = 'Nuit', [6] = 'Niveaux de gris', [7] = 'Sépia', [8] = 'Portrait', [9] = 'Sport', [10] = 'Macro',
    [11] = 'Noir et blanc', [13] = 'Vivid', [14] = 'Neutre', [15] = 'Flash désactivé',
    [16] = 'Pose longue', [36] = 'Facile', [38] = 'Auto créatif', [57] = 'Monochrome',
    [59] = 'Auto intelligent', [61] = 'Peau lisse', [68] = 'Gastronomie',
}
local qualities = { [1] = 'économique', [2] = 'normale', [3] = 'fine', [4] = 'RAW', [5] = 'superfine', [7] = 'CRAW' }
local tones = { [1] = 'manuelle', [2] = 'personnalisée' }
local adjustments = { { 13, 'Contraste' }, { 14, 'Saturation' }, { 42, 'Ton de couleur' } }
local notAvailable = 32767

local function signed(n)
    if type(n) == 'number' and n >= 32768 then return n - 65536 end
    return n
end
local function number(n)
    if n > 0 then return '+' .. tostring(n) end
    return (tostring(n):gsub('^-', '−'))
end
-- ExifTool counts block indexes from the size word, Lua arrays start at 1.
local function field(tags, tag, index)
    local block = tags[tag]
    if type(block) ~= 'table' then return nil end
    return signed(block[index + 1])
end

function M.describe(data)
    local t = data.tags
    local first, second, details = {}, {}, {}
    local style = field(t, 0xa0, 10)
    if style ~= nil and style ~= 0 and style ~= 255 and style ~= -1 then
        first[#first + 1] = styles[style] or 'STYLE ?'
    end
    local balance, kelvin = field(t, 0x4, 7), field(t, 0xa0, 9)
    local white = wb[balance] or '?'
    if balance == 9 then white = (kelvin and kelvin > 0) and (tostring(kelvin) .. ' K') or 'KELVIN' end
    first[#first + 1] = 'WB ' .. white

    local exposure, scene = field(t, 0x1, 20), field(t, 0x1, 11)
    local mode, code
    if exposure ~= nil and exposure ~= 0 then
        mode, code = exposures[exposure], exposure
    elseif scene ~= nil then
        mode, code = easy[scene], scene
    end
    if code ~= nil then second[#second + 1] = mode or 'Mode ?' end
    if code ~= nil and not mode then details[#details + 1] = 'Mode de prise de vue : code ' .. tostring(code) end

    local values = {}
    for _, item in ipairs(adjustments) do
        local value = field(t, 0x1, item[1])
        if type(value) == 'number' and value ~= notAvailable then
            values[#values + 1] = item[2] .. ' ' .. number(value)
            if value ~= 0 then second[#second + 1] = values[#values] end
        end
    end
    local sharpness = field(t, 0xa0, 2)
    if type(sharpness) == 'number' and sharpness >= 0 then
        values[#values + 1] = 'Netteté ' .. tostring(sharpness)
        local normal = sharpnessDefault[style]
        if normal and sharpness ~= normal then
            second[#second + 1] = 'Netteté ' .. tostring(sharpness) .. ' (' .. tostring(normal) .. ' par défaut)'
        end
    end
    local curve = field(t, 0xa0, 1)
    if curve ~= nil and curve ~= 0 then second[#second + 1] = 'Courbe de tons ' .. (tones[curve] or '?') end
    local amber, green = field(t, 0xa0, 12), field(t, 0xa0, 13)
    if type(amber) == 'number' and type(green) == 'number' and (amber ~= 0 or green ~= 0) then
        second[#second + 1] = 'WB A/B ' .. number(amber) .. ' / G/M ' .. number(green)
    end

    if style == 0x87 then details[#details + 1] = 'Style Auto : l’appareil choisit les réglages de l’image.' end
    if #values > 0 then details[#details + 1] = table.concat(values, ' · ') end
    local quality = field(t, 0x1, 3)
    if quality ~= nil and quality > 0 then details[#details + 1] = 'Qualité ' .. (qualities[quality] or '?') end
    return {
        first = table.concat(first, ' · '), second = table.concat(second, ' · '),
        details = table.concat(details, '\n'),
    }
end

return M
