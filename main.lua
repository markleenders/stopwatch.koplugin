local SWDisplayWidget = require("swdisplaywidget")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local FontList = require("fontlist")
local LuaSettings = require("frontend/luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local cre -- delayed loading
local _ = require("gettext")
local T = require("ffi/util").template

local StopWatch = WidgetContainer:extend {
    name = "stopwatch",
    config_file = "stopwatch_config.lua",
    local_storage = nil,
    is_doc_only = false,
    start_time = nil,
}

function StopWatch:init()
    self:initLuaSettings()
    self.settings = self.local_storage.data
    self.ui.menu:registerToMainMenu(self)
end

function StopWatch:initLuaSettings()
    self.local_storage = LuaSettings:open(("%s/%s"):format(DataStorage:getSettingsDir(), self.config_file))
    if next(self.local_storage.data) == nil then
        self.local_storage:reset({
            time_widget = {
                font_name = "./fonts/noto/NotoSans-Regular.ttf",
                font_size = 119,
            },
        })
        self.local_storage:flush()
    end
end

function StopWatch:addToMainMenu(menu_items)
    menu_items.StopWatch = {
        text = _("Stopwatch"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Launch"),
                separator = true,
                callback = function()
                    UIManager:show(SWDisplayWidget:new { props = self.settings })
                end,
            },
            {
                text = _("Time widget font"),
                sub_item_table = self:getFontMenuList(
                    {
                        font_callback = function(font_name)
                            self:setTimeFont(font_name)
                        end,
                        font_size_callback = function(font_size)
                            self:setTimeFontSize(font_size)
                        end,
                        font_size_func = function()
                            return self.settings.time_widget.font_size
                        end,
                        checked_func = function(font)
                            return font == self.settings.time_widget.font_name
                        end
                    }
                ),
            },
        },
    }
end

function StopWatch:getFontMenuList(args)
    -- Unpack arguments
    local font_callback = args.font_callback
    local font_size_callback = args.font_size_callback
    local font_size_func = args.font_size_func
    local checked_func = args.checked_func

    -- Based on readerfont.lua
    cre = require("document/credocument"):engineInit()
    local face_list = cre.getFontFaces()
    local menu_list = {}

    -- Font size
    table.insert(menu_list, {
        text_func = function()
            return T(_("Font size: %1"), font_size_func())
        end,
        callback = function(touchmenu_instance)
            self:showFontSizeSpinWidget(touchmenu_instance, font_size_func(), font_size_callback)
        end,
        keep_menu_open = true,
        separator = true
    })

    -- Font list
    for k, v in ipairs(face_list) do
        local font_filename, font_faceindex, is_monospace = cre.getFontFaceFilenameAndFaceIndex(v)
        table.insert(menu_list, {
            text_func = function()
                -- defaults are hardcoded in credocument.lua
                local default_font = G_reader_settings:readSetting("cre_font")
                local fallback_font = G_reader_settings:readSetting("fallback_font")
                local monospace_font = G_reader_settings:readSetting("monospace_font")
                local text = v
                if font_filename and font_faceindex then
                    text = FontList:getLocalizedFontName(font_filename, font_faceindex) or text
                end

                if v == monospace_font then
                    text = text .. " \u{1F13C}" -- Squared Latin Capital Letter M
                elseif is_monospace then
                    text = text .. " \u{1D39}"  -- Modified Letter Capital M
                end
                if v == default_font then
                    text = text .. "   ★"
                end
                if v == fallback_font then
                    text = text .. "   �"
                end
                return text
            end,
            font_func = function(size)
                if G_reader_settings:nilOrTrue("font_menu_use_font_face") then
                    if font_filename and font_faceindex then
                        return Font:getFace(font_filename, size, font_faceindex)
                    end
                end
            end,
            callback = function()
                return font_callback(font_filename)
            end,
            hold_callback = function(touchmenu_instance)
            end,
            checked_func = function()
                return checked_func(font_filename)
            end,
            menu_item_id = v,
        })
    end

    return menu_list
end

function StopWatch:setTimeFont(font)
    self.settings["time_widget"]["font_name"] = font
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function StopWatch:setTimeFontSize(font_size)
    self.settings["time_widget"]["font_size"] = font_size
    self.local_storage:reset(self.settings)
    self.local_storage:flush()
end

function StopWatch:showFontSizeSpinWidget(touchmenu_instance, font_size, callback)
    -- Lazy loading the widget import
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(
        SpinWidget:new {
            value = font_size,
            value_min = 8,
            value_max = 256,
            value_step = 1,
            value_hold_step = 10,
            ok_text = _("Set font size"),
            title_text = _("Set font size"),
            callback = function(spin)
                callback(spin.value)
                touchmenu_instance:updateItems()
            end
        }
    )
end

return StopWatch
