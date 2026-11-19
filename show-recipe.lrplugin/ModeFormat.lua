-- Shooting mode from standard Exif tags, for the brands that have no maker-note reader.
local M = {}
-- CustomRendered: iPhones set it for HDR, panoramas and portraits.
local rendered = {
    [2] = 'HDR', [3] = 'HDR', [4] = 'Original HDR', [6] = 'Panorama', [7] = 'Portrait HDR', [8] = 'Portrait',
}
local scenes = { [1] = 'Paysage', [2] = 'Portrait', [3] = 'Nuit' }
-- ExposureProgram: the program of a compact is a mode of its dial, unlike a phone's constant "normal".
local programs = {
    [1] = 'Manuel', [2] = 'Programme', [3] = 'Priorité ouverture', [4] = 'Priorité vitesse',
    [5] = 'Créatif', [6] = 'Action', [7] = 'Portrait', [8] = 'Paysage',
}

-- The mode as text, or '' when the file does not name one; nothing is guessed.
function M.describe(data, brand)
    local t = data.tags
    if brand == 'apple' then return rendered[t.rendered] or scenes[t.scene] or '' end
    if brand == 'ricoh' then return programs[t.program] or '' end
    return ''
end

-- The settings line of the brands that have one: the Exif white balance, auto or manual.
-- A phone's is always auto, so only the Ricoh shows it. The Ricoh always has this line, "WB ?"
-- when the file does not say (or cannot be read), so its layout does not change from photo to photo.
local balances = { [0] = 'AUTO', [1] = 'MANUEL' }
function M.look(data, brand)
    if brand ~= 'ricoh' then return '' end
    return 'WB ' .. (data and balances[data.tags.balance] or '?')
end

return M
