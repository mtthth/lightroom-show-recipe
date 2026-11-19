-- Read-only JPEG reader of the standard Exif settings that name a shooting mode, Lua 5.1.
-- For brands without a maker-note reader; HEIC and RAW are not decoded.
local LrPathUtils = import 'LrPathUtils'
local Exif = dofile(LrPathUtils.child(_PLUGIN.path, 'ExifReader.lua'))
local M = {}

-- Exif 2.3: ExposureProgram, CustomRendered, SceneCaptureType and WhiteBalance.
function M.parseExif(data)
    local info = Exif.header(data)
    local exif = Exif.exifTags(info)
    if not exif then return nil, 'missing_notes', 'Métadonnées EXIF de réglages absentes.' end
    Exif.validateTags(exif, { 0x8822, 0xa401, 0xa406, 0xa403 })
    return {
        make = info.make, model = info.model,
        tags = { program = exif[0x8822], rendered = exif[0xa401], scene = exif[0xa406], balance = exif[0xa403] },
    }
end

local function readJpeg(file, length)
    return Exif.readJpeg(file, 0, length, M.parseExif, 'EXIF absents de ce fichier.')
end

function M.read(path)
    return Exif.read(path, { jpg = readJpeg, jpeg = readJpeg },
        'POC : seuls les fichiers JPEG sont pris en charge pour le mode de prise de vue.')
end

return M
