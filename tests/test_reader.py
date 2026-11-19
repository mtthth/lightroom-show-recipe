"""Execute the actual Lua 5.1 reader against binary fixtures."""
from pathlib import Path
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
from lua_env import runtime


def jpeg_fixture(endian='<', make=b'FUJIFILM\0', notes=True):
    # Independent TIFF/EXIF fixture, including a signed tone and WB shift array.
    note = b'FUJIFILM' + struct.pack('<I', 12) + struct.pack('<H', 6)
    for tag, kind, count, value in [
        (0x1401, 3, 1, 0x600), (0x1002, 3, 1, 0),
        (0x100a, 9, 2, 12 + 2 + 6 * 12 + 4),
        (0x1041, 9, 1, 32), (0x1040, 9, 1, -32),
        (0x1003, 3, 1, 0x100),
    ]:
        inline = struct.pack('<h', value) + b'\0\0' if kind == 3 else struct.pack('<i', value)
        note += struct.pack('<HHI', tag, kind, count) + inline
    note += b'\0' * 4 + struct.pack('<ii', 40, -100)
    # root at 8 (2 entries), Make at 38, ExifIFD after Make, MakerNotes after ExifIFD.
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


def raf_fixture(jpeg):
    header = bytearray(100)
    header[:16] = b'FUJIFILMCCD-RAW '
    header[84:92] = struct.pack('>II', 100, len(jpeg))
    return bytes(header) + jpeg


class ReaderTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime(unpack_returned_tuples=True, encoding='utf-8')
        plugin = ROOT / 'show-recipe.lrplugin'
        self.reader = self.lua.execute((plugin / 'FujiReader.lua').read_text(encoding='utf-8'))
        self.format = self.lua.execute((plugin / 'FujiFormat.lua').read_text(encoding='utf-8'))
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write(self, name, content):
        p = Path(self.tmp.name) / name
        p.write_bytes(content)
        return str(p)

    def test_jpeg_both_tiff_byte_orders_and_signed_values(self):
        for endian in ['<', '>']:
            path = self.write('image.JPG', jpeg_fixture(endian))
            data, code, message = self.reader.read(path)
            self.assertIsNone(code)
            self.assertEqual(data.tags[0x1040], -32)
            self.assertEqual(data.tags[0x100a][2], -100)
            text = self.format.describe(data)
            self.assertIn('CLASSIC CHROME', text.first)
            self.assertIn('R +2 / B −5', text.first)
            self.assertIn('H −2 · S +2 · Couleur +2', text.second)
            self.assertIn('Netteté ?', text.second)

    def test_raf_preview_and_companion_fallback(self):
        path = self.write('image.JPG', jpeg_fixture(notes=False))
        raf = self.write('image.RAF', raf_fixture(jpeg_fixture()))
        direct, _, _ = self.reader.read(raf)
        self.assertEqual(direct.tags[0x1401], 0x600)
        found = self.reader.readWithCompanion(path)
        self.assertTrue(found.fromCompanion)
        self.assertEqual(found.sourcePath, raf)

    def test_missing_notes_is_not_a_default_recipe(self):
        data, code, _ = self.reader.read(self.write('image.JPG', jpeg_fixture(notes=False)))
        self.assertIsNone(data)
        self.assertEqual(code, 'missing_notes')

    def test_non_fuji_is_not_matched_to_fuji_companion(self):
        path = self.write('image.JPG', jpeg_fixture(make=b'OTHERBRAND\0'))
        self.write('image.RAF', raf_fixture(jpeg_fixture()))
        data, code, _ = self.reader.readWithCompanion(path)
        self.assertIsNone(data)
        self.assertEqual(code, 'not_fuji')

    def test_invalid_files_fail_safely(self):
        for name, content in [
            ('empty.JPG', b''), ('cut.JPG', jpeg_fixture()[:40]),
            ('cut.RAF', b'FUJIFILMCCD-RAW '),
            ('wrong.RAF', b'X' * 100),
            ('offset.RAF', raf_fixture(jpeg_fixture())[:100]),
        ]:
            data, code, _ = self.reader.read(self.write(name, content))
            self.assertIsNone(data)
            self.assertEqual(code, 'invalid')

    def test_present_settings_with_invalid_types_or_cardinality_are_rejected(self):
        cases = [
            # A scalar tone as text or an array; a two-value WB shift as a scalar.
            (struct.pack('<HHI', 0x1041, 9, 1), struct.pack('<HHI', 0x1041, 2, 4) + b'abc\0'),
            (struct.pack('<HHI', 0x1041, 9, 1), struct.pack('<HHI', 0x1041, 3, 2) + b'\0' * 4),
            (struct.pack('<HHI', 0x100a, 9, 2), struct.pack('<HHI', 0x100a, 9, 1) + b'\0' * 4),
        ]
        for original, replacement in cases:
            with self.subTest(replacement=replacement):
                raw = bytearray(jpeg_fixture())
                position = raw.index(original)
                raw[position:position + 12] = replacement
                data, code, message = self.reader.read(self.write('bad.JPG', raw))
                self.assertIsNone(data)
                self.assertEqual(code, 'invalid')
                self.assertIn('Type de métadonnée invalide', message)

    def test_unsupported_and_missing(self):
        self.assertEqual(self.reader.read('missing.JPG')[1], 'unavailable')
        self.assertEqual(self.reader.read('image.DNG')[1], 'unsupported')

    def test_monochrome_and_absent_fields(self):
        data = self.lua.table_from({'tags': self.lua.table_from({0x1003: 0x501, 0x1401: 0})})
        text = self.format.describe(data)
        self.assertTrue(text.first.startswith('ACROS +R'))
        self.assertIn('Couleur N/B', text.second)
        self.assertIn('H ?', text.second)

    def test_all_plugin_files_compile_as_lua51(self):
        compiler = self.lua.eval('function(code, name) local f, err = loadstring(code, name); assert(f, err) end')
        for path in (ROOT / 'show-recipe.lrplugin').glob('*.lua'):
            compiler(path.read_text(encoding='utf-8'), path.name)


if __name__ == '__main__':
    unittest.main(verbosity=2)
