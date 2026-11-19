-- Read-only Canon JPEG reader, Lua 5.1; CR2/CR3 are not decoded yet.
-- Tag definitions: https://exiftool.org/TagNames/Canon.html
local LrPathUtils = import 'LrPathUtils'
local Exif = dofile(LrPathUtils.child(_PLUGIN.path, 'ExifReader.lua'))
local M = {}

-- The maker note is a plain IFD without header; its offsets count from the TIFF header.
function M.parseExif(data)
    local info = Exif.header(data)
    if not info.make:upper():find('CANON', 1, true) then
        return nil, 'not_canon', 'Cette photo ne provient pas d’un boîtier Canon.'
    end
    local note, position = Exif.makerNote(info)
    if not note then return nil, 'missing_notes', 'Métadonnées constructeur Canon absentes.' end
    -- A re-saved JPEG can keep a maker note whose address no longer points at it.
    local ok, tags = pcall(Exif.directory, data, position, info.little)
    if not ok then
        return nil, 'invalid_notes', 'Métadonnées constructeur Canon illisibles : adresse de la MakerNote incohérente.'
    end
    Exif.validateTags(tags, nil, { [0x1] = 0, [0x4] = 0, [0xa0] = 0 })
    return { model = info.model or 'Canon', tags = tags }
end

local function readJpeg(file, length)
    return Exif.readJpeg(file, 0, length, M.parseExif, 'EXIF Canon absents de ce fichier.')
end

function M.read(path)
    return Exif.read(path, { jpg = readJpeg, jpeg = readJpeg },
        'POC : seuls les fichiers JPEG Canon sont pris en charge.')
end

return M
