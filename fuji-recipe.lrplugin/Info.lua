return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 5.0,
    LrToolkitIdentifier = 'fr.matthieu.fuji-recipe',
    LrPluginName = 'Appareil photo et recette Fuji',
    LrForceInitPlugin = true,
    LrInitPlugin = 'Startup.lua',
    LrEnablePlugin = 'Startup.lua',
    LrMetadataProvider = 'MetadataDefinition.lua',
    LrMetadataTagsetFactory = 'Tagset.lua',

    LrPluginInfoProvider = 'PluginInfoProvider.lua',
    LrLibraryMenuItems = {
        { title = 'Renseigner le panneau Métadonnées pour la sélection…', file = 'FillRecipes.lua' },
    },
    LrShutdownPlugin = 'Shutdown.lua',
    LrDisablePlugin = 'Shutdown.lua',
    VERSION = { major = 0, minor = 12, revision = 1 },
}
