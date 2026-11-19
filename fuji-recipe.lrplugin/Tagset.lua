-- "Appareil photo et recette" in the menu of the Metadata panel: Lightroom's own camera
-- fields, then the fields of MetadataDefinition.lua, named (LrToolkitIdentifier).(field id).
return {
    id = 'cameraRecipe',
    title = 'Appareil photo et recette',
    items = {
        'com.adobe.filename',
        'com.adobe.model',
        'com.adobe.lens',
        'com.adobe.exposure',
        'com.adobe.ISOSpeedRating',
        'com.adobe.focalLength',
        'com.adobe.dateTimeOriginal',
        'com.adobe.separator',
        { 'com.adobe.label', label = 'Réglages du boîtier' },
        'fr.matthieu.fuji-recipe.recipe',
        'fr.matthieu.fuji-recipe.settings',
        { 'fr.matthieu.fuji-recipe.details', height_in_lines = 2 },
        'fr.matthieu.fuji-recipe.note',
    },
}
