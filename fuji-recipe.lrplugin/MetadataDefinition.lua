-- Fields of the Metadata panel, filled by Controller.lua from the settings read in the file.
-- They live in the catalog only: no XMP, no export, nothing written to the photos.
-- Increment schemaVersion after any change below; never lower it.
return {
    metadataFieldsForPhotos = {
        { id = 'recipe', title = 'Recette', dataType = 'string', readOnly = true,
            searchable = true, browsable = true },
        { id = 'settings', title = 'Réglages', dataType = 'string', readOnly = true, searchable = true },
        { id = 'details', title = 'Détails', dataType = 'string', readOnly = true },
        { id = 'note', title = 'Remarque', dataType = 'string', readOnly = true },
    },
    schemaVersion = 1,
}
