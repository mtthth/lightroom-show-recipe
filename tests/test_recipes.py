"""Recipes.lua must follow fuji-recipes.csv, and each recipe must be found from its MakerNotes."""
import csv
from pathlib import Path
import re
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.test-deps'))
sys.path.insert(0, str(ROOT / 'scripts'))
from lupa.lua51 import LuaRuntime
import build_recipes

# Independent encoding of the CSV vocabulary as MakerNotes values (X-T5).
FILM_MODES = {
    'Provia/Standard': 0, 'Astia/Soft': 0x120, 'Velvia/Vivid': 0x200, 'PRO Neg. Std': 0x500,
    'PRO Neg. Hi': 0x501, 'Classic Chrome': 0x600, 'Eterna/Cinema': 0x700,
    'Classic Negative': 0x800, 'Eterna Bleach Bypass': 0x900, 'Nostalgic Negative': 0xa00,
    'Reala Ace': 0xb00,
}
MONOCHROME = {
    'Monochrome': 0x300, 'Monochrome+R': 0x301, 'Monochrome+Ye': 0x302, 'Monochrome+G': 0x303,
    'Sepia': 0x310, 'Acros': 0x500, 'Acros+R': 0x501, 'Acros+Ye': 0x502, 'Acros+G': 0x503,
}
WHITE = {
    'Auto': 0, 'Auto (White Priority)': 1, 'Auto (Ambience Priority)': 2, 'Daylight': 0x100,
    'Shade': 0x200, 'Fluorescent 1': 0x300, 'Fluorescent 2': 0x301, 'Fluorescent 3': 0x302,
    'Incandescent': 0x400, 'Underwater': 0x600,
}
SATURATION = {0: 0, 1: 0x80, 2: 0x100, 3: 0xc0, 4: 0xe0, -1: 0x180, -2: 0x400, -3: 0x4c0, -4: 0x4e0}
SHARPNESS = {-4: 0, -3: 1, -2: 2, -1: 0x82, 0: 3, 1: 0x84, 2: 4, 3: 5, 4: 6}
NOISE = {0: 0, 2: 0x100, 1: 0x180, 3: 0x1c0, 4: 0x1e0, -2: 0x200, -1: 0x280, -3: 0x2c0, -4: 0x2e0}
LEVEL = {'Off': 0, 'Weak': 32, 'Strong': 64}
SIZE = {'Small': 16, 'Large': 32}


def number(text):
    return float(text) if text else 0


def tags_for(lua, row):
    tags = {}
    film = row['film_simulation']
    if film in MONOCHROME:
        tags[0x1003] = MONOCHROME[film]
    else:
        tags[0x1401] = FILM_MODES[film]
        tags[0x1003] = SATURATION[int(row['color'])]
    if row['dr_priority'] != 'Off':
        tags[0x1443] = 1
        tags[0x1445] = {'Weak': 1, 'Strong': 2}[row['dr_priority']]
    elif row['dynamic_range'] == 'Auto':
        tags[0x1402], tags[0x140b] = 0, 200
    else:
        tags[0x1402], tags[0x1403] = 1, int(row['dynamic_range'][2:])
    kelvin = re.fullmatch(r'(\d+)K', row['white_balance'])
    if kelvin:
        tags[0x1002], tags[0x1005] = 0xff0, int(kelvin.group(1))
    else:
        tags[0x1002] = WHITE[row['white_balance']]
    tags[0x100a] = lua.table_from([int(row['wb_shift_red']) * 20, int(row['wb_shift_blue']) * 20])
    tags[0x1041] = int(number(row['highlight']) * -16)
    tags[0x1040] = int(number(row['shadow']) * -16)
    tags[0x1047] = LEVEL[row['grain_effect']]
    tags[0x104c] = SIZE.get(row['grain_size'], 0)
    tags[0x1048] = LEVEL[row['color_chrome_effect']]
    tags[0x104e] = LEVEL[row['color_chrome_fx_blue']]
    tags[0x1001] = SHARPNESS[int(row['sharpness'])]
    tags[0x100e] = NOISE[int(row['high_iso_nr'])]
    tags[0x100f] = int(row['clarity']) * 1000
    return tags


class RecipeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True, encoding='utf-8')
        plugin = ROOT / 'fuji-recipe.lrplugin'
        self.format = self.lua.execute((plugin / 'FujiFormat.lua').read_text(encoding='utf-8'))
        self.match = self.lua.execute((plugin / 'RecipeMatch.lua').read_text(encoding='utf-8'))
        self.recipes = self.lua.execute((plugin / 'Recipes.lua').read_text(encoding='utf-8'))
        with open(ROOT / 'fuji-recipes.csv', encoding='utf-8', newline='') as source:
            self.rows = list(csv.DictReader(source))

    def find(self, tags):
        data = self.lua.table_from({'tags': self.lua.table_from(tags)})
        return self.match.find(self.recipes, self.format.settings(data))

    def test_recipes_lua_follows_the_csv(self):
        generated = (ROOT / 'fuji-recipe.lrplugin' / 'Recipes.lua').read_text(encoding='utf-8')
        self.assertEqual(generated, build_recipes.build(self.rows),
            'Run python scripts/build_recipes.py')

    def test_each_recipe_is_found_from_its_makernotes(self):
        self.assertEqual(len(self.recipes), len(self.rows))
        for row in self.rows:
            result = self.find(tags_for(self.lua, row))
            self.assertEqual([r.name for r in result.matches.values()], [row['nom']], row['nom'])

    def test_no_two_recipes_can_match_the_same_photo(self):
        recipes = [dict(r.items()) for r in self.recipes.values()]
        ignored = {'name', 'source'}
        for i, a in enumerate(recipes):
            for b in recipes[i + 1:]:
                shared = (a.keys() & b.keys()) - ignored
                self.assertTrue(any(a[k] != b[k] for k in shared), a['name'] + ' / ' + b['name'])

    def test_a_different_setting_is_not_the_recipe(self):
        row = next(r for r in self.rows if r['nom'] == "Reggie's Portra")
        tags = tags_for(self.lua, row)
        tags[0x1001] = SHARPNESS[0]
        result = self.find(tags)
        self.assertEqual(len(result.matches), 0)
        self.assertEqual(result.near.name, "Reggie's Portra")
        self.assertEqual(list(result.differences.values()), ['Netteté'])
        line, detail = self.format.recipe(result)
        self.assertEqual(line, 'Recette non identifiée')
        self.assertIn('Plus proche : Reggie\'s Portra (écarts : Netteté)', detail)

    def test_priority_dr_must_agree(self):
        row = next(r for r in self.rows if r['dr_priority'] == 'Strong')
        tags = tags_for(self.lua, row)
        del tags[0x1443]
        tags[0x1402], tags[0x1403] = 1, 400
        self.assertEqual(len(self.find(tags).matches), 0)

    def test_numbered_fluorescent_presets_cannot_substitute_for_each_other(self):
        row = next(r for r in self.rows if r['white_balance'] == 'Fluorescent 3')
        tags = tags_for(self.lua, row)
        for code in [0x300, 0x301, 0x302, 0x303, 0x304]:
            with self.subTest(code=hex(code)):
                tags[0x1002] = code
                names = [recipe.name for recipe in self.find(tags).matches.values()]
                self.assertEqual(names, [row['nom']] if code == 0x302 else [])
        data = self.lua.table_from({'tags': self.lua.table_from(tags)})
        for code, label in [(0x300, 'FLUO 1'), (0x301, 'FLUO 2'), (0x302, 'FLUO 3')]:
            data.tags[0x1002] = code
            self.assertIn('WB ' + label, self.format.describe(data).first)

    def test_dr_priority_requires_the_fixed_strength_not_just_a_present_tag(self):
        row = next(r for r in self.rows if r['dr_priority'] == 'Strong')
        tags = tags_for(self.lua, row)
        for mode, strength in [(1, 1), (1, 2), (1, None), (1, 3), (0, 2), (99, 2)]:
            with self.subTest(mode=mode, strength=strength):
                tags[0x1443] = mode
                tags.pop(0x1445, None)
                if strength is not None:
                    tags[0x1445] = strength
                tags[0x1444] = 2
                names = [recipe.name for recipe in self.find(tags).matches.values()]
                self.assertEqual(names, [row['nom']] if (mode, strength) == (1, 2) else [])

    def test_dr_priority_is_explicit_in_the_display(self):
        for tags, expected in [
            ({0x1443: 1, 0x1445: 1}, 'PRIORITÉ DR FAIBLE'),
            ({0x1443: 1, 0x1445: 2}, 'PRIORITÉ DR FORTE'),
            ({0x1443: 0, 0x1444: 2}, 'PRIORITÉ DR AUTO (FORTE)'),
            ({0x1443: 1}, 'PRIORITÉ DR ?'),
        ]:
            with self.subTest(tags=tags):
                data = self.lua.table_from({'tags': self.lua.table_from(tags)})
                self.assertIn(expected, self.format.describe(data).first)

    def test_real_x_t5_signature_is_not_a_recipe(self):
        # Reala Ace photos of the catalog: colour 0 and noise reduction +1.
        result = self.find({
            0x1401: 0xb00, 0x1003: 0, 0x1402: 0, 0x140b: 100, 0x1002: 0,
            0x100a: self.lua.table_from([0, 0]), 0x1041: 0, 0x1040: 0, 0x1001: 3,
            0x100e: 384, 0x100f: 0, 0x1047: 32, 0x104c: 16, 0x1048: 32, 0x104e: 32,
        })
        self.assertEqual(len(result.matches), 0)
        self.assertEqual(result.near.name, 'Reala Everyday')
        self.assertEqual(list(result.differences.values()), ['Couleur', 'Bruit'])

    def test_unreadable_settings_match_nothing(self):
        result = self.find({})
        self.assertEqual(len(result.matches), 0)
        self.assertIsNone(result.near)
        self.assertEqual(self.format.recipe(result), ('Recette non identifiée',
            'Aucune recette connue ne correspond exactement à ces réglages.'))

    def test_identical_recipes_are_all_listed(self):
        twin = dict(self.recipes[1].items())
        twin['name'] = 'Jumelle'
        recipes = self.lua.table_from([self.recipes[1], self.lua.table_from(twin)])
        settings = self.format.settings(self.lua.table_from({'tags': self.lua.table_from(
            tags_for(self.lua, self.rows[0]))}))
        result = self.match.find(recipes, settings)
        line, detail = self.format.recipe(result)
        self.assertEqual(line, self.rows[0]['nom'] + ' / Jumelle')
        self.assertIn('Recette : ' + self.rows[0]['nom'] + ' · ' + self.rows[0]['source'], detail)

    def test_csv_vocabulary_matches_the_makernotes_decoding(self):
        # Every film and white balance the builder accepts decodes to its label.
        for name, label in build_recipes.FILMS.items():
            tags = {0x1003: MONOCHROME[name]} if name in MONOCHROME else {0x1401: FILM_MODES[name]}
            settings = self.format.settings(self.lua.table_from({'tags': self.lua.table_from(tags)}))
            self.assertEqual(settings.film, label, name)
        for name, kind in build_recipes.WHITE.items():
            tags = {0x1002: WHITE[name]}
            settings = self.format.settings(self.lua.table_from({'tags': self.lua.table_from(tags)}))
            self.assertEqual(settings.wb, kind, name)

    def test_builder_rejects_unknown_or_contradictory_values(self):
        row = dict(self.rows[0])
        for column, value in [('film_simulation', 'Velvia'), ('white_balance', 'Cloudy'),
                ('grain_effect', ''), ('clarity', 'beaucoup')]:
            with self.assertRaises(SystemExit, msg=column):
                build_recipes.convert({**row, column: value})
        with self.assertRaises(SystemExit):
            build_recipes.convert({**row, 'dr_priority': 'Strong'})


if __name__ == '__main__':
    unittest.main(verbosity=2)
