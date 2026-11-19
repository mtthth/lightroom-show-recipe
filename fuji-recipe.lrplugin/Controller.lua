local LrApplication = import 'LrApplication'
local LrDate = import 'LrDate'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'
local Reader = dofile(LrPathUtils.child(_PLUGIN.path, 'FujiReader.lua'))
local Format = dofile(LrPathUtils.child(_PLUGIN.path, 'FujiFormat.lua'))
local RecipeMatch = dofile(LrPathUtils.child(_PLUGIN.path, 'RecipeMatch.lua'))
local RecipeBook = dofile(LrPathUtils.child(_PLUGIN.path, 'RecipeBook.lua'))
local PanasonicReader = dofile(LrPathUtils.child(_PLUGIN.path, 'PanasonicReader.lua'))
local PanasonicFormat = dofile(LrPathUtils.child(_PLUGIN.path, 'PanasonicFormat.lua'))
local CanonReader = dofile(LrPathUtils.child(_PLUGIN.path, 'CanonReader.lua'))
local CanonFormat = dofile(LrPathUtils.child(_PLUGIN.path, 'CanonFormat.lua'))
local ModeReader = dofile(LrPathUtils.child(_PLUGIN.path, 'ModeReader.lua'))
local ModeFormat = dofile(LrPathUtils.child(_PLUGIN.path, 'ModeFormat.lua'))
local CameraInfo = dofile(LrPathUtils.child(_PLUGIN.path, 'CameraInfo.lua'))
-- Brands read from their MakerNotes, keyed by CameraInfo's brand; Fuji has its own recipe path.
local makerNotes = {
    panasonic = { label = 'Panasonic', read = PanasonicReader.read, describe = PanasonicFormat.describe },
    canon = { label = 'Canon', read = CanonReader.read, describe = CanonFormat.describe },
}
-- Brands without a maker-note reader whose standard Exif settings name a shooting mode.
local modeBrands = { apple = { label = 'Apple' }, ricoh = { label = 'Ricoh' } }
-- Fields of MetadataDefinition.lua.
local fieldIds = { 'recipe', 'settings', 'details', 'note' }
local retryDelay = 5 -- Do not repeatedly open an offline original on every 350 ms tick.
local M = {}

local function readerLabel(camera)
    return (makerNotes[camera.brand] or modeBrands[camera.brand] or { label = 'Fuji' }).label
end

-- The texts of the settings read in the file, for the Metadata panel;
-- nil when the file gave none.
local function settingsText(entry)
    if not entry.data then return nil end
    local reader = makerNotes[entry.camera.brand]
    if reader then
        local text = reader.describe(entry.data)
        text.recipe, text.recipeDetail = '', ''
        return text
    end
    local text = Format.describe(entry.data)
    if entry.match then
        text.recipe, text.recipeDetail = Format.recipe(entry.match)
    else
        text.recipe, text.recipeDetail = '', ''
    end
    return text
end

function M.readEntry(photo, path)
    local camera = CameraInfo.describe(photo)
    if not camera then return { known = false } end
    local entry = { known = true, camera = camera }
    -- Reading, matching and formatting are one non-yielding operation. A damaged setting
    -- must fail only this photo, never the tracking task or the rest of a selection.
    local ok, message = pcall(function()
        if camera.fuji then
            entry.data, entry.code, entry.message = Reader.readWithCompanion(path)
            -- A raw file is not rendered with the camera settings: they describe the shot,
            -- but no recipe applies to it. Only the camera's JPEG carries one.
            entry.raw = type(path) == 'string' and path:lower():match('%.raf$') ~= nil
            if entry.data and not entry.raw then
                entry.match = RecipeMatch.find(RecipeBook.current().recipes, Format.settings(entry.data))
            end
        elseif makerNotes[camera.brand] then
            entry.data, entry.code, entry.message = makerNotes[camera.brand].read(path)
        elseif modeBrands[camera.brand] then
            local info
            info, entry.code, entry.message = ModeReader.read(path)
            if info then entry.mode = ModeFormat.describe(info, camera.brand) end
            entry.look = ModeFormat.look(info, camera.brand)
            -- HEIC and RAW are not read: that is no reason to show an error.
            if entry.code == 'unsupported' then entry.message = nil end
        end
        entry.text = settingsText(entry)
    end)
    if not ok then
        return { known = true, camera = camera, code = 'invalid',
            message = 'Métadonnées de réglages illisibles : ' .. tostring(message),
            look = ModeFormat.look(nil, camera.brand) }
    end
    return entry
end

local function joined(...)
    local kept = {}
    for i = 1, select('#', ...) do
        local part = select(i, ...)
        if part and part ~= '' then kept[#kept + 1] = part end
    end
    return table.concat(kept, '\n')
end

-- Values of the Metadata panel fields, or nil to leave them as they are: no identified camera,
-- or an original that cannot be opened (offline) and may have been read before.
function M.panelFields(entry)
    if not (entry and entry.known) or entry.code == 'unavailable' then return nil end
    local text = entry.text
    if text then
        return {
            recipe = text.recipe, settings = joined(text.first, text.second),
            details = joined(text.recipeDetail, text.details),
            note = entry.raw and 'Fichier RAW : pas de recette, elle ne s’applique qu’au JPEG du boîtier.'
                or entry.data.fromCompanion and 'Réglages lus dans le RAF associé.' or '',
        }
    end
    return {
        recipe = '', settings = joined(entry.look, entry.mode), details = '',
        note = entry.message and ('Réglages ' .. readerLabel(entry.camera) .. ' : ' .. entry.message) or '',
    }
end

-- Writes the panel fields that differ from the catalog, for a list of { photo = , fields = }.
-- Plug-in fields only, outside the undo history. False when the catalog stayed busy.
function M.writeFields(catalog, items)
    local changes = {}
    for _, item in ipairs(items) do
        for _, id in ipairs(fieldIds) do
            local value = item.fields[id] or ''
            if (item.photo:getPropertyForPlugin(_PLUGIN, id) or '') ~= value then
                changes[#changes + 1] = { photo = item.photo, id = id, value = value ~= '' and value or nil }
            end
        end
    end
    if #changes == 0 then return true end
    return catalog:withPrivateWriteAccessDo(function()
        for _, change in ipairs(changes) do
            change.photo:setPropertyForPlugin(_PLUGIN, change.id, change.value)
        end
    end, { timeout = 2 }) ~= 'aborted'
end

function M.start()
    local existing = _G.fujiRecipeController
    if existing and not existing.stopped then return existing end
    local state = { stopped = false, force = true }
    _G.fujiRecipeController = state
    state.stop = function() state.stopped = true end

    LrFunctionContext.postAsyncTaskWithContext('Suivi de la photo active', function(context)
        LrDialogs.attachErrorDialogToFunctionContext(context)
        context:addCleanupHandler(function() state.stop() end)
        local catalog = LrApplication.activeCatalog()
        local cache, cacheSize, lastPath, currentEntry, syncedKey = {}, 0, nil, nil, nil

        -- Menu commands load Controller.lua again: publish fresh readings through the
        -- running state so its cache and the panel use the same entry.
        state.cacheEntry = function(path, entry)
            if cacheSize >= 64 and not cache[path] then cache, cacheSize = {}, 0 end
            if not cache[path] then cacheSize = cacheSize + 1 end
            entry.retryAt = entry.code == 'unavailable' and (LrDate.currentTime() + retryDelay) or nil
            cache[path] = entry
            -- Also refresh the active photo if a large batch evicts its entry before the next tick.
            if path == lastPath and entry ~= currentEntry then lastPath = nil end
        end

        local function tick()
            local photo = catalog:getTargetPhoto()
            local path = photo and photo:getRawMetadata('path')
            local now = LrDate.currentTime()
            local retry = currentEntry and currentEntry.retryAt and now >= currentEntry.retryAt
            if state.force or path ~= lastPath or retry then
                local force = state.force
                state.force, lastPath = false, path
                syncedKey = nil -- A fresh reading can change fields without changing the photo id.
                currentEntry = nil
                -- An edited or newly chosen recipe file makes every cached match out of date.
                local book = RecipeBook.current()
                if book ~= state.book then cache, cacheSize, state.book = {}, 0, book end
                if path then
                    currentEntry = not force and cache[path]
                    if currentEntry and currentEntry.retryAt and now >= currentEntry.retryAt then
                        currentEntry = nil
                    end
                    if not currentEntry then
                        currentEntry = M.readEntry(photo, path)
                        state.cacheEntry(path, currentEntry)
                    end
                end
            end
            -- Virtual copies share their master's path: the panel follows the photo itself.
            -- A busy catalog leaves syncedKey behind, so the next tick writes again.
            local key = photo and (photo.localIdentifier or path)
            if key ~= syncedKey then
                local fields = M.panelFields(currentEntry)
                if not fields or M.writeFields(catalog, { { photo = photo, fields = fields } }) then
                    syncedKey = key
                end
            end
        end

        while not state.stopped do
            tick()
            LrTasks.sleep(0.35)
        end
    end)
    return state
end

-- Menu command: fills the panel fields of the selected photos (of the filmstrip when none is
-- selected), so that they can be searched and filtered without visiting each photo.
function M.fillSelection()
    LrFunctionContext.postAsyncTaskWithContext('Panneau Métadonnées de la sélection', function(context)
        LrDialogs.attachErrorDialogToFunctionContext(context)
        local catalog = LrApplication.activeCatalog()
        local photos = catalog:getTargetPhotos()
        local progress = LrProgressScope { title = 'Lecture des réglages du boîtier', functionContext = context }
        local batch, filled, skipped, busy = {}, 0, 0, 0
        local function flush()
            if #batch == 0 then return end
            if M.writeFields(catalog, batch) then filled = filled + #batch else busy = busy + #batch end
            batch = {}
        end
        for i, photo in ipairs(photos) do
            if progress:isCanceled() then break end
            local path = photo:getRawMetadata('path')
            local entry = M.readEntry(photo, path)
            local state = _G.fujiRecipeController
            if state and not state.stopped and state.cacheEntry then state.cacheEntry(path, entry) end
            local fields = M.panelFields(entry)
            if fields then batch[#batch + 1] = { photo = photo, fields = fields } else skipped = skipped + 1 end
            if #batch >= 50 then flush() end
            progress:setPortionComplete(i, #photos)
        end
        flush()
        progress:done()
        local function plural(n) return n > 1 and 's' or '' end
        local lines = { filled .. ' photo' .. plural(filled) .. ' à jour dans le panneau Métadonnées.' }
        if skipped > 0 then
            lines[#lines + 1] = skipped .. ' photo' .. plural(skipped) ..
                ' sans appareil identifié ou à l’original inaccessible.'
        end
        if busy > 0 then
            lines[#lines + 1] = busy .. ' photo' .. plural(busy) .. ' non enregistrée' .. plural(busy) ..
                ' : catalogue occupé, relancer la commande.'
        end
        LrDialogs.message('Panneau Métadonnées', table.concat(lines, '\n'), 'info')
    end)
end

return M
