"""Execute the actual Lua 5.1 Canon reader and formatter against binary fixtures."""
from pathlib import Path
import struct
import tempfile
import unittest

from lua_env import runtime

ROOT = Path(__file__).resolve().parents[1]

# Positions inside the three maker-note blocks, counted from the size word like ExifTool does.
CS = dict(quality=3, scene=11, contrast=13, saturation=14, sharpness=15, exposure=20, tone=42)
SI = dict(white_balance=7)
PI = dict(curve=1, sharpness=2, kelvin=9, style=10, amber=12, green=13)


def block(count, positions, **values):
    out = [0] * count
    out[0] = 2 * count  # the first word is the size of the block in bytes
    for name, value in values.items():
        out[positions[name]] = value
    return out


def eos(cs=None, si=None, pi=None):
    """A 500D in full auto, Standard style, nothing adjusted."""
    cs = dict(dict(quality=3, scene=0, exposure=0, sharpness=32767), **(cs or {}))
    si = dict(dict(white_balance=0), **(si or {}))
    pi = dict(dict(style=0x81, sharpness=3, kelvin=5200), **(pi or {}))
    return {0x1: block(49, CS, **cs), 0x4: block(34, SI, **si), 0xa0: block(14, PI, **pi)}


def jpeg_fixture(endian='<', make=b'Canon\0', blocks=None, notes=True, misplaced=False):
    blocks = eos() if blocks is None else blocks
    # Maker note: a headerless IFD of SHORT arrays whose offsets count from the TIFF header.
    # root at 8 (2 entries), Make at 38, ExifIFD after Make, maker note after ExifIFD.
    exif_offset = 38 + len(make)
    note_offset = exif_offset + 18
    cursor = note_offset + 2 + 12 * len(blocks) + 4
    entries, data = b'', b''
    for tag, values in blocks.items():
        raw = b''.join(struct.pack(endian + 'h', v) for v in values)
        entries += struct.pack(endian + 'HHII', tag, 3, len(values), cursor)
        data += raw
        cursor += len(raw)
    # A misplaced maker note reads as an IFD with an absurd number of entries.
    note = struct.pack(endian + 'H', 8960 if misplaced else len(blocks)) + entries + b'\0' * 4 + data
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


class CanonTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime(unpack_returned_tuples=True, encoding='utf-8')
        plugin = ROOT / 'fuji-recipe.lrplugin'
        self.reader = self.lua.execute((plugin / 'CanonReader.lua').read_text(encoding='utf-8'))
        self.format = self.lua.execute((plugin / 'CanonFormat.lua').read_text(encoding='utf-8'))
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write(self, name, content):
        p = Path(self.tmp.name) / name
        p.write_bytes(content)
        return str(p)

    def describe(self, cs=None, si=None, pi=None):
        data, code, message = self.reader.read(self.write('image.JPG', jpeg_fixture(blocks=eos(cs, si, pi))))
        self.assertIsNone(code, message)
        return self.format.describe(data)

    def test_500d_standard_full_auto_both_tiff_byte_orders(self):
        for endian in ['<', '>']:
            data, code, _ = self.reader.read(self.write('image.JPG', jpeg_fixture(endian)))
            self.assertIsNone(code)
            self.assertEqual(data.tags[0x1][1], 98)
            self.assertEqual(data.tags[0xa0][11], 0x81)
            text = self.format.describe(data)
            self.assertEqual(text.first, 'STANDARD · WB AUTO')
            self.assertEqual(text.second, 'Auto')
            self.assertIn('Contraste 0 · Saturation 0 · Ton de couleur 0 · Netteté 3', text.details)
            self.assertIn('Qualité fine', text.details)

    def test_mode_comes_from_exposure_mode_or_the_scene_mode(self):
        self.assertEqual(self.describe(cs=dict(exposure=1)).second, 'Programme')
        self.assertEqual(self.describe(cs=dict(exposure=3, scene=1)).second, 'Priorité ouverture')
        self.assertEqual(self.describe(cs=dict(scene=9)).second, 'Sport')
        self.assertEqual(self.describe(cs=dict(scene=59)).second, 'Auto intelligent')
        self.assertEqual(self.describe(cs=dict(scene=15)).second, 'Flash désactivé')
        text = self.describe(cs=dict(scene=99))
        self.assertEqual(text.second, 'Mode ?')
        self.assertIn('code 99', text.details)

    def test_auto_style_sharpness_is_not_a_deviation(self):
        text = self.describe(pi=dict(style=0x87, sharpness=2))
        self.assertEqual((text.first, text.second), ('AUTO · WB AUTO', 'Auto'))
        self.assertIn('Style Auto', text.details)

    def test_sharpness_is_reported_against_the_style_default(self):
        self.assertEqual(self.describe(pi=dict(style=0x82, sharpness=2)).second, 'Auto')
        self.assertEqual(self.describe(pi=dict(style=0x83, sharpness=4)).second, 'Auto')
        text = self.describe(pi=dict(style=0x81, sharpness=5))
        self.assertEqual(text.second, 'Auto · Netteté 5 (3 par défaut)')
        self.assertEqual(self.describe(pi=dict(style=0x83)).first, 'PAYSAGE · WB AUTO')

    def test_adjustments_only_when_off_normal(self):
        text = self.describe(cs=dict(contrast=1, saturation=-2, tone=-1))
        self.assertEqual(text.second, 'Auto · Contraste +1 · Saturation −2 · Ton de couleur −1')
        text = self.describe(cs=dict(contrast=32767, saturation=32767, tone=32767))  # not available
        self.assertEqual(text.second, 'Auto')
        self.assertNotIn('Contraste', text.details)

    def test_white_balance_and_processing_flags(self):
        self.assertEqual(self.describe(si=dict(white_balance=1)).first, 'STANDARD · WB JOUR')
        self.assertEqual(self.describe(si=dict(white_balance=9), pi=dict(kelvin=6500)).first, 'STANDARD · WB 6500 K')
        self.assertEqual(self.describe(si=dict(white_balance=99)).first, 'STANDARD · WB ?')
        text = self.describe(pi=dict(amber=2, green=-1, curve=1))
        self.assertEqual(text.second, 'Auto · Courbe de tons manuelle · WB A/B +2 / G/M −1')

    def test_no_style_when_the_camera_reports_none(self):
        self.assertEqual(self.describe(pi=dict(style=0)).first, 'WB AUTO')
        self.assertEqual(self.describe(pi=dict(style=255)).first, 'WB AUTO')
        self.assertEqual(self.describe(pi=dict(style=0x99)).first, 'STYLE ? · WB AUTO')

    def test_missing_notes_and_other_makes(self):
        data, code, _ = self.reader.read(self.write('image.JPG', jpeg_fixture(notes=False)))
        self.assertIsNone(data)
        self.assertEqual(code, 'missing_notes')
        data, code, _ = self.reader.read(self.write('other.JPG', jpeg_fixture(make=b'FUJIFILM\0')))
        self.assertIsNone(data)
        self.assertEqual(code, 'not_canon')

    def test_misplaced_maker_note_is_reported_not_guessed(self):
        data, code, message = self.reader.read(self.write('image.JPG', jpeg_fixture(misplaced=True)))
        self.assertIsNone(data)
        self.assertEqual(code, 'invalid_notes')
        self.assertIn('illisibles', message)

    def test_invalid_files_fail_safely(self):
        for name, content in [('empty.JPG', b''), ('cut.JPG', jpeg_fixture()[:60]), ('notjpeg.jpg', b'X' * 100)]:
            data, code, _ = self.reader.read(self.write(name, content))
            self.assertIsNone(data)
            self.assertEqual(code, 'invalid')

    def test_unsupported_and_missing(self):
        self.assertEqual(self.reader.read('missing.JPG')[1], 'unavailable')
        self.assertEqual(self.reader.read('image.CR2')[1], 'unsupported')


if __name__ == '__main__':
    unittest.main(verbosity=2)
