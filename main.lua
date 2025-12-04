-- stopwatchtimer.koplugin/main.lua
-- StopWatch & Timer for KoReader

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
local PowerD = Device.powerd  -- Global PowerD for Kindle T1 reset

local StopWatchTimerDisplay = InputContainer:extend{ props = {} }

function StopWatchTimerDisplay:init()
    self.now = os.time()
    self.paused = false
    self.mode = "stopwatch"
    self.timer_minutes = 5
    self.timer_end_time = nil
    self.pause_offset = 0
    self.alarmed = false
    self.paused_remaining = nil

    self.ges_events = {
        TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{x=0, y=0, w=Screen:getWidth(), h=Screen:getHeight()}
            }
        }
    }

    self.covers_fullscreen = true
    self.modal = true

    -- Create the large time display once
    self.time_widget = TextBoxWidget:new{
        text = "00:00",
        face = Font:getFace(self.props.time_widget.font_name or "cfont", self.props.time_widget.font_size or 220),
        width = Screen:getWidth(),
        height = math.floor(Screen:getHeight() * 0.6),
        alignment = "center",
        bold = true,
    }

    self[1] = self:render()
    UIManager:setDirty(nil, "full")
end

function StopWatchTimerDisplay:onShow()
    UIManager:setDirty(nil, "full")
    self:autoRefresh()

    -- KEEP DEVICE AWAKE – general
    if Device.powerd and Device.powerd.setSuspendTimeout then
        self.old_suspend_timeout = Device.powerd.setSuspendTimeout(math.huge)
    end

    -- Kindle-specific: periodically reset the firmware T1 timeout
    if Device:isKindle() then
        if PowerD and PowerD.resetT1Timeout then
            PowerD:resetT1Timeout()
        end
        self.kindle_t1_task = function()
            if PowerD and PowerD.resetT1Timeout then
                PowerD:resetT1Timeout()
            end
            UIManager:scheduleIn(5*60, self.kindle_t1_task)
        end
        UIManager:scheduleIn(5*60, self.kindle_t1_task)
    end

    -- Politely turn on frontlight if it was off
    if Device:hasFrontlight() and Device.powerd.fl and Device.powerd.fl.isFrontlightOff then
        if Device.powerd.fl:isFrontlightOff() then
            Device.powerd.fl:turnOn()
        end
    end
end

function StopWatchTimerDisplay:onCloseWidget()
    -- Restore original sleep timeout
    if Device.powerd and Device.powerd.setSuspendTimeout and self.old_suspend_timeout then
        Device.powerd.setSuspendTimeout(self.old_suspend_timeout)
    end

    -- Kindle-specific: unschedule T1 resets
    if self.kindle_t1_task then
        UIManager:unschedule(self.kindle_t1_task)
        self.kindle_t1_task = nil
    end

    -- Safe unschedule: only unschedule our own function
    UIManager:unschedule(self.autoRefresh)
end

function StopWatchTimerDisplay:onTapClose()
    self:onCloseWidget()
    UIManager:close(self)
end
StopWatchTimerDisplay.onAnyKeyPressed = StopWatchTimerDisplay.onTapClose

function StopWatchTimerDisplay:onSuspend()
    self:onCloseWidget()
    UIManager:close(self)
end

function StopWithTimerDisplay:onPowerOff()
    self:onCloseWidget()
    UIManager:close(self)
end

function StopWatchTimerDisplay:getTimeText()
    if self.mode == "stopwatch" then
        local elapsed = self.paused and self.pause_offset or (self.pause_offset + (os.time() - self.now))
        local _, m, s = Datetime.secondsToClock(elapsed, false, false):match("(%d+):(%d+):(%d+)")
        return T("%1:%2", m, string.format("%02d", s))
    else  -- timer mode
        if not self.timer_end_time then
            self.timer_end_time = os.time() + self.timer_minutes * 60
        end

        local remaining
        if self.paused then
            remaining = self.paused_remaining or math.max(0, self.timer_end_time - os.time())
        else
            remaining = math.max(0, self.timer_end_time - os.time())
        end

        if remaining == 0 then
            self:alarm()
            return "00:00"
        end

        local _, m, s = Datetime.secondsToClock(remaining, false, false):match("(%d+):(%d+):(%d+)")
        return T("%1:%2", m, string.format("%02d", s))
    end
end

function StopWatchTimerDisplay:alarm()
    if self.alarmed then return end
    self.alarmed = true
    UIManager:setDirty(nil, "flashui")

    -- Vibration if the device supports it (many Kobos do)
    if Device.canVibrate then Device:vibrate(500) end
end

function StopWatchTimerDisplay:update()
    local txt = self:getTimeText()
    if self.time_widget.text ~= txt then
        self.time_widget:setText(txt)
        UIManager:setDirty(self, "ui")
    end

    if self.current_mode ~= self.mode then
        self.current_mode = self.mode
        self[1] = self:render()
        UIManager:setDirty(self, "ui")
    end
end

function StopWatchTimerDisplay:autoRefresh()
    self:update()
    UIManager:scheduleIn(0.5, self.autoRefresh, self)
end

function StopWatchTimerDisplay:onTogglePause()
    self.paused = not self.paused

    if self.paused then
        if self.mode == "stopwatch" then
            self.pause_offset = self.pause_offset + (os.time() - self.now)
        else  -- timer mode
            local remaining = math.max(0, self.timer_end_time - os.time())
            self.paused_remaining = remaining
        end
    else
        if self.mode == "stopwatch" then
            self.now = os.time()
        else  -- timer mode
            if self.paused_remaining and self.paused_remaining > 0 then
                self.timer_end_time = os.time() + self.paused_remaining
                self.paused_remaining = nil
            end
        end
    end

    self[1] = self:render()
    UIManager:setDirty(self, "ui")
end

function StopWatchTimerDisplay:onRestart()
    self.now = os.time()
    self.pause_offset = 0
    self.paused = false
    self.timer_end_time = nil
    self.alarmed = false
    self.paused_remaining = nil

    self.time_widget:setText("00:00")

    self[1] = self:render()
    UIManager:setDirty(self, "flashpartial")
end

function StopWatchTimerDisplay:render()
    local s = Screen:getSize()

    local mode_btn = self.mode == "stopwatch" and _("Timer") or _("Stopwatch")
    local row = {{ text = mode_btn, callback = function() self:toggleMode() end }}

    if self.mode == "timer" then
        table.insert(row, {
            text_func = function() return self.paused and _("Resume") or _("Pause") end,
            callback = function() self:onTogglePause() end
        })
        table.insert(row, {
            text = T(_("Set Time (%1 min)"), self.timer_minutes),
            callback = function() self:setTimerMinutes() end
        })
        table.insert(row, { text = _("Restart"), callback = function() self:onRestart() end })
    else
        table.insert(row, {
            text_func = function() return self.paused and _("Resume") or _("Pause") end,
            callback = function() self:onTogglePause() end
        })
        table.insert(row, { text = _("Restart"), callback = function() self:onRestart() end })
    end

    self.buttons = ButtonTable:new{
        width = math.floor(s.w * 0.9),
        buttons = { row },
    }

    local content = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ height = math.floor(s.h * 0.15) },
        self.time_widget,
        VerticalSpan:new{ height = math.floor(s.h * 0.1) },
        self.buttons,
    }

    return FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        dimen = s,
        CenterContainer:new{ dimen = s, content },
    }
end

function StopWatchTimerDisplay:toggleMode()
    self.mode = self.mode == "stopwatch" and "timer" or "stopwatch"
    self.paused = false
    self.pause_offset = 0
    self.timer_end_time = nil
    self.alarmed = false
    self.paused_remaining = nil
    self.now = os.time()
    self[1] = self:render()
    UIManager:setDirty(nil, "full")
end

function StopWatchTimerDisplay:setTimerMinutes()
    local options = {5, 10, 15, 20, 25, 30}
    local current_idx = 1
    for i, v in ipairs(options) do
        if v == self.timer_minutes then
            current_idx = i
            break
        end
    end
    local next_idx = (current_idx % #options) + 1
    self.timer_minutes = options[next_idx]

    self.timer_end_time = os.time() + self.timer_minutes * 60
    self.alarmed = false
    self.paused = false
    self.paused_remaining = nil

    self[1] = self:render()
    UIManager:setDirty(nil, "full")
end

-- Plugin entry
local StopWatchTimer = WidgetContainer:extend{ name = "stopwatchtimer", config_file = "stopwatchtimer_config.lua" }

function StopWatchTimer:init()
    local path = DataStorage:getSettingsDir() .. "/" .. self.config_file
    self.settings = LuaSettings:open(path)
    if not self.settings.data.time_widget then
        self.settings:reset{
            time_widget = { font_name = "./fonts/noto/NotoSans-Bold.ttf", font_size = 220 },
        }
        self.settings:flush()
    end
    self.ui.menu:registerToMainMenu(self)
end

function StopWatchTimer:addToMainMenu(menu_items)
    menu_items.StopWatchTimer = {
        text = _("StopWatch / Timer"),
        sorting_hint = "more_tools",
        callback = function()
            UIManager:show(StopWatchTimerDisplay:new{ props = self.settings.data })
        end,
    }
end

return StopWatchTimer
