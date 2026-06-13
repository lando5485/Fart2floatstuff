-- ============================================================================================
-- MOVED. The black hole VISUAL is now built inside src/client/WorldClient.client.lua (function
-- buildBlackHole, called from its "Spawn world objects" task). This standalone file was never synced
-- by Rojo (its default.project.json entry has been removed), so it never ran -- which is exactly why
-- the black hole never appeared. It now lives in WorldClient, an already-mapped script that reliably
-- executes. This file is intentionally a no-op stub so nothing here can create a DUPLICATE black hole.
-- Do not re-map this file; edit the black hole in WorldClient.client.lua instead.
-- ============================================================================================
return
