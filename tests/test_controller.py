"""Lifecycle tests: exercise the actual controller with a cooperative Lightroom mock."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.test-deps'))
from lupa.lua51 import LuaRuntime


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().pluginPath = str(ROOT / 'fuji-recipe.lrplugin').replace('\\', '/')
        self.lua.execute('''
            jobs, prefs, recipeStamp = {}, {}, 0
            readCount, writeCount = 0, 0
            now, readOverrides = 0, {}
            -- Plug-in fields by photo id; busy makes the catalog refuse write access.
            stored, busy, writing, targets, messages = {}, false, false, {}, {}
            local nativeDofile = dofile
            dofile = function(path)
                if path:match('FujiReader.lua$') then
                    return { readWithCompanion = function(path)
                        readCount = readCount + 1
                        if readOverrides[path] then return readOverrides[path]() end
                        if path == 'missing.JPG' then return nil, 'unavailable', 'Original inaccessible' end
                        if path == 'stripped.JPG' then
                            return nil, 'missing_notes', 'Métadonnées constructeur Fuji absentes.'
                        end
                        if path == 'recipe.JPG' then
                            return { model = 'X-T5', tags = { -- Reala Everyday
                                [0x1401] = 0xb00, [0x1003] = 0x80, [0x1402] = 0, [0x140b] = 200,
                                [0x1002] = 0, [0x100a] = {0, 0}, [0x1041] = 0, [0x1040] = 0,
                                [0x1001] = 3, [0x100e] = 0x280, [0x100f] = 0, [0x1047] = 32,
                                [0x104c] = 16, [0x1048] = 32, [0x104e] = 32,
                            } }
                        end
                        return { model = 'X-T5', tags = {
                            [0x1401] = path == 'second.JPG' and 0xb00 or 0,
                            [0x1002] = 0, [0x100a] = {0, 0}, [0x1403] = 100,
                            [0x1040] = 32, [0x1041] = 16, [0x1003] = 0, [0x1001] = 0x84,
                        } }
                    end }
                end
                if path:match('PanasonicReader.lua$') then
                    return { read = function(path)
                        readCount = readCount + 1
                        if readOverrides[path] then return readOverrides[path]() end
                        if path == 'missing.JPG' then return nil, 'unavailable', 'Original inaccessible' end
                        return { model = 'DMC-GX80', tags = { -- Intelligent Auto Plus, Standard, no adjustment
                            [0x03] = 1, [0x1f] = 60, [0x89] = 1, [0x39] = 0, [0x40] = 0, [0x41] = 0,
                        } }
                    end }
                end
                if path:match('CanonReader.lua$') then
                    return { read = function(path)
                        readCount = readCount + 1
                        if readOverrides[path] then return readOverrides[path]() end
                        if path == 'missing.JPG' then return nil, 'unavailable', 'Original inaccessible' end
                        local cs, si, pi = {}, {}, {}
                        for i = 1, 49 do cs[i] = 0 end
                        for i = 1, 34 do si[i] = 0 end
                        for i = 1, 14 do pi[i] = 0 end
                        cs[12] = 9 -- sports scene (index 11), exposure mode easy (index 20)
                        pi[11], pi[3] = 0x81, 3 -- Standard style at its default sharpness
                        return { model = 'Canon EOS 500D', tags = { [0x1] = cs, [0x4] = si, [0xa0] = pi } }
                    end }
                end
                if path:match('ModeReader.lua$') then
                    return { read = function(path)
                        readCount = readCount + 1
                        if readOverrides[path] then return readOverrides[path]() end
                        if path == 'heic.JPG' then return nil, 'unsupported', 'POC : seuls les fichiers JPEG' end
                        if path == 'missing.JPG' then return nil, 'unavailable', 'Original inaccessible' end
                        return { tags = { rendered = 8, program = 3, balance = 0 } } -- Portrait; aperture priority; auto
                    end }
                end
                return nativeDofile(path)
            end
            _PLUGIN = { path = pluginPath }
            local api = {
                LrApplication = { activeCatalog = function()
                    return {
                        getTargetPhoto = function() return current end,
                        getTargetPhotos = function() return targets end,
                        withPrivateWriteAccessDo = function(self, fn, params)
                            assert(params.timeout)
                            if busy then return 'aborted' end
                            writing = true
                            fn()
                            writing, writeCount = false, writeCount + 1
                            return 'executed'
                        end,
                    }
                end },
                LrDate = { currentTime = function() return now end },
                LrFileUtils = { fileAttributes = function(path)
                    return { fileModificationDate = recipeStamp }
                end },
                LrPrefs = { prefsForPlugin = function() return prefs end },
                LrDialogs = {
                    attachErrorDialogToFunctionContext = function() end,
                    message = function(title, text) messages[#messages + 1] = text end,
                },
                LrFunctionContext = { postAsyncTaskWithContext = function(name, fn)
                    local context = { addCleanupHandler = function(self, handler) self.cleanup = handler end }
                    jobs[#jobs + 1] = coroutine.create(function()
                        fn(context)
                        if context.cleanup then context.cleanup() end
                    end)
                end },
                LrPathUtils = { child = function(a, b) return a .. '/' .. b end },
                LrProgressScope = function(args)
                    return { isCanceled = function() return false end,
                        setPortionComplete = function() end, done = function() end }
                end,
                LrTasks = { sleep = function(seconds) now = now + seconds; coroutine.yield() end },
            }
            import = function(name) return assert(api[name], name) end
            -- copy names a virtual copy: same file, its own plug-in fields.
            function makePhoto(path, make, copy)
                local id = path .. (copy or '')
                return {
                    localIdentifier = id,
                    getPropertyForPlugin = function(self, plugin, field) return stored[id] and stored[id][field] end,
                    setPropertyForPlugin = function(self, plugin, field, value)
                        assert(writing, 'plug-in field written outside a write gate')
                        assert(value == nil or value ~= '', 'empty values are cleared with nil')
                        stored[id] = stored[id] or {}
                        stored[id][field] = value
                    end,
                    getRawMetadata = function(self, key) assert(key == 'path'); return path end,
                    getFormattedMetadata = function(self, key)
                        if key == 'cameraMake' then return make end
                        if key == 'cameraModel' then
                            if modelValue then return modelValue end
                            if path == 'unknown.JPG' then return 'Unknown' end
                            if make == 'Panasonic' then return 'DMC-GX80' end
                            if make == 'Canon' then return 'Canon EOS 500D' end
                            if make == 'Apple' then return 'iPhone XR' end
                            if make == 'RICOH' then return 'GR Digital' end
                            return make == 'FUJIFILM' and 'X-T5' or 'Test camera'
                        end
                        return ''
                    end,
                }
            end
            function selectPhoto(path, make, copy)
                current = path and makePhoto(path, make, copy) or nil
            end
            function step(index)
                local job = jobs[index or #jobs]
                if coroutine.status(job) ~= 'dead' then
                    local ok, err = coroutine.resume(job)
                    assert(ok, err)
                end
            end
            controller = dofile(pluginPath .. '/Controller.lua')
        ''')
        self.g = self.lua.globals()

    def run_lua(self, code):
        self.lua.execute(code)

    def test_only_cameras_with_a_reader_are_read(self):
        self.run_lua("controller.start(); selectPhoto('unknown.JPG', 'Canon'); step()")
        self.assertEqual(self.g.readCount, 0)
        self.run_lua("selectPhoto('first.JPG', 'FUJIFILM'); step()")
        self.assertTrue(self.g.stored['first.JPG'].settings.startswith('PROVIA'))
        self.run_lua("selectPhoto('second.JPG', 'FUJIFILM'); step()")
        self.assertTrue(self.g.stored['second.JPG'].settings.startswith('REALA ACE'))
        self.run_lua("selectPhoto('sony.JPG', 'SONY'); step(); selectPhoto('unknown.JPG', 'SONY'); step()")
        self.assertIsNone(self.g.stored['sony.JPG'])
        self.run_lua("selectPhoto('first.JPG', 'FUJIFILM'); step(); selectPhoto(nil); step()")
        self.assertEqual(self.g.readCount, 2)  # cached Fuji; other brands never read

    def test_startup_tracks_once_and_restarts_after_shutdown(self):
        self.run_lua("dofile(pluginPath .. '/Startup.lua'); dofile(pluginPath .. '/Startup.lua')")
        self.assertEqual(len(self.g.jobs), 1)
        self.run_lua("selectPhoto('recipe.JPG', 'FUJIFILM'); step()")
        self.assertEqual(self.g.stored['recipe.JPG'].recipe, 'Reala Everyday')
        self.run_lua("dofile(pluginPath .. '/Shutdown.lua'); step()")
        self.assertTrue(self.g.fujiRecipeController.stopped)
        self.run_lua("dofile(pluginPath .. '/Startup.lua')")
        self.assertEqual(len(self.g.jobs), 2)

    def test_the_panel_is_filled_for_the_active_photo(self):
        self.run_lua("controller.start(); selectPhoto('recipe.JPG', 'FUJIFILM'); step()")
        fields = self.g.stored['recipe.JPG']
        self.assertEqual(fields.recipe, 'Reala Everyday')
        self.assertEqual(fields.source, 'Personnelle')
        self.assertTrue(fields.settings.startswith('REALA ACE'))
        self.assertTrue(fields.adjustments.startswith('H '))
        self.assertTrue(fields.effects.startswith('Grain '))
        self.assertTrue(fields.noise.startswith('Bruit '))
        self.assertIsNone(fields.note)
        for value in fields.values():
            self.assertNotIn('\n', value)

    def test_panel_fields_are_written_only_when_they_change(self):
        self.run_lua("controller.start(); selectPhoto('first.JPG', 'FUJIFILM'); step(); step(); step()")
        self.assertEqual(self.g.writeCount, 1)
        self.assertEqual(self.g.stored['first.JPG'].recipe, 'Recette non identifiée')
        self.run_lua("selectPhoto('second.JPG', 'FUJIFILM'); step(); selectPhoto('first.JPG', 'FUJIFILM'); step()")
        self.assertEqual(self.g.writeCount, 2)
        self.run_lua("selectPhoto('sony.JPG', 'SONY'); step(); selectPhoto('unknown.JPG', 'SONY'); step()")
        self.assertEqual(self.g.writeCount, 2)  # nothing to show for a camera without a reader
        self.assertIsNone(self.g.stored['sony.JPG'])

    def test_a_raw_file_gets_its_settings_but_no_recipe(self):
        reala = ("{ model = 'X-T5', tags = { [0x1401] = 0xb00, [0x1003] = 0x80, [0x1402] = 0, "
            "[0x140b] = 200, [0x1002] = 0, [0x100a] = {0, 0}, [0x1041] = 0, [0x1040] = 0, [0x1001] = 3, "
            "[0x100e] = 0x280, [0x100f] = 0, [0x1047] = 32, [0x104c] = 16, [0x1048] = 32, [0x104e] = 32 } }")
        for path in ['DSCF5790.RAF', 'dscf5791.raf']:
            with self.subTest(path=path):
                self.run_lua("stored['" + path + "'] = { recipe = 'Ancienne recette' }; "
                    "readOverrides['" + path + "'] = function() return " + reala + " end; "
                    "controller.start(); selectPhoto('" + path + "', 'FUJIFILM'); step()")
                fields = self.g.stored[path]
                self.assertIsNone(fields.recipe)
                self.assertTrue(fields.settings.startswith('REALA ACE'))
                self.assertTrue(fields.effects.startswith('Grain '))
                self.assertIsNone(fields.source)
                self.assertIsNone(fields.note)
        self.run_lua("selectPhoto('recipe.JPG', 'FUJIFILM'); step()")
        self.assertEqual(self.g.stored['recipe.JPG'].recipe, 'Reala Everyday')

    def test_offline_original_keeps_what_an_earlier_reading_wrote(self):
        self.run_lua("stored['missing.JPG'] = { recipe = 'Reala Everyday', settings = 'REALA ACE' }; "
            "controller.start(); selectPhoto('missing.JPG', 'FUJIFILM'); step()")
        self.assertEqual(self.g.writeCount, 0)
        self.assertEqual(self.g.stored['missing.JPG'].recipe, 'Reala Everyday')

    def test_offline_original_is_retried_without_changing_the_active_photo(self):
        self.run_lua('''
            stored['missing.JPG'] = { recipe = 'Ancienne recette' }
            readOverrides['missing.JPG'] = function()
                if not online then return nil, 'unavailable', 'Original inaccessible' end
                return { tags = { [0x1401] = 0xb00 } }
            end
            controller.start(); selectPhoto('missing.JPG', 'FUJIFILM'); step()
            online = true; now = 1; step()
        ''')
        self.assertEqual(self.g.readCount, 1)  # wait before retrying an offline disk
        self.assertEqual(self.g.stored['missing.JPG'].recipe, 'Ancienne recette')
        self.run_lua('now = 6; step()')
        self.assertEqual(self.g.readCount, 2)
        self.assertTrue(self.g.stored['missing.JPG'].settings.startswith('REALA ACE'))
        self.assertEqual(self.g.stored['missing.JPG'].recipe, 'Recette non identifiée')
        self.assertIsNone(self.g.stored['missing.JPG'].note)

    def test_expired_offline_cache_is_retried_when_revisiting_the_photo(self):
        self.run_lua('''
            readOverrides['missing.JPG'] = function()
                if not online then return nil, 'unavailable', 'Original inaccessible' end
                return { tags = { [0x1401] = 0xb00 } }
            end
            controller.start(); selectPhoto('missing.JPG', 'FUJIFILM'); step()
            selectPhoto('first.JPG', 'FUJIFILM'); step()
            online = true; now = 6; selectPhoto('missing.JPG', 'FUJIFILM'); step()
        ''')
        self.assertEqual(self.g.readCount, 3)
        self.assertTrue(self.g.stored['missing.JPG'].settings.startswith('REALA ACE'))

    def test_damaged_settings_do_not_stop_tracking_or_leak_partial_text(self):
        for make, bad_data in [
            ('FUJIFILM', "{ tags = { [0x1041] = 'abc' } }"),
            ('Canon', "{ tags = { [0x4] = { [8] = 9 }, [0xa0] = { [10] = 'abc' } } }"),
        ]:
            with self.subTest(make=make):
                path = 'bad-' + make + '.JPG'
                self.run_lua("readOverrides['" + path + "'] = function() return " + bad_data + " end; "
                    "controller.start(); selectPhoto('" + path + "', '" + make + "'); step()")
                self.assertIsNone(self.g.stored[path].recipe)
                self.assertIn('illisibles', self.g.stored[path].note)
                self.run_lua("selectPhoto('recipe.JPG', 'FUJIFILM'); step()")
                self.assertEqual(self.g.stored['recipe.JPG'].recipe, 'Reala Everyday')
                self.assertFalse(self.g.fujiRecipeController.stopped)

    def test_unreadable_settings_clear_the_fields_and_give_the_reason(self):
        self.run_lua("stored['stripped.JPG'] = { recipe = 'Reala Everyday', settings = 'REALA ACE' }; "
            "controller.start(); selectPhoto('stripped.JPG', 'FUJIFILM'); step()")
        fields = self.g.stored['stripped.JPG']
        self.assertIsNone(fields.recipe)
        self.assertIsNone(fields.settings)
        self.assertEqual(fields.note, 'Réglages Fuji : Métadonnées constructeur Fuji absentes.')

    def test_panel_fields_of_the_other_brands(self):
        self.run_lua("controller.start(); selectPhoto('gx80.JPG', 'Panasonic'); step(); "
            "selectPhoto('eos.JPG', 'Canon'); step(); selectPhoto('gr.JPG', 'RICOH'); step(); "
            "selectPhoto('phone.JPG', 'Apple'); step()")
        stored = self.g.stored
        self.assertEqual(stored['gx80.JPG'].settings, 'STANDARD · WB AUTO')
        self.assertEqual(stored['gx80.JPG'].adjustments, 'Auto intelligent +')
        self.assertIn('Contraste 0 · Saturation 0 · Netteté 0', stored['gx80.JPG'].note)
        self.assertIsNone(stored['gx80.JPG'].recipe)
        self.assertIsNone(stored['gx80.JPG'].effects)
        self.assertEqual(stored['eos.JPG'].settings, 'STANDARD · WB AUTO')
        self.assertEqual(stored['eos.JPG'].adjustments, 'Sport')
        self.assertEqual(stored['gr.JPG'].settings, 'WB AUTO')
        self.assertEqual(stored['gr.JPG'].adjustments, 'Priorité ouverture')
        self.assertIsNone(stored['phone.JPG'].settings)
        self.assertEqual(stored['phone.JPG'].adjustments, 'Portrait')

    def test_busy_catalog_is_retried_on_the_next_tick(self):
        self.run_lua("busy = true; controller.start(); selectPhoto('first.JPG', 'FUJIFILM'); step()")
        self.assertIsNone(self.g.stored['first.JPG'])
        self.run_lua('busy = false; step()')
        self.assertEqual(self.g.writeCount, 1)
        self.assertTrue(self.g.stored['first.JPG'].settings.startswith('PROVIA'))

    def test_virtual_copy_gets_its_own_fields_without_a_second_reading(self):
        self.run_lua("controller.start(); selectPhoto('first.JPG', 'FUJIFILM'); step(); "
            "selectPhoto('first.JPG', 'FUJIFILM', ' copie 1'); step()")
        self.assertEqual(self.g.readCount, 1)
        self.assertEqual(self.g.stored['first.JPG copie 1'].settings, self.g.stored['first.JPG'].settings)

    def test_menu_fills_the_selection_in_batches(self):
        self.run_lua('''
            for i = 1, 60 do targets[i] = makePhoto('photo' .. i .. '.JPG', 'FUJIFILM') end
            targets[61] = makePhoto('unknown.JPG', 'SONY')
            targets[62] = makePhoto('missing.JPG', 'FUJIFILM')
            dofile(pluginPath .. '/FillRecipes.lua')
            step()
        ''')
        self.assertEqual(self.g.writeCount, 2)  # 50 photos, then 10
        self.assertTrue(self.g.stored['photo60.JPG'].settings.startswith('PROVIA'))
        self.assertEqual(self.g.messages[1], '60 photos à jour dans le panneau Métadonnées.\n'
            '2 photos sans appareil identifié ou à l’original inaccessible.')

    def test_selection_refreshes_tracking_and_cannot_be_undone_by_its_old_cache(self):
        self.run_lua('''
            controller.start(); selectPhoto('recipe.JPG', 'FUJIFILM'); step()
            readOverrides['recipe.JPG'] = function() return { tags = { [0x1401] = 0 } } end
            targets = { current }
            dofile(pluginPath .. '/FillRecipes.lua'); step()
        ''')
        self.assertEqual(self.g.stored['recipe.JPG'].recipe, 'Recette non identifiée')
        self.run_lua('step(1)')
        self.assertEqual(self.g.readCount, 2)  # the menu's fresh reading is reused
        self.run_lua("selectPhoto('first.JPG', 'FUJIFILM'); step(1); "
            "selectPhoto('recipe.JPG', 'FUJIFILM'); step(1)")
        self.assertEqual(self.g.readCount, 3)  # first.JPG only: recipe.JPG comes from the cache
        self.assertEqual(self.g.stored['recipe.JPG'].recipe, 'Recette non identifiée')
        self.assertTrue(self.g.stored['recipe.JPG'].settings.startswith('PROVIA'))

    def test_selection_refresh_survives_cache_eviction_before_the_next_tick(self):
        self.run_lua('''
            controller.start(); selectPhoto('recipe.JPG', 'FUJIFILM'); step()
            readOverrides['recipe.JPG'] = function() return { tags = { [0x1401] = 0 } } end
            targets = { current }
            for i = 2, 70 do targets[i] = makePhoto('photo' .. i .. '.JPG', 'FUJIFILM') end
            dofile(pluginPath .. '/FillRecipes.lua'); step(); step(1)
        ''')
        self.assertEqual(self.g.stored['recipe.JPG'].recipe, 'Recette non identifiée')
        self.assertTrue(self.g.stored['recipe.JPG'].settings.startswith('PROVIA'))

    def test_selection_continues_after_a_damaged_photo(self):
        self.run_lua('''
            readOverrides['bad.JPG'] = function() return { tags = { [0x1041] = 'abc' } } end
            targets = { makePhoto('bad.JPG', 'FUJIFILM'), makePhoto('recipe.JPG', 'FUJIFILM') }
            dofile(pluginPath .. '/FillRecipes.lua'); step()
        ''')
        self.assertIn('illisibles', self.g.stored['bad.JPG'].note)
        self.assertEqual(self.g.stored['recipe.JPG'].recipe, 'Reala Everyday')

    def test_chosen_recipe_file_is_used_and_reread_when_it_changes(self):
        import tempfile
        source = (ROOT / 'fuji-recipe.lrplugin' / 'recipes.csv').read_text(encoding='utf-8')
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'mes recettes.csv'
            path.write_text(source.replace('Reala Everyday,', 'Ma Reala,'), encoding='utf-8')
            self.g.chosen = str(path).replace('\\', '/')
            self.run_lua("prefs.recipesPath = chosen; controller.start(); "
                "selectPhoto('recipe.JPG', 'FUJIFILM'); step()")
            self.assertEqual(self.g.stored['recipe.JPG'].recipe, 'Ma Reala')
            path.write_text(source.replace('Reala Everyday,', 'Reala du jour,'), encoding='utf-8')
            self.run_lua("recipeStamp = 1; selectPhoto('first.JPG', 'FUJIFILM'); step(); "
                "selectPhoto('recipe.JPG', 'FUJIFILM'); step()")
            self.assertEqual(self.g.stored['recipe.JPG'].recipe, 'Reala du jour')
            self.run_lua("prefs.recipesPath = chosen .. '.absent'; selectPhoto('second.JPG', 'FUJIFILM'); step()")
            self.assertEqual(self.g.stored['second.JPG'].recipe, 'Recette non identifiée')

    def test_tagset_lists_the_declared_fields(self):
        self.run_lua('''
            info = dofile(pluginPath .. '/Info.lua')
            definition = dofile(pluginPath .. '/MetadataDefinition.lua')
            tagset = dofile(pluginPath .. '/Tagset.lua')
        ''')
        fields = list(self.g.definition.metadataFieldsForPhotos.values())
        ids = [field.id for field in fields]
        self.assertEqual(ids, ['recipe', 'source', 'settings', 'adjustments', 'effects', 'noise', 'note'])
        self.assertTrue(all(field.title and field.readOnly for field in fields))
        prefix = self.g.info.LrToolkitIdentifier + '.'
        items = [item if isinstance(item, str) else item[1]
            for item in self.g.tagset['items'].values()]  # .items is a LuaTable method
        self.assertEqual([i for i in items if i.startswith(prefix)], [prefix + id for id in ids])
        self.assertEqual(self.g.info.LrMetadataTagsetFactory, 'Tagset.lua')

    def test_unavailable_originals_are_not_written_for_any_brand(self):
        self.run_lua("controller.start(); selectPhoto('first.JPG', 'FUJIFILM'); step()")
        for make in ['FUJIFILM', 'Panasonic', 'Canon', 'RICOH']:
            self.run_lua("selectPhoto('missing.JPG', '" + make + "'); step()")
            self.assertIsNone(self.g.stored['missing.JPG'], make)

    def test_recipe_name_is_given_for_fuji_only(self):
        self.run_lua("controller.start(); selectPhoto('recipe.JPG', 'FUJIFILM'); step(); "
            "selectPhoto('first.JPG', 'FUJIFILM'); step(); selectPhoto('gx80.JPG', 'Panasonic'); step()")
        self.assertEqual(self.g.stored['recipe.JPG'].recipe, 'Reala Everyday')
        self.assertEqual(self.g.stored['first.JPG'].recipe, 'Recette non identifiée')
        self.assertEqual(self.g.stored['first.JPG'].source, 'Aucune recette proche')
        self.assertIsNone(self.g.stored['gx80.JPG'].recipe)

    def test_fuji_model_without_make_is_still_read(self):
        self.run_lua("modelValue = 'X-T5'; controller.start(); selectPhoto('first.JPG', ''); step()")
        self.assertTrue(self.g.stored['first.JPG'].settings.startswith('PROVIA'))

    def test_unknown_model_values_stay_hidden(self):
        self.run_lua("info = dofile(pluginPath .. '/CameraInfo.lua')")
        for value in ['', ' ', 'Unknown', '(unknown)', 'Inconnu', 'N/A', '-', '?', '0']:
            self.assertEqual(self.g.info.clean(value), '')
        self.assertEqual(self.g.info.clean(' X-T5 '), 'X-T5')

    def test_brand_detection_from_make_or_model(self):
        self.run_lua('''
            info = dofile(pluginPath .. '/CameraInfo.lua')
            local function photo(make, model) return { getFormattedMetadata = function(self, key)
                if key == 'cameraMake' then return make elseif key == 'cameraModel' then return model end
                return ''
            end } end
            brands = {}
            for i, p in ipairs({ {'Panasonic', 'DMC-TZ30'}, {'', 'DMC-GF1'}, {'', 'DC-S5'},
                    {'Canon', 'Canon EOS 500D'}, {'', 'Canon EOS 40D'}, {'FUJIFILM', 'X-T5'},
                    {'', 'X100V'}, {'SONY', 'ILCE-7M2'}, {'Apple', 'iPhone XR'}, {'', 'iPhone 7'},
                    {'RICOH IMAGING COMPANY, LTD.', 'GR Digital'}, {'', 'GR III'}, {'', 'Caplio GX'},
                    {'Google', 'Pixel 7a'} }) do
                local camera = info.describe(photo(p[1], p[2]))
                brands[i] = camera.brand or (camera.fuji and 'fuji') or 'none'
            end
        ''')
        self.assertEqual([self.g.brands[i] for i in range(1, 15)],
            ['panasonic', 'panasonic', 'panasonic', 'canon', 'canon', 'fuji', 'fuji', 'none',
             'apple', 'apple', 'ricoh', 'ricoh', 'ricoh', 'none'])

    def test_heic_is_not_read_and_gives_no_error(self):
        self.run_lua("controller.start(); selectPhoto('heic.JPG', 'Apple'); step()")
        self.assertIsNone(self.g.stored['heic.JPG'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
