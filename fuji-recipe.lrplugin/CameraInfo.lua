-- Camera make and model, and the brand whose settings can be read. Read-only and SDK independent.
local M = {}
local unknown = {
    ['unknown'] = true, ['unknown camera'] = true, ['inconnu'] = true,
    ['inconnue'] = true, ['appareil inconnu'] = true, ['appareil photo inconnu'] = true,
    ['n/a'] = true, ['none'] = true, ['null'] = true, ['undefined'] = true,
    ['-'] = true, ['?'] = true, ['0'] = true,
}

function M.clean(value)
    if type(value) ~= 'string' then return '' end
    local text = value:gsub('^%s+', ''):gsub('%s+$', '')
    local key = text:lower():gsub('^%(', ''):gsub('%)$', '')
    if unknown[key] then return '' end
    return text
end

-- nil when the photo names no camera model: there is nothing to read.
function M.describe(photo)
    local model = M.clean(photo:getFormattedMetadata('cameraModel'))
    if model == '' then return nil end
    local make = M.clean(photo:getFormattedMetadata('cameraMake'))
    -- Brands whose settings are read, from the make or, when it is missing, the model prefix.
    local upper = make:upper()
    local brand = (upper:find('PANASONIC', 1, true) or model:match('^DMC%-') or model:match('^DC%-')) and 'panasonic'
        or (upper:find('CANON', 1, true) or model:match('^Canon ')) and 'canon'
        or (upper:find('APPLE', 1, true) or model:match('^iPhone') or model:match('^iPad')) and 'apple'
        or (upper:find('RICOH', 1, true) or model:match('^GR ') or model:match('^Caplio')) and 'ricoh' or nil
    local fuji = upper:find('FUJI', 1, true) ~= nil
        or (make == '' and (model:match('^X%-') or model:match('^X100') or model:match('^GFX')) ~= nil)
    return { model = model, make = make, brand = brand, fuji = fuji }
end

return M
