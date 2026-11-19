# Fuji Recipe for Lightroom Classic

*[Version française](README.fr.md)*

A Lightroom Classic plug-in that shows the in-camera settings of the active photo in the
Library's **Metadata panel**, and recognizes the **Fujifilm film simulation recipe** it was
shot with.

The camera does not record a recipe's name. The plug-in reads the settings stored in the
file (film simulation, dynamic range, white balance and shift, highlight, shadow, colour,
grain, Color Chrome, sharpness, noise reduction, clarity) and compares them with a CSV of
recipes. 28 recipes are included, most of them from [Fuji X Weekly](https://fujixweekly.com/);
you can use your own file instead.

Panasonic, Canon, iPhone and Ricoh GR settings are read too.

> The plug-in's interface is in French for now: *Recette* = recipe, *Réglages* = settings,
> *Détails* = details, *Remarque* = note.

## Installation

1. Download `fuji-recipe.lrplugin.zip` from the
   [latest release](https://github.com/mtthth/lightroom-show-recipe/releases/latest) and unzip it.
2. Lightroom Classic → File → **Plug-in Manager** → **Add**, and choose the
   `fuji-recipe.lrplugin` folder.
3. In the Library, open the menu at the top of the Metadata panel and choose
   **Appareil photo et recette**.

To update, replace the folder and click **Reload Plug-in** in the Plug-in Manager.

## The Metadata panel

The **Appareil photo et recette** preset shows Lightroom's own fields (file name, model,
lens, exposure, ISO, focal length, date), followed by four fields of the plug-in:

- **Recette**: the recipe name, or *Recette non identifiée* (no recipe recognized).
- **Réglages**: on Fuji, film simulation, dynamic range or DR priority and white balance,
  then highlight, shadow, colour and sharpness. On Panasonic and Canon: photo style, white
  balance, shooting mode and adjustments. On iPhone: the mode; on Ricoh: white balance
  and mode.
- **Détails**: the recipe's source, or the closest recipe and what differs; grain, Color
  Chrome, noise reduction, clarity…
- **Remarque**: the settings were read from the companion RAF, or why they could not be read.

Fields are filled when a photo becomes the active photo. To fill a whole folder or
collection at once, select the photos and choose Library → Plug-in Extras →
**Renseigner le panneau Métadonnées pour la sélection…** (with no selection, the whole
filmstrip). **Recette** and **Réglages** can then be used in smart collections and text
search, and **Recette** appears in the Library Filter's Metadata columns.

## Recipes

A recipe is recognized when every setting given in the CSV is equal. An empty cell is not
compared. A recipe that differs **only by its dynamic range** (DR100/200/400/Auto) is still
recognized; *Détails* then says which DR the photo used. When no recipe matches,
*Détails* names the closest one (at most three differences) and the settings that differ.

### Using your own recipes

In the Plug-in Manager, the **Recettes Fuji** section shows the recipe file in use, how many
recipes it holds and any lines left out (with the reason):

- **Copier les recettes fournies…** saves an editable copy of the included recipes and uses it.
- **Choisir un fichier CSV…** uses another CSV.
- **Recettes fournies** goes back to the included recipes.

Edits to the file apply to the photos read next, without reloading the plug-in. To update
photos already read, run the selection command above again.

### CSV format

UTF-8, comma-separated, one recipe per line, with this header (extra columns are ignored):

| Column | Values |
|---|---|
| `nom` | Recipe name (required, unique) |
| `film_simulation` | `Provia/Standard`, `Velvia/Vivid`, `Astia/Soft`, `Classic Chrome`, `Reala Ace`, `PRO Neg. Hi`, `PRO Neg. Std`, `Classic Negative`, `Nostalgic Negative`, `Eterna/Cinema`, `Eterna Bleach Bypass`, `Acros`, `Acros+Ye`, `Acros+R`, `Acros+G`, `Monochrome`, `Monochrome+Ye`, `Monochrome+R`, `Monochrome+G`, `Sepia` |
| `dynamic_range` | `DR100`, `DR200`, `DR400`, `Auto`, or empty (must be empty with DR priority) |
| `dr_priority` | `Off`, `Weak`, `Strong` (required) |
| `white_balance` | `Auto`, `Auto (White Priority)`, `Auto (Ambience Priority)`, `Daylight`, `Shade`, `Fluorescent 1`, `Fluorescent 2`, `Fluorescent 3`, `Incandescent`, `Underwater`, or a temperature such as `5500K` |
| `wb_shift_red`, `wb_shift_blue` | Numbers |
| `highlight`, `shadow`, `color` | Numbers (half steps allowed, e.g. `-1.5`); leave `color` empty for black and white |
| `grain_effect` | `Off`, `Weak`, `Strong` (required) |
| `grain_size` | `Small`, `Large`, or empty |
| `color_chrome_effect`, `color_chrome_fx_blue` | `Off`, `Weak`, `Strong` (required) |
| `sharpness`, `high_iso_nr`, `clarity` | Numbers |
| `source` | Shown in *Détails* |

The columns `mono_color_wc`, `mono_color_mg`, `iso_max`, `exposure_comp`, `usage` and
`notes` are kept for reference and not compared.

## How it works, and limits

- Nothing is written to the photos, their XMP or Lightroom's standard metadata. The plug-in
  only writes its four fields to the catalog, through the access reserved for plug-ins: no
  undo history entry, nothing in XMP or exports. A field is written only when its value
  changes. The fields stay in the catalog if the plug-in is removed.
- **Fuji**: EXIF/MakerNotes of JPEG files and of the JPEG preview in RAF files. If a JPEG has
  lost its MakerNotes, the RAF with the same name in the same folder is read instead. A RAF
  photo gets its settings but no recipe: a raw file is not rendered with them, only the
  camera's JPEG is. White
  balance shifts are validated on the X-T5; other generations still need checking.
  Monochrome WC/MG are not compared.
- **Panasonic**: JPEG only (RW2 is not read). **Canon**: JPEG only (CR2/CR3 are not read).
- **iPhone and Ricoh**: JPEG only; the shooting mode comes from standard EXIF when the
  camera writes it. HEIC is not read.
- Nikon, Sony and other brands are not read yet.
- An offline original keeps the values read earlier; it is retried every 5 seconds while it
  stays active. A busy catalog is retried on the next check.
- `?` means a setting that is missing or not recognized; no default value is made up.
- A recipe describes the camera settings at capture, not how Lightroom renders the raw file.

References: [Fujifilm tags](https://exiftool.org/TagNames/FujiFilm.html),
[Fuji presets in Exiv2](https://github.com/Exiv2/exiv2/blob/main/src/fujimn_int.cpp),
[Panasonic tags](https://exiftool.org/TagNames/Panasonic.html),
[Canon tags](https://exiftool.org/TagNames/Canon.html).

## Tests

The tests run the plug-in's Lua 5.1 code through [Lupa](https://github.com/scoder/lupa) on
generated sample files; no real photo is needed.

```powershell
python -m pip install --target .test-deps lupa
python -m unittest discover -s tests -p "test_*.py"
```

## Licence

[MIT](LICENSE). Recipe settings are credited to their authors in the `source` column of
[recipes.csv](fuji-recipe.lrplugin/recipes.csv).
