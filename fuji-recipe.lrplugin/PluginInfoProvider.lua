-- Plug-in Manager section: which recipe file is used, how many recipes it gives, and the
-- lines left out. The file can be replaced by the user's own CSV, starting from a copy of
-- the recipes shipped with the plugin.
local LrDialogs = import 'LrDialogs'
local LrFileUtils = import 'LrFileUtils'
local LrPathUtils = import 'LrPathUtils'
local LrPrefs = import 'LrPrefs'
local LrView = import 'LrView'
local RecipeBook = dofile(LrPathUtils.child(_PLUGIN.path, 'RecipeBook.lua'))

local function plural(n, word) return n .. ' ' .. word .. (n > 1 and 's' or '') end

local function refresh(props)
    local book = RecipeBook.current()
    props.recipeFile = book.path == RecipeBook.defaultPath()
        and 'Recettes fournies avec le module (recipes.csv)' or book.path
    local status = plural(#book.recipes, 'recette') .. ' chargée' .. (#book.recipes > 1 and 's' or '') .. '.'
    if #book.errors > 0 then
        status = status .. '\n' .. plural(#book.errors, 'ligne') .. ' ignorée' ..
            (#book.errors > 1 and 's' or '') .. ' :\n' .. table.concat(book.errors, '\n')
    end
    props.recipeStatus = status
end

return {
    sectionsForTopOfDialog = function(f, props)
        local prefs = LrPrefs.prefsForPlugin()
        local bind, share = LrView.bind, LrView.share
        refresh(props)
        return { {
            title = 'Recettes Fuji',
            f:row {
                f:static_text { title = 'Fichier :', width = share 'recipeLabel' },
                f:static_text { title = bind 'recipeFile', fill_horizontal = 1, truncation = 'middle' },
            },
            f:row {
                f:static_text { title = '', width = share 'recipeLabel' },
                f:static_text { title = bind 'recipeStatus', fill_horizontal = 1, height_in_lines = 5 },
            },
            f:row {
                f:static_text { title = '', width = share 'recipeLabel' },
                f:push_button { title = 'Choisir un fichier CSV…', action = function()
                    local files = LrDialogs.runOpenPanel {
                        title = 'Fichier de recettes', canChooseFiles = true, canChooseDirectories = false,
                        allowsMultipleSelection = false, fileTypes = 'csv',
                    }
                    if files and files[1] then
                        prefs.recipesPath = files[1]
                        refresh(props)
                    end
                end },
                f:push_button { title = 'Recettes fournies', action = function()
                    prefs.recipesPath = nil
                    refresh(props)
                end },
                f:push_button { title = 'Copier les recettes fournies…', action = function()
                    local target = LrDialogs.runSavePanel {
                        title = 'Copie modifiable des recettes', requiredFileType = 'csv',
                        initialFileName = 'mes-recettes.csv',
                    }
                    if not target then return end
                    if LrFileUtils.exists(target) then LrFileUtils.moveToTrash(target) end
                    local ok = LrFileUtils.copy(RecipeBook.defaultPath(), target)
                    if not ok then
                        LrDialogs.message('Recettes Fuji', 'Copie impossible vers ' .. target, 'critical')
                        return
                    end
                    prefs.recipesPath = target
                    refresh(props)
                end },
            },
            f:row {
                f:static_text { title = '', width = share 'recipeLabel' },
                f:static_text {
                    title = 'Une modification du fichier vaut pour les photos lues ensuite. Pour recalculer '
                        .. 'les photos déjà lues : Bibliothèque → Module externe - Extras → Renseigner le '
                        .. 'panneau Métadonnées pour la sélection…',
                    fill_horizontal = 1, height_in_lines = 3, width_in_chars = 60, size = 'small',
                },
            },
        } }
    end,
}
