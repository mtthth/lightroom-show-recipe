"""Execute the actual Lua 5.1 Panasonic reader and formatter against binary fixtures."""
from pathlib import Path
import struct
import tempfile
import unittest

from lua_env import runtime

ROOT = Path(__file__).resolve().parents[1]

# A GX80 in Intelligent Auto Plus: Standard style, white balance auto, saturation +5, sharpness -1.
GX80 = {0x03: 1, 0x1f: 60, 0x89: 1, 0x39: 0, 0x40: 5, 0x41: 65535, 0x2d: 0, 0x70: 2, 0x5d: 0, 0x49: 2}


def jpeg_fixture(endian='<', make=b'Panasonic\0', tags=None, notes=True):
    tags = GX80 if tags is None else tags
    # Maker note: "Panasonic\0\0\0", then an IFD of inline SHORT values (offsets count from the TIFF header).
    note = b'Panasonic\0\0\0' + struct.pack(endian + 'H', len(tags))
    for tag, value in tags.items():
        note += struct.pack(endian + 'HHI', tag, 3, 1) + struct.pack(endian + 'H', value) + b'\0\0'
    note += b'\0' * 4
    # root at 8 (2 entries), Make at 38, ExifIFD after Make, maker note after ExifIFD.
    exif_offset = 38 + len(make)
    note_offset = exif_offset + 18
    header = (b'II' if endian == '<' else b'MM') + struct.pack(endian + 'HI', 42, 8)
    root = struct.pack(endian + 'H', 2)
    root += struct.pack(endian + 'HHII', 0x010f, 2, len(make), 38)
    root += struct.pack(endian + 'HHII', 0x8769, 4, 1, exif_offset)
    root += b'\0' * 4
    exif = struct.pack(endian + 'H', 1 if notes else 0)
    if notes:
        exif += struct.pack(endian + 'HHII', 0x927c, 7, len(note), note_offset)
    exif += b'\0' * 4
    tiff = header + root + make + exif + (note if notes else b'')
    app = b'Exif\0\0' + tiff
    return b'\xff\xd8\xff\xe1' + struct.pack('>H', len(app) + 2) + app + b'\xff\xd9'


class PanasonicTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime(unpack_returned_tuples=True, encoding='utf-8')
        plugin = ROOT / 'show-recipe.lrplugin'
        self.reader = self.lua.execute((plugin / 'PanasonicReader.lua').read_text(encoding='utf-8'))
        self.format = self.lua.execute((plugin / 'PanasonicFormat.lua').read_text(encoding='utf-8'))
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write(self, name, content):
        p = Path(self.tmp.name) / name
        p.write_bytes(content)
        return str(p)

    def describe(self, tags, name='image.JPG'):
        data, code, message = self.reader.read(self.write(name, jpeg_fixture(tags=tags)))
        self.assertIsNone(code, message)
        return self.format.describe(data)

    def test_gx80_both_tiff_byte_orders(self):
        for endian in ['<', '>']:
            data, code, _ = self.reader.read(self.write('image.JPG', jpeg_fixture(endian)))
            self.assertIsNone(code)
            self.assertEqual(data.tags[0x40], 5)
            self.assertEqual(data.tags[0x41], 65535)
            text = self.format.describe(data)
            self.assertEqual(text.first, 'STANDARD · WB AUTO')
            self.assertEqual(text.second, 'Auto intelligent + · Saturation +5 · Netteté −1')
            self.assertIn('Contraste 0 · Saturation +5 · Netteté −1 · Bruit 0', text.details)
            self.assertIn('i.Résolution standard · Exposition intelligente off · Bruit pose longue on', text.details)
            self.assertIn('personnalisé', text.details)

    def test_defaults_show_only_look_and_mode(self):
        text = self.describe({0x03: 1, 0x1f: 2, 0x89: 1, 0x39: 0, 0x40: 0, 0x41: 0, 0x2d: 0})
        self.assertEqual(text.first, 'STANDARD · WB AUTO')
        self.assertEqual(text.second, 'Portrait')

    def test_models_with_film_mode_or_color_effect_only(self):
        text = self.describe({0x03: 1, 0x42: 2, 0x28: 1, 0x1f: 37})  # GF1: film mode
        self.assertEqual((text.first, text.second), ('DYNAMIQUE · WB AUTO', 'Auto intelligent'))
        text = self.describe({0x03: 1, 0x28: 6, 0x1f: 37, 0x2c: 6})  # TZ30: no style tag
        self.assertEqual((text.first, text.second), ('HAPPY · WB AUTO', 'Auto intelligent'))
        text = self.describe({0x03: 1, 0x28: 1, 0x1f: 2})  # TZ7: color effect off
        self.assertEqual((text.first, text.second), ('WB AUTO', 'Portrait'))
        text = self.describe({0x42: 0, 0x28: 1})  # film mode n/a, no mode, no white balance
        self.assertEqual((text.first, text.second), ('WB ?', ''))

    def test_unrecognised_codes_are_marked_not_invented(self):
        text = self.describe({0x03: 99, 0x1f: 99, 0x89: 99, 0x2d: 77})
        self.assertEqual(text.first, 'STYLE ? · WB ?')
        self.assertEqual(text.second, 'Mode ? · Bruit ?')
        self.assertIn('code 99', text.details)

    def test_noise_reduction_encodings(self):
        self.assertIn('Bruit +2', self.describe({0x2d: 4}).second)
        self.assertIn('Bruit −1', self.describe({0x2d: 65535}).second)
        self.assertNotIn('Bruit', self.describe({0x2d: 0}).second)

    def test_missing_notes_and_other_makes(self):
        data, code, _ = self.reader.read(self.write('image.JPG', jpeg_fixture(notes=False)))
        self.assertIsNone(data)
        self.assertEqual(code, 'missing_notes')
        data, code, _ = self.reader.read(self.write('other.JPG', jpeg_fixture(make=b'FUJIFILM\0')))
        self.assertIsNone(data)
        self.assertEqual(code, 'not_panasonic')

    def test_invalid_files_fail_safely(self):
        for name, content in [('empty.JPG', b''), ('cut.JPG', jpeg_fixture()[:60]), ('notjpeg.jpg', b'X' * 100)]:
            data, code, _ = self.reader.read(self.write(name, content))
            self.assertIsNone(data)
            self.assertEqual(code, 'invalid')

    def test_unsupported_and_missing(self):
        self.assertEqual(self.reader.read('missing.JPG')[1], 'unavailable')
        self.assertEqual(self.reader.read('image.RW2')[1], 'unsupported')


if __name__ == '__main__':
    unittest.main(verbosity=2)
