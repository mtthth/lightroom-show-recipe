return {
    LrSdkVersion = 6.0,
    LrSdkMinimumVersion = 5.0,
    LrToolkitIdentifier = 'io.github.mtthth.show-recipe',
    LrPluginName = 'show-recipe',
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
    VERSION = { major = 1, minor = 1, revision = 0 },
}
