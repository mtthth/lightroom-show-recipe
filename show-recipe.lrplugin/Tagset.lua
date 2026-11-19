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
        'io.github.mtthth.show-recipe.recipe',
        'io.github.mtthth.show-recipe.source',
        'io.github.mtthth.show-recipe.settings',
        'io.github.mtthth.show-recipe.adjustments',
        'io.github.mtthth.show-recipe.effects',
        'io.github.mtthth.show-recipe.noise',
        'io.github.mtthth.show-recipe.note',
    },
}
