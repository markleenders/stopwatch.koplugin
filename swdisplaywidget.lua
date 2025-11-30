local Blitbuffer = require("ffi/blitbuffer")
local Date = os.date
local Datetime = require("frontend/datetime")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require('ui/widget/container/framecontainer')
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = Device.screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")

local T = require("ffi/util").template
local _ = require("gettext")

local SWDisplayWidget = InputContainer:extend {
    props = {},
}

function SWDisplayWidget:init()
    -- Properties
    self.now = os.time()
    self.time_widget = nil
    self.datetime_vertical_group = nil
    self.autoRefresh = function()
        self:refresh()
        return UIManager:scheduleIn(.963, self.autoRefresh)
    end

    -- Events
    self.ges_events.TapClose = {
        GestureRange:new {
            ges = "tap",
            range = Geom:new {
                x = 0, y = 0,
                w = Screen:getWidth(),
                h = Screen:getHeight(),
            }
        }
    }

    -- Hints
    self.covers_fullscreen = true

    -- Render
    UIManager:setDirty("all", "flashpartial")
    self[1] = self:render()
end

function SWDisplayWidget:refresh()
    --self.now = os.time()
    self:update()
    UIManager:setDirty("all", "ui", self.datetime_vertical_group.dimen)
end

function SWDisplayWidget:onShow()
    return self:autoRefresh()
end

function SWDisplayWidget:onResume()
    UIManager:unschedule(self.autoRefresh)
end

function SWDisplayWidget:onSuspend()
    UIManager:unschedule(self.autoRefresh)
end

function SWDisplayWidget:onTapClose()
    UIManager:unschedule(self.autoRefresh)
    UIManager:close(self)
end

SWDisplayWidget.onAnyKeyPressed = SWDisplayWidget.onTapClose

function SWDisplayWidget:getTimeText(now)
    --return Datetime.secondsToClock(now, false, false)
    local delta_time = os.time() - now 
    local hour, min, sec   = Datetime.secondsToClock(delta_time, false, false):match("(%d+):(%d+):(%d+)")
    return T(_("%1:%2"), min, sec)
end

function SWDisplayWidget:update()
    local time_text = self:getTimeText(self.now)

    -- Avoid spamming repeated calls to setText
    if self.time_widget.text ~= time_text then
        self.time_widget:setText(time_text)
    end
end

function SWDisplayWidget:renderTimeWidget(now, width, font_face)
    return TextBoxWidget:new {
        text = self:getTimeText(now),
        face = font_face or Font:getFace("tfont", 119),
        width = width or Screen:getWidth(),
        alignment = "center",
        bold = true,
    }
end

function SWDisplayWidget:render()
    local screen_size = Screen:getSize()

    -- Insntiate widgets
    self.time_widget = self:renderTimeWidget(
        self.now,
        screen_size.w,
        Font:getFace(
            self.props.time_widget.font_name,
            self.props.time_widget.font_size
        )
    )

    -- Compute the widget heights and the amount of spacing we need
    -- local total_height = self.time_widget:getSize().h + self.date_widget:getSize().h + self.status_widget:getSize().h
    local total_height = self.time_widget:getSize().h 
    local spacer_height = (screen_size.h - total_height) / 2

    -- HELP: is there a better way of drawing blank space?
    local spacer_widget = TextBoxWidget:new {
        text = nil,
        face = Font:getFace("cfont"),
        width = screen_size.w,
        height = spacer_height
    }

    -- Lay out and assemble
    self.datetime_vertical_group = VerticalGroup:new {
        --self.date_widget,
        self.time_widget,
        --self.status_widget,
    }
    local vertical_group = VerticalGroup:new {
        spacer_widget,
        self.datetime_vertical_group,
        spacer_widget,
    }

    return FrameContainer:new {
        geom = Geom:new { w = screen_size.w, screen_size.h },
        radius = 0,
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOUR_WHITE,
        color = Blitbuffer.COLOUR_WHITE,
        width = screen_size.w,
        height = screen_size.h,
        vertical_group
    }
end

return SWDisplayWidget
