-- WaypointUI_Gamepad.lua
-- 为 WaypointUI Prompt 弹窗添加手柄操作支持
-- 架构：叠加式 GamePad 层，不修改原插件，采用 hook 方式

local ADDON_NAME = "WaypointUI_Gamepad"

-- ==================== 状态 ====================
local activePrompt = nil
local focusIndex = 1
local focusButtons = {}
local isSwitchController = false
local lastStickTime = 0
local STICK_THROTTLE = 0.15
local STICK_DEADZONE = 0.5

-- Prompt 缩放：放大确认框使其在掌机上更易操作
-- 默认 1.3x（325px * 1.3 ≈ 422px，接近原生 StaticPopup 的 420px）
local PROMPT_SCALE = 1.5

-- ==================== 工具函数 ====================
-- ConsolePort 存在性检测
local function HasConsolePort()
    return ConsolePort ~= nil and ConsolePort.db ~= nil and ConsolePort.db.UIHandle ~= nil
end

-- 检测手柄类型
local function DetectControllerType()
    isSwitchController = false
    if ConsolePort then
        if ConsolePort.GetControllerType then
            local ctrlType = ConsolePort:GetControllerType()
            isSwitchController = (ctrlType == "Switch")
        elseif ConsolePort.GetDeviceType then
            local deviceType = ConsolePort:GetDeviceType()
            isSwitchController = (deviceType == "Switch")
        end
    end
    -- 备用方案：通过 CVar 检测
    if not isSwitchController then
        local theme = GetCVar("gamepadThemeProvider")
        if theme and theme:lower():find("switch") then
            isSwitchController = true
        end
    end
end

-- 扫描活动按钮（按 element.index 排序，确保顺序与 UI 一致）
local function ScanActiveButtons(prompt)
    local list = prompt.Content and prompt.Content.ButtonContainer and prompt.Content.ButtonContainer.List
    if not list then return {} end
    local buttons = {}
    local pool = list.__elementPool
    if pool then
        for _, typePool in pairs(pool) do
            for _, element in ipairs(typePool) do
                if element.__shouldShow and element:IsShown() and element.value then
                    table.insert(buttons, element)
                end
            end
        end
    end
    -- 按 index 排序（pairs 遍历不保证顺序）
    table.sort(buttons, function(a, b)
        return (a.index or 0) < (b.index or 0)
    end)
    return buttons
end

-- ==================== CP 集成 ====================
local function AddCPHints(prompt)
    if not HasConsolePort() then return end
    local handle = ConsolePort.db.UIHandle
    if handle then
        handle:ToggleHintFocus(prompt, true)
        local confirmKey = isSwitchController and "CIRCLE" or "CROSS"
        local cancelKey = isSwitchController and "CROSS" or "CIRCLE"
        local confirmText = "确认"
        local cancelText = "取消"
        
        if #focusButtons > 0 and focusButtons[focusIndex] then
            local focusedBtn = focusButtons[focusIndex]
            if focusedBtn.value and focusedBtn.value.text then
                confirmText = focusedBtn.value.text
            end
        end
        
        handle:AddHint(confirmKey, confirmText)
        handle:AddHint(cancelKey, cancelText)
    end
end

local function UpdateCPHints()
    if not HasConsolePort() then return end
    local handle = ConsolePort.db.UIHandle
    if handle and activePrompt then
        local confirmKey = isSwitchController and "CIRCLE" or "CROSS"
        local cancelKey = isSwitchController and "CROSS" or "CIRCLE"
        local confirmText = "确认"
        local cancelText = "取消"

        if #focusButtons > 0 and focusButtons[focusIndex] then
            local focusedBtn = focusButtons[focusIndex]
            if focusedBtn.value and focusedBtn.value.text then
                confirmText = focusedBtn.value.text
            end
        end

        -- CP 没有单条更新 API，需要重置后重新添加
        handle:ResetHintBar()
        handle:AddHint(confirmKey, confirmText)
        handle:AddHint(cancelKey, cancelText)
    end
end

local function RemoveCPHints(prompt)
    if not HasConsolePort() then return end
    local handle = ConsolePort.db.UIHandle
    if handle then
        -- ToggleHintFocus(false) 内部会调用 ClearHintsForFrame + HideHintBar
        handle:ToggleHintFocus(prompt, false)
    end
end

-- ==================== 焦点导航 ====================
local function SetFocus(button)
    if button and button.OnEnter then
        button:OnEnter()
    end
end

local function ClearFocus(button)
    if button and button.OnLeave then
        button:OnLeave()
    end
end

local function FocusByDelta(delta)
    if #focusButtons == 0 then return end
    ClearFocus(focusButtons[focusIndex])
    focusIndex = focusIndex + delta
    if focusIndex < 1 then focusIndex = #focusButtons end
    if focusIndex > #focusButtons then focusIndex = 1 end
    SetFocus(focusButtons[focusIndex])
    UpdateCPHints()
end

local function ClickFocusedButton()
    local button = focusButtons[focusIndex]
    if button and button:IsEnabled() and button.value then
        -- Prompt 按钮的点击回调通过 HookMouseUp 注册（不走 OnClick），
        -- 需要直接执行 value.callback + HidePrompt，模拟 OnElementClick 行为
        if button.value.callback then
            button.value.callback()
        end
        if activePrompt then
            activePrompt:HidePrompt()
        end
    end
end

local function CancelPrompt()
    if activePrompt and activePrompt.hideOnEscape then
        activePrompt:OnEscape()
    end
end

-- ==================== 手柄输入 ====================
local function OnGamePadButtonDown(_, button)
    if not activePrompt or not activePrompt:IsShown() then return end

    local confirmButton = isSwitchController and "PAD2" or "PAD1"
    local cancelButton = isSwitchController and "PAD1" or "PAD2"

    if button == "PADDLEFT" or button == "PADDUP" then
        FocusByDelta(-1)
    elseif button == "PADDRIGHT" or button == "PADDDOWN" then
        FocusByDelta(1)
    elseif button == confirmButton then
        ClickFocusedButton()
    elseif button == cancelButton then
        CancelPrompt()
    end

    -- 阻止事件传播（非战斗时）
    if not InCombatLockdown() then
        SetPropagateKeyboardInput(false)
    end
end

local function OnGamePadStick(_, stick, x, y, len)
    if not activePrompt or not activePrompt:IsShown() then return end
    if stick ~= "LStick" then return end

    local now = GetTime()
    if now - lastStickTime < STICK_THROTTLE then return end

    -- 水平方向优先，垂直方向作为备选
    if math.abs(x) > STICK_DEADZONE then
        lastStickTime = now
        FocusByDelta(x > 0 and 1 or -1)
    elseif math.abs(y) > STICK_DEADZONE then
        lastStickTime = now
        FocusByDelta(y > 0 and -1 or 1)
    end
end

-- ==================== Hook ====================
local function OnPromptOpen(prompt, info, ...)
    if not prompt then return end
    
    activePrompt = prompt
    DetectControllerType()

    -- 延迟扫描按钮（等待 List:RenderElements 完成）
    C_Timer.After(0.05, function()
        if not activePrompt or not activePrompt:IsShown() then return end
        
        -- 清空旧数据
        for _, btn in ipairs(focusButtons) do
            ClearFocus(btn)
        end
        wipe(focusButtons)
        focusIndex = 1

        -- 扫描新按钮
        local buttons = ScanActiveButtons(activePrompt)
        for _, btn in ipairs(buttons) do
            table.insert(focusButtons, btn)
        end

        -- 设置初始焦点
        if #focusButtons > 0 then
            SetFocus(focusButtons[1])
        end

        -- 注册手柄输入（战斗外）
        if not InCombatLockdown() then
            activePrompt:SetScript("OnGamePadButtonDown", OnGamePadButtonDown)
            activePrompt:SetScript("OnGamePadStick", OnGamePadStick)
        end

        -- CP 集成
        AddCPHints(activePrompt)

        -- 放大 Prompt（掌机优化）
        activePrompt:SetScale(PROMPT_SCALE)
    end)
end

local function OnPromptHide(prompt)
    if activePrompt and activePrompt == prompt then
        -- 清理焦点
        for _, btn in ipairs(focusButtons) do
            ClearFocus(btn)
        end
        wipe(focusButtons)
        focusIndex = 1

        -- 清理手柄输入
        if not InCombatLockdown() then
            if activePrompt.SetScript then
                activePrompt:SetScript("OnGamePadButtonDown", nil)
                activePrompt:SetScript("OnGamePadStick", nil)
            end
        end

        -- CP 清理
        RemoveCPHints(activePrompt)

        -- 恢复缩放
        activePrompt:SetScale(1)
        
        activePrompt = nil
    end
end

-- ==================== 初始化 ====================
-- Dependencies: WaypointUI 保证了本插件在 WaypointUI 之后加载
-- WUISharedPrompt 在 WaypointUI 的 ADDON_LOADED 阶段就创建完毕
-- 所以在本插件的 ADDON_LOADED 时 WUISharedPrompt 已经可用

-- 战斗状态变化时重新注册/注销手柄输入
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function(_, event)
    if not activePrompt then return end
    if event == "PLAYER_REGEN_ENABLED" then
        -- 离开战斗，重新注册手柄输入
        if activePrompt:IsShown() then
            activePrompt:SetScript("OnGamePadButtonDown", OnGamePadButtonDown)
            activePrompt:SetScript("OnGamePadStick", OnGamePadStick)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- 进入战斗，注销手柄输入（战斗中 SetScript 安全但 SetPropagateKeyboardInput 不安全）
        -- 实际上 SetScript 在战斗中可用，只是 SetPropagateKeyboardInput 不行
        -- 所以保留输入注册，只在 OnGamePadButtonDown 中跳过 SetPropagateKeyboardInput
    end
end)

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" and addon == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")
        if WUISharedPrompt then
            hooksecurefunc(WUISharedPrompt, "Open", function(...) OnPromptOpen(WUISharedPrompt, ...) end)
            hooksecurefunc(WUISharedPrompt, "HidePrompt", function() OnPromptHide(WUISharedPrompt) end)
        else
            -- 极端情况：WUISharedPrompt 未就绪，等待 PLAYER_LOGIN 重试
            self:RegisterEvent("PLAYER_LOGIN")
            self:SetScript("OnEvent", function(s, e)
                s:UnregisterEvent("PLAYER_LOGIN")
                if WUISharedPrompt then
                    hooksecurefunc(WUISharedPrompt, "Open", function(...) OnPromptOpen(WUISharedPrompt, ...) end)
                    hooksecurefunc(WUISharedPrompt, "HidePrompt", function() OnPromptHide(WUISharedPrompt) end)
                end
            end)
        end
    end
end)

-- ==================== 导出供调试 ====================
_G.WaypointUI_Gamepad = {
    GetActivePrompt = function() return activePrompt end,
    GetFocusButtons = function() return focusButtons end,
    GetFocusIndex = function() return focusIndex end,
    IsSwitchController = function() return isSwitchController end,
    GetPromptScale = function() return PROMPT_SCALE end,
    SetPromptScale = function(scale) PROMPT_SCALE = scale end,
}