-- main.lua
-- Stopwatch – Updates every second, flashes only on whole minutes

local Device = require("device")
local Screen = Device.screen
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ButtonTable = require("ui/widget/buttontable")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local LuaSettings = require("frontend/luasettings")
local DataStorage = require("datastorage")
local Datetime = require("frontend/datetime")
local T = require("ffi/util").template
local _ = require("gettext")

local SWDisplayWidget = InputContainer:extend{ props = {} }

function SWDisplayWidget:init()
    self.now = os.time()
    self.paused = false
    self.pause_offset = 0
    self.last_minute = -1  -- track when we last flashed

    self.ges_events.TapClose = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        }
    }

    -- TRUE FULLSCREEN (hides absolutely everything)
    self.covers_fullscreen = true
    self.modal = true

    self[1] = self:render()
    UIManager:setDirty(nil, "full")
end

function SWDisplayWidget:onShow()
    UIManager:setDirty(nil, "full")
    self:autoRefresh()
end

function SWDisplayWidget:onTapClose()
    --mle UIManager:unscheduleAll()
    UIManager:unschedule(self.autoRefresh)
    UIManager:close(self)
end
SWDisplayWidget.onAnyKeyPressed = SWDisplayWidget.onTapClose

function SWDisplayWidget:getTimeText()
    local elapsed = self.paused and self.pause_offset or (self.pause_offset + (os.time() - self.now))
    local _, min, sec = Datetime.secondsToClock(elapsed, false, false):match("(%d+):(%d+):(%d+)")
    return T("%1:%2", min, string.format("%02d", sec))
end

function SWDisplayWidget:update()
    local txt = self:getTimeText()
    if self.time_widget.text ~= txt then
        self.time_widget:setText(txt)

        -- Extract current minute
        local elapsed = self.paused and self.pause_offset or (self.pause_offset + (os.time() - self.now))
        local current_minute = math.floor(elapsed / 60)

        -- Flash ONLY when minute changes
        if current_minute ~= self.last_minute then
            self.last_minute = current_minute
            UIManager:setDirty(self, "flashpartial")   -- full e-ink flash
        else
            UIManager:setDirty(self, "ui")        -- ghosting-free update (no flash)
        end
    end
end

-- Refresh every second, but smart flash control is in update()
function SWDisplayWidget:autoRefresh()
    self:update()
    UIManager:scheduleIn(1, function() self:autoRefresh() end)
end

function SWDisplayWidget:onTogglePause()
    self.paused = not self.paused
    if self.paused then
        self.pause_offset = self.pause_offset + (os.time() - self.now)
        self.pause_button.text = _("Resume")
    else
        self.now = os.time()
        self.pause_button.text = _("Pause")
    end
    UIManager:setDirty(self, "ui")
end

function SWDisplayWidget:onRestart()
    self.now = os.time()
    self.pause_offset = 0
    self.paused = false
    self.last_minute = -1
    self.pause_button.text = _("Pause")
    self.time_widget:setText("00:00")
    UIManager:setDirty(self, "flashpartial")
end

function SWDisplayWidget:render()
    local s = Screen:getSize()

    -- Huge timer (will be perfectly centered by CenterContainer)
    self.time_widget = TextBoxWidget:new{
        text = "00:00",
        face = Font:getFace(self.props.time_widget.font_name or "cfont", self.props.time_widget.font_size or 220),
        width = s.w,
        height = math.floor(s.h * 0.6),
        alignment = "center",
        bold = true,
    }

    -- Buttons
    self.pause_button = { text = _("Pause") }
    local buttons = ButtonTable:new{
        width = math.floor(s.w * 0.9),
        buttons = {{
            { text_func = function() return self.pause_button.text end,
              callback = function() self:onTogglePause() end },
            { text = _("Restart"), callback = function() self:onRestart() end },
        }},
    }

    local content = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ height = math.floor(s.h * 0.15) },
        self.time_widget,
        VerticalSpan:new{ height = math.floor(s.h * 0.12) },
        buttons,
    }

    return FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        dimen = s,
        CenterContainer:new{ dimen = s, content },
    }
end

-- Plugin entry
local StopWatch = WidgetContainer:extend{
    name = "stopwatch",
    config_file = "stopwatch_config.lua",
}

function StopWatch:init()
    local path = DataStorage:getSettingsDir() .. "/" .. self.config_file
    self.settings = LuaSettings:open(path)
    if not self.settings.data.time_widget then
        self.settings:reset({
            time_widget = {
                font_name = "./fonts/noto/NotoSans-Bold.ttf",
                font_size = 220,
            },
        })
        self.settings:flush()
    end
    self.ui.menu:registerToMainMenu(self)
end

function StopWatch:addToMainMenu(menu_items)
    menu_items.StopWatch = {
        text = _("StopWatch"),
        sorting_hint = "more_tools",
        callback = function()
            UIManager:show(SWDisplayWidget:new{ props = self.settings.data })
        end,
    }
end

return StopWatch
