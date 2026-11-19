"""Execute the actual Lua 5.1 mode reader and formatter against binary fixtures."""
from pathlib import Path
import struct
import tempfile
import unittest

from lua_env import runtime

ROOT = Path(__file__).resolve().parents[1]
EXPOSURE_PROGRAM, CUSTOM_RENDERED, SCENE_CAPTURE_TYPE, WHITE_BALANCE = 0x8822, 0xa401, 0xa406, 0xa403


def jpeg_fixture(endian='<', make=b'Apple\0', tags=None, exif=True):
    """A JPEG whose Exif IFD holds inline SHORT values; exif=False leaves the Exif IFD out."""
    tags = tags or {}
    root_entries = 2 if exif else 1
    make_offset = 8 + 2 + 12 * root_entries + 4
    exif_offset = make_offset + len(make)
    header = (b'II' if endian == '<' else b'MM') + struct.pack(endian + 'HI', 42, 8)
    root = struct.pack(endian + 'H', root_entries)
    root += struct.pack(endian + 'HHII', 0x010f, 2, len(make), make_offset)
    if exif:
        root += struct.pack(endian + 'HHII', 0x8769, 4, 1, exif_offset)
    root += b'\0' * 4
    block = b''
    if exif:
        block = struct.pack(endian + 'H', len(tags))
        for tag, value in tags.items():
            block += struct.pack(endian + 'HHI', tag, 3, 1) + struct.pack(endian + 'H', value) + b'\0\0'
        block += b'\0' * 4
    tiff = header + root + make + block
    app = b'Exif\0\0' + tiff
    return b'\xff\xd8\xff\xe1' + struct.pack('>H', len(app) + 2) + app + b'\xff\xd9'


class ModeTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime(unpack_returned_tuples=True, encoding='utf-8')
        plugin = ROOT / 'show-recipe.lrplugin'
        self.reader = self.lua.execute((plugin / 'ModeReader.lua').read_text(encoding='utf-8'))
        self.format = self.lua.execute((plugin / 'ModeFormat.lua').read_text(encoding='utf-8'))
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def write(self, name, content):
        p = Path(self.tmp.name) / name
        p.write_bytes(content)
        return str(p)

    def mode(self, brand, tags, endian='<'):
        data, code, message = self.reader.read(self.write('image.JPG', jpeg_fixture(endian, tags=tags)))
        self.assertIsNone(code, message)
        return self.format.describe(data, brand)

    def test_iphone_modes_from_custom_rendered_and_scene_type_both_byte_orders(self):
        for endian in ['<', '>']:
            data, code, _ = self.reader.read(self.write('image.JPG', jpeg_fixture(endian, tags={CUSTOM_RENDERED: 7})))
            self.assertIsNone(code)
            self.assertEqual(data.tags.rendered, 7)
            self.assertEqual(data.make, 'Apple')
            self.assertEqual(self.format.describe(data, 'apple'), 'Portrait HDR')
        expected = {8: 'Portrait', 7: 'Portrait HDR', 6: 'Panorama', 3: 'HDR', 2: 'HDR', 4: 'Original HDR', 0: '', 1: ''}
        for value, label in expected.items():
            self.assertEqual(self.mode('apple', {CUSTOM_RENDERED: value}), label, value)
        self.assertEqual(self.mode('apple', {SCENE_CAPTURE_TYPE: 2}), 'Portrait')
        self.assertEqual(self.mode('apple', {SCENE_CAPTURE_TYPE: 3}), 'Nuit')
        self.assertEqual(self.mode('apple', {SCENE_CAPTURE_TYPE: 0}), '')
        # The exposure program of a phone is always "normal": it is not a mode.
        self.assertEqual(self.mode('apple', {EXPOSURE_PROGRAM: 2}), '')

    def test_ricoh_mode_from_the_exposure_program(self):
        expected = {1: 'Manuel', 2: 'Programme', 3: 'Priorité ouverture', 4: 'Priorité vitesse', 0: '', 99: ''}
        for value, label in expected.items():
            self.assertEqual(self.mode('ricoh', {EXPOSURE_PROGRAM: value}), label, value)
        self.assertEqual(self.mode('ricoh', {CUSTOM_RENDERED: 8}), '')

    def test_ricoh_settings_line_is_the_exif_white_balance(self):
        for value, label in {0: 'WB AUTO', 1: 'WB MANUEL'}.items():
            data, code, _ = self.reader.read(self.write('image.JPG', jpeg_fixture(tags={WHITE_BALANCE: value})))
            self.assertIsNone(code)
            self.assertEqual(self.format.look(data, 'ricoh'), label)
            self.assertEqual(self.format.look(data, 'apple'), '')  # a phone's is always auto
        # The Ricoh keeps its layout when the file says nothing or cannot be read.
        data, _, _ = self.reader.read(self.write('image.JPG', jpeg_fixture(tags={})))
        self.assertEqual(self.format.look(data, 'ricoh'), 'WB ?')
        self.assertEqual(self.format.look(None, 'ricoh'), 'WB ?')
        self.assertEqual(self.format.look(None, 'apple'), '')

    def test_other_brands_and_absent_tags_name_no_mode(self):
        self.assertEqual(self.mode('sony', {EXPOSURE_PROGRAM: 3, CUSTOM_RENDERED: 8}), '')
        self.assertEqual(self.mode(None, {EXPOSURE_PROGRAM: 3}), '')
        self.assertEqual(self.mode('apple', {}), '')

    def test_missing_exif_ifd_and_damaged_files(self):
        data, code, _ = self.reader.read(self.write('image.JPG', jpeg_fixture(exif=False)))
        self.assertIsNone(data)
        self.assertEqual(code, 'missing_notes')
        for name, content in [('empty.JPG', b''), ('cut.JPG', jpeg_fixture(tags={CUSTOM_RENDERED: 7})[:50]),
                              ('notjpeg.jpg', b'X' * 100)]:
            data, code, _ = self.reader.read(self.write(name, content))
            self.assertIsNone(data)
            self.assertEqual(code, 'invalid')

    def test_unsupported_and_missing(self):
        self.assertEqual(self.reader.read('missing.JPG')[1], 'unavailable')
        self.assertEqual(self.reader.read('image.HEIC')[1], 'unsupported')
        self.assertEqual(self.reader.read('image.DNG')[1], 'unsupported')


if __name__ == '__main__':
    unittest.main(verbosity=2)
