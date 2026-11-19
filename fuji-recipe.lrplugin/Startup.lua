local LrPathUtils = import 'LrPathUtils'
-- Tracking always runs: it fills the Metadata panel of the active photo.
dofile(LrPathUtils.child(_PLUGIN.path, 'Controller.lua')).start()
