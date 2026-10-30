local frame = 0
local function onEndFrame()
    frame = frame + 1
    if frame == 70 then
        local png = emu.takeScreenshot()
        local f = assert(io.open('/tmp/retro_splash_check.png', 'wb'))
        f:write(png)
        f:close()
        emu.stop(0)
    end
end
emu.addEventCallback(onEndFrame, emu.eventType.endFrame)
