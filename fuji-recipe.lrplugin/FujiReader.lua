-- Read-only JPEG/RAF reader, Lua 5.1. Needs no Lightroom API besides locating ExifReader.lua.
-- Tag definitions: https://exiftool.sourceforge.net/TagNames/FujiFilm.html
local LrPathUtils = import 'LrPathUtils'
local Exif = dofile(LrPathUtils.child(_PLUGIN.path, 'ExifReader.lua'))
local M = {}
local missing = 'EXIF Fuji absents de ce fichier.'

function M.parseExif(data)
    local info = Exif.header(data)
    if not info.make:upper():find('FUJIFILM', 1, true) then
        return nil, 'not_fuji', 'Cette photo ne provient pas d’un boîtier Fujifilm.'
    end
    local note = Exif.makerNote(info)
    if not note or note:sub(1, 8) ~= 'FUJIFILM' then
        return nil, 'missing_notes', 'Métadonnées constructeur Fuji absentes.'
    end
    -- Fuji offsets count from the start of the maker note, which is always little-endian.
    local tags = Exif.directory(note, Exif.integer(note, 9, 4, true), true)
    Exif.validateTags(tags, {
        0x1001, 0x1002, 0x1003, 0x1005, 0x100e, 0x100f, 0x1040, 0x1041,
        0x1047, 0x1048, 0x104c, 0x104e, 0x1400, 0x1401, 0x1402, 0x1403,
        0x140b, 0x1443, 0x1444, 0x1445,
    }, { [0x100a] = 2 })
    return { model = info.model or 'Fujifilm', tags = tags }
end

local function readJpeg(file, length)
    return Exif.readJpeg(file, 0, length, M.parseExif, missing)
end

-- A RAF holds a full JPEG preview after a 100-byte header; it is the only part read.
local function readRaf(file, length)
    file:seek('set', 0)
    local header = file:read(100) or ''
    if header:sub(1, 16) ~= 'FUJIFILMCCD-RAW ' then error('Signature RAF invalide') end
    local first = Exif.integer(header, 85, 4, false)
    local size = Exif.integer(header, 89, 4, false)
    if first < 100 or size < 4 or first + size > length then error('Aperçu RAF invalide') end
    return Exif.readJpeg(file, first, first + size, M.parseExif, missing)
end

function M.read(path)
    return Exif.read(path, { jpg = readJpeg, jpeg = readJpeg, raf = readRaf },
        'POC : seuls les fichiers JPEG et RAF sont pris en charge.')
end

function M.readWithCompanion(path)
    local data, code, message = M.read(path)
    if data then return data end
    if code == 'missing_notes' and path:lower():match('%.jpe?g$') then
        local base = path:gsub('%.[^%.\\/]+$', '')
        for _, ext in ipairs({ '.RAF', '.raf' }) do
            local companion = M.read(base .. ext)
            if companion then companion.fromCompanion = true; return companion end
        end
    end
    return nil, code, message
end

return M
