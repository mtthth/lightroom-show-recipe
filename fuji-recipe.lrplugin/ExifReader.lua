-- Read-only EXIF/TIFF primitives shared by the maker-note readers, Lua 5.1.
-- No Lightroom or external dependency.
local M = {}

local function integer(data, pos, size, little, signed)
    if pos < 1 or pos + size - 1 > #data then error('Métadonnées tronquées') end
    local n = 0
    for i = 0, size - 1 do
        local index = little and (pos + size - 1 - i) or (pos + i)
        n = n * 256 + data:byte(index)
    end
    if signed and n >= 2 ^ (size * 8 - 1) then n = n - 2 ^ (size * 8) end
    return n
end
M.integer = integer

local sizes = { [1] = 1, [2] = 1, [3] = 2, [4] = 4, [7] = 1, [9] = 4 }

-- IFD offsets are zero-based relative to data, Lua string indices are one-based.
-- The second result gives the zero-based position of every value.
function M.directory(data, offset, little)
    local count = integer(data, offset + 1, 2, little)
    if count > 1024 or offset + 2 + count * 12 > #data then
        error('Répertoire de métadonnées invalide')
    end
    local result, positions = {}, {}
    for i = 0, count - 1 do
        local p = offset + 3 + i * 12
        local tag = integer(data, p, 2, little)
        local kind = integer(data, p + 2, 2, little)
        local length = integer(data, p + 4, 4, little)
        local size = sizes[kind]
        if size and length > 0 then
            local bytes = size * length
            local valuePos = bytes <= 4 and (p + 8) or
                (integer(data, p + 8, 4, little) + 1)
            if bytes > #data or valuePos < 1 or valuePos + bytes - 1 > #data then
                error('Valeur de métadonnées hors limites')
            end
            positions[tag] = valuePos - 1
            if kind == 2 or kind == 7 then
                result[tag] = data:sub(valuePos, valuePos + bytes - 1)
                if kind == 2 then result[tag] = result[tag]:gsub('%z+$', '') end
            elseif length <= 256 then -- Canon's settings blocks hold 30 to 100 values
                local values = {}
                for j = 0, length - 1 do
                    values[j + 1] = integer(data, valuePos + j * size, size, little, kind == 9)
                end
                result[tag] = length == 1 and values[1] or values
            end
        end
    end
    return result, positions
end

-- Validate only the settings consumed by a reader. Missing/unknown tags stay allowed;
-- a present setting must have the scalar or numeric-array shape expected by its formatter.
function M.validateTags(tags, scalars, arrays)
    local function invalid(tag)
        error(string.format('Type de métadonnée invalide (balise 0x%04x)', tag))
    end
    for _, tag in ipairs(scalars or {}) do
        if tags[tag] ~= nil and type(tags[tag]) ~= 'number' then invalid(tag) end
    end
    for tag, count in pairs(arrays or {}) do
        local value = tags[tag]
        if value ~= nil then
            if type(value) ~= 'table' or (count > 0 and #value ~= count) then invalid(tag) end
            for _, item in ipairs(value) do
                if type(item) ~= 'number' then invalid(tag) end
            end
        end
    end
    return tags
end

-- TIFF header and IFD0: make, model and the root directory. Raises on a damaged header.
function M.header(data)
    local endian = data:sub(1, 2)
    if endian ~= 'II' and endian ~= 'MM' then error('En-tête TIFF invalide') end
    local little = endian == 'II'
    if integer(data, 3, 2, little) ~= 42 then error('Signature TIFF invalide') end
    local root = M.directory(data, integer(data, 5, 4, little), little)
    return {
        make = type(root[0x010f]) == 'string' and root[0x010f] or '',
        model = root[0x0110], root = root, little = little, tiff = data,
    }
end

-- The Exif IFD with the zero-based position of each value, or nil when the file has none.
function M.exifTags(info)
    local pointer = info.root[0x8769]
    if type(pointer) ~= 'number' then return nil end
    return M.directory(info.tiff, pointer, info.little)
end

-- The maker note bytes and their zero-based position in the TIFF data, or nil when absent.
function M.makerNote(info)
    local exif, positions = M.exifTags(info)
    if not exif or type(exif[0x927c]) ~= 'string' then return nil end
    return exif[0x927c], positions[0x927c]
end

-- Walks the JPEG segments between first and limit and hands the first Exif block to parse.
function M.readJpeg(file, first, limit, parse, missing)
    file:seek('set', first)
    if file:read(2) ~= '\255\216' then error('Signature JPEG invalide') end
    for _ = 1, 1024 do
        if file:seek() + 2 > limit then break end
        if file:read(1) ~= '\255' then error('Segment JPEG invalide') end
        local marker = file:read(1)
        while marker == '\255' do marker = file:read(1) end
        if not marker then error('JPEG tronqué') end
        local code = marker:byte()
        if code == 0xda or code == 0xd9 then break end -- never decode pixels
        if code ~= 0x01 and not (code >= 0xd0 and code <= 0xd7) then
            local length = file:read(2) or ''
            local size = integer(length, 1, 2, false) - 2
            if size < 0 or file:seek() + size > limit then error('Segment JPEG tronqué') end
            if code == 0xe1 then
                local segment = file:read(size) or ''
                if #segment ~= size then error('Segment EXIF tronqué') end
                if segment:sub(1, 6) == 'Exif\0\0' then
                    return parse(segment:sub(7))
                end
            else
                file:seek('cur', size)
            end
        end
    end
    return nil, 'missing_notes', missing
end

-- Opens path and runs the handler registered for its extension, called as handler(file, length).
-- Results are (data, code, message): a nil data comes with a code and a message to show.
function M.read(path, handlers, unsupported)
    local ext = path:match('%.([^%.\\/]+)$')
    ext = ext and ext:lower()
    local handler = handlers[ext]
    if not handler then return nil, 'unsupported', unsupported end
    local file = io.open(path, 'rb')
    if not file then return nil, 'unavailable', 'Fichier original inaccessible.' end
    local ok, value, code, message = pcall(function() return handler(file, file:seek('end')) end)
    file:close()
    if not ok then return nil, 'invalid', tostring(value) end
    if value then value.sourcePath = path end
    return value, code, message
end

return M
