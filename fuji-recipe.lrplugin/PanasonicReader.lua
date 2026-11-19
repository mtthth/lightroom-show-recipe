-- Read-only Panasonic JPEG reader, Lua 5.1; RW2 is not decoded yet.
-- Tag definitions: https://exiftool.org/TagNames/Panasonic.html
local LrPathUtils = import 'LrPathUtils'
local Exif = dofile(LrPathUtils.child(_PLUGIN.path, 'ExifReader.lua'))
local M = {}

-- The maker note starts with "Panasonic\0\0\0"; its offsets count from the TIFF header.
function M.parseExif(data)
    local info = Exif.header(data)
    if not info.make:upper():find('PANASONIC', 1, true) then
        return nil, 'not_panasonic', 'Cette photo ne provient pas d’un boîtier Panasonic.'
    end
    local note, position = Exif.makerNote(info)
    if not note or note:sub(1, 9) ~= 'Panasonic' then
        return nil, 'missing_notes', 'Métadonnées constructeur Panasonic absentes.'
    end
    local tags = Exif.directory(data, position + 12, info.little)
    Exif.validateTags(tags, {
        0x03, 0x1f, 0x28, 0x2d, 0x39, 0x40, 0x41, 0x42, 0x49, 0x5d, 0x70, 0x79, 0x89,
    })
    return { model = info.model or 'Panasonic', tags = tags }
end

local function readJpeg(file, length)
    return Exif.readJpeg(file, 0, length, M.parseExif, 'EXIF Panasonic absents de ce fichier.')
end

function M.read(path)
    return Exif.read(path, { jpg = readJpeg, jpeg = readJpeg },
        'POC : seuls les fichiers JPEG Panasonic sont pris en charge.')
end

return M
