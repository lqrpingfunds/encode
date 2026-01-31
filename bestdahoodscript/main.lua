if SCRIPT_KEY ~= "ccgGYb2ybCApBpnj" then return end

local ESP_TOGGLE_KEY = Enum.KeyCode.C
local SILENT_AIM_TOGGLE_KEY = Enum.KeyCode.V
local MAX_DISTANCE = 5000
local FOV_CIRCLE_RADIUS = 160

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local ESP_ENABLED = false
local SILENT_AIM_ENABLED = false
local ESP_CACHE = {}
local TARGET_PLAYER = nil
local TARGET_LOCKED = false

local FOV_CIRCLE = nil
local AIM_LINE = nil
local TARGET_INDICATOR = nil

local COLOR = Color3.fromRGB(255, 255, 255)

local EspSettings = {
    Boxes = {
        Enabled = true,
        Transparency = 1,
        Color = Color3.fromRGB(255, 255, 255),
        Outline = true,
        OutlineColor = Color3.fromRGB(0, 0, 0),
        OutlineThickness = 1,
        Thickness = 1
    },
    Skeletons = {
        Enabled = true,
        Transparency = 1,
        Color = Color3.fromRGB(255, 255, 255),
        Outline = true,
        OutlineColor = Color3.fromRGB(0, 0, 0),
        OutlineThickness = 1,
        Thickness = 1
    }
}

local SilentAimSettings = {
    FOV = {
        Visible = true,
        Color = Color3.fromRGB(255, 0, 0),
        Transparency = 0.3,
        Thickness = 2,
        Filled = false
    },
    AimLine = {
        Color = Color3.fromRGB(0, 255, 0),
        Thickness = 2,
        Transparency = 1
    },
    Target = {
        Color = Color3.fromRGB(255, 0, 0),
        Thickness = 3,
        Transparency = 1
    },
    HitPart = "Head",  
    Smoothness = 0.5,
    UseFOV = true   
}

local function initializeSilentAimDrawings()
    FOV_CIRCLE = Drawing.new("Circle")
    FOV_CIRCLE.Visible = false
    FOV_CIRCLE.Color = SilentAimSettings.FOV.Color
    FOV_CIRCLE.Transparency = SilentAimSettings.FOV.Transparency
    FOV_CIRCLE.Thickness = SilentAimSettings.FOV.Thickness
    FOV_CIRCLE.Filled = SilentAimSettings.FOV.Filled
    FOV_CIRCLE.Radius = FOV_CIRCLE_RADIUS

    AIM_LINE = Drawing.new("Line")
    AIM_LINE.Visible = false
    AIM_LINE.Color = SilentAimSettings.AimLine.Color
    AIM_LINE.Thickness = SilentAimSettings.AimLine.Thickness
    AIM_LINE.Transparency = SilentAimSettings.AimLine.Transparency

    TARGET_INDICATOR = Drawing.new("Circle")
    TARGET_INDICATOR.Visible = false
    TARGET_INDICATOR.Color = SilentAimSettings.Target.Color
    TARGET_INDICATOR.Thickness = SilentAimSettings.Target.Thickness
    TARGET_INDICATOR.Transparency = SilentAimSettings.Target.Transparency
    TARGET_INDICATOR.Radius = 8
    TARGET_INDICATOR.Filled = false
end

initializeSilentAimDrawings()

local function newLine()
    local l = Drawing.new("Line")
    l.Color = EspSettings.Skeletons.Color
    l.Thickness = EspSettings.Skeletons.Thickness
    l.Visible = false
    l.Transparency = EspSettings.Skeletons.Transparency
    
    if EspSettings.Skeletons.Outline then
        local outlines = {}
        local outlineCount = math.ceil(EspSettings.Skeletons.OutlineThickness)
        
        for i = 1, outlineCount do
            local outline = Drawing.new("Line")
            outline.Color = EspSettings.Skeletons.OutlineColor
            outline.Thickness = l.Thickness
            outline.Visible = false
            outline.Transparency = l.Transparency
            table.insert(outlines, outline)
        end
        
        return {Main = l, Outlines = outlines}
    end
    
    return {Main = l, Outlines = {}}
end

local function updateLine(lineData, from, to)
    if not lineData or not lineData.Main then return end
    
    if from and to then
        lineData.Main.From = from
        lineData.Main.To = to
        lineData.Main.Visible = ESP_ENABLED and EspSettings.Skeletons.Enabled
        
        if EspSettings.Skeletons.Outline and #lineData.Outlines > 0 then
            local offset = EspSettings.Skeletons.OutlineThickness
            
            for i, outline in ipairs(lineData.Outlines) do
                local offsetX = offset * (i / #lineData.Outlines)
                local offsetY = offset * (i / #lineData.Outlines)
                
                outline.From = Vector2.new(from.X + offsetX, from.Y + offsetY)
                outline.To = Vector2.new(to.X + offsetX, to.Y + offsetY)
                outline.Visible = ESP_ENABLED and EspSettings.Skeletons.Enabled
            end
        end
    else
        lineData.Main.Visible = false
        for _, outline in ipairs(lineData.Outlines) do
            outline.Visible = false
        end
    end
end

local function drawBoxOutline(box, position, size)
    if not EspSettings.Boxes.Outline then return {} end
    
    local outlineThickness = EspSettings.Boxes.OutlineThickness
    local outlines = {}
    
    for i = 1, outlineThickness do
        local outlineBox = Drawing.new("Square")
        outlineBox.Filled = false
        outlineBox.Thickness = EspSettings.Boxes.Thickness
        outlineBox.Color = EspSettings.Boxes.OutlineColor
        outlineBox.Transparency = EspSettings.Boxes.Transparency
        outlineBox.Visible = box.Visible
        
        local offset = i
        outlineBox.Position = Vector2.new(position.X - offset, position.Y - offset)
        outlineBox.Size = Vector2.new(size.X + (offset * 2), size.Y + (offset * 2))
        
        table.insert(outlines, outlineBox)
    end
    
    return outlines
end

local function getClosestPlayerToCursor()
    local closestPlayer = nil
    local closestDistance = math.huge
    local mousePos = Vector2.new(Mouse.X, Mouse.Y)
    
    for _, player in pairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        
        local character = player.Character
        if not character then continue end
        
        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid or humanoid.Health <= 0 then continue end
        
        local hitPart = character:FindFirstChild(SilentAimSettings.HitPart)
        if not hitPart then
            hitPart = character:FindFirstChild("HumanoidRootPart")
        end
        if not hitPart then continue end
        
        local screenPoint, onScreen = Camera:WorldToViewportPoint(hitPart.Position)
        if not onScreen then continue end
        
        local playerPos = Vector2.new(screenPoint.X, screenPoint.Y)
        local distance = (mousePos - playerPos).Magnitude

        if SilentAimSettings.UseFOV and distance > FOV_CIRCLE_RADIUS then
            continue
        end

        if (Camera.CFrame.Position - hitPart.Position).Magnitude > MAX_DISTANCE then
            continue
        end
        
        if distance < closestDistance then
            closestDistance = distance
            closestPlayer = player
        end
    end
    
    return closestPlayer, closestDistance
end

local function updateSilentAimVisuals()
    if not SILENT_AIM_ENABLED then
        FOV_CIRCLE.Visible = false
        AIM_LINE.Visible = false
        TARGET_INDICATOR.Visible = false
        TARGET_PLAYER = nil
        TARGET_LOCKED = false
        return
    end

    FOV_CIRCLE.Position = Vector2.new(Mouse.X, Mouse.Y)
    FOV_CIRCLE.Visible = SilentAimSettings.FOV.Visible

    local closestPlayer, closestDistance = getClosestPlayerToCursor()
    
    if closestPlayer and closestPlayer.Character then
        local hitPart = closestPlayer.Character:FindFirstChild(SilentAimSettings.HitPart) or 
                       closestPlayer.Character:FindFirstChild("HumanoidRootPart")
        
        if hitPart then
            local screenPoint, onScreen = Camera:WorldToViewportPoint(hitPart.Position)
            
            if onScreen then
                local targetPos = Vector2.new(screenPoint.X, screenPoint.Y)
                local mousePos = Vector2.new(Mouse.X, Mouse.Y)

                AIM_LINE.From = mousePos
                AIM_LINE.To = targetPos
                AIM_LINE.Visible = true
                
                TARGET_INDICATOR.Position = targetPos
                TARGET_INDICATOR.Visible = true
                
                TARGET_PLAYER = closestPlayer
                TARGET_LOCKED = true
            else
                AIM_LINE.Visible = false
                TARGET_INDICATOR.Visible = false
                TARGET_LOCKED = false
            end
        end
    else
        AIM_LINE.Visible = false
        TARGET_INDICATOR.Visible = false
        TARGET_PLAYER = nil
        TARGET_LOCKED = false
    end
end

local function createESP(player)
    if player == LocalPlayer then return end

    local box = Drawing.new("Square")
    box.Filled = false
    box.Thickness = EspSettings.Boxes.Thickness
    box.Color = EspSettings.Boxes.Color
    box.Transparency = EspSettings.Boxes.Transparency
    box.Visible = false
    
    local boxOutlines = {}

    local skeleton = {
        Head = newLine(),
        Spine = newLine(),
        LA = newLine(),
        RA = newLine(),
        LL = newLine(),
        RL = newLine()
    }

    ESP_CACHE[player] = {
        Box = box, 
        BoxOutlines = boxOutlines,
        Skeleton = skeleton
    }
end

local function removeESP(player)
    local esp = ESP_CACHE[player]
    if not esp then return end
    
    esp.Box:Remove()
    for _, outline in ipairs(esp.BoxOutlines) do
        outline:Remove()
    end
    
    for boneName, lineData in pairs(esp.Skeleton) do
        lineData.Main:Remove()
        for _, outline in ipairs(lineData.Outlines) do
            outline:Remove()
        end
    end
    
    ESP_CACHE[player] = nil

    if player == TARGET_PLAYER then
        TARGET_PLAYER = nil
        TARGET_LOCKED = false
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    createESP(p)
end

Players.PlayerAdded:Connect(createESP)
Players.PlayerRemoving:Connect(removeESP)

RunService.RenderStepped:Connect(function()
    for player, esp in pairs(ESP_CACHE) do
        local char = player.Character
        local hum = char and char:FindFirstChild("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        if not ESP_ENABLED or not hum or hum.Health <= 0 or not hrp then
            esp.Box.Visible = false
            for _, outline in ipairs(esp.BoxOutlines) do
                outline.Visible = false
            end
            for boneName, lineData in pairs(esp.Skeleton) do
                updateLine(lineData)
            end
            continue
        end

        if (Camera.CFrame.Position - hrp.Position).Magnitude > MAX_DISTANCE then
            esp.Box.Visible = false
            for _, outline in ipairs(esp.BoxOutlines) do
                outline.Visible = false
            end
            for boneName, lineData in pairs(esp.Skeleton) do
                updateLine(lineData)
            end
            continue
        end

        local cf, size = char:GetBoundingBox()
        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        local onScreen = false

        for x = -1, 1, 2 do
            for y = -1, 1, 2 do
                for z = -1, 1, 2 do
                    local point = cf * Vector3.new(size.X / 2 * x, size.Y / 2 * y, size.Z / 2 * z)
                    local screenPoint, visible = Camera:WorldToViewportPoint(point)
                    
                    if visible then
                        onScreen = true
                        minX = math.min(minX, screenPoint.X)
                        minY = math.min(minY, screenPoint.Y)
                        maxX = math.max(maxX, screenPoint.X)
                        maxY = math.max(maxY, screenPoint.Y)
                    end
                end
            end
        end

        if not onScreen then
            esp.Box.Visible = false
            for _, outline in ipairs(esp.BoxOutlines) do
                outline.Visible = false
            end
            for boneName, lineData in pairs(esp.Skeleton) do
                updateLine(lineData)
            end
            continue
        end

        local boxPos = Vector2.new(minX, minY)
        local boxSize = Vector2.new(maxX - minX, maxY - minY)
        
        esp.Box.Visible = ESP_ENABLED and EspSettings.Boxes.Enabled
        esp.Box.Position = boxPos
        esp.Box.Size = boxSize

        for _, outline in ipairs(esp.BoxOutlines) do
            outline:Remove()
        end

        esp.BoxOutlines = drawBoxOutline(esp.Box, boxPos, boxSize)

        local function vp(part)
            if not part then return nil end
            local screenPoint, visible = Camera:WorldToViewportPoint(part.Position)
            if visible then
                return Vector2.new(screenPoint.X, screenPoint.Y)
            end
            return nil
        end

        local head = vp(char:FindFirstChild("Head"))
        local torso = vp(hrp)
        local lua = vp(char:FindFirstChild("LeftUpperArm"))
        local rua = vp(char:FindFirstChild("RightUpperArm"))
        local lul = vp(char:FindFirstChild("LeftUpperLeg"))
        local rul = vp(char:FindFirstChild("RightUpperLeg"))

        if head and torso then updateLine(esp.Skeleton.Head, head, torso) end
        if torso then updateLine(esp.Skeleton.Spine, torso, torso + Vector2.new(0, 15)) end
        if torso and lua then updateLine(esp.Skeleton.LA, torso, lua) end
        if torso and rua then updateLine(esp.Skeleton.RA, torso, rua) end
        if torso and lul then updateLine(esp.Skeleton.LL, torso, lul) end
        if torso and rul then updateLine(esp.Skeleton.RL, torso, rul) end
    end

    updateSilentAimVisuals()
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end

    if input.KeyCode == ESP_TOGGLE_KEY then
        ESP_ENABLED = not ESP_ENABLED
        print("[ESP]", ESP_ENABLED and "ON" or "OFF")

        if not ESP_ENABLED then
            for _, esp in pairs(ESP_CACHE) do
                esp.Box.Visible = false
                for _, outline in ipairs(esp.BoxOutlines) do
                    outline.Visible = false
                end
                for boneName, lineData in pairs(esp.Skeleton) do
                    updateLine(lineData)
                end
            end
        end

    elseif input.KeyCode == SILENT_AIM_TOGGLE_KEY then
        SILENT_AIM_ENABLED = not SILENT_AIM_ENABLED
        print("[SILENT AIM]", SILENT_AIM_ENABLED and "ON" or "OFF")
        
        if not SILENT_AIM_ENABLED then
            FOV_CIRCLE.Visible = false
            AIM_LINE.Visible = false
            TARGET_INDICATOR.Visible = false
            TARGET_PLAYER = nil
            TARGET_LOCKED = false
        end
    end
end)

local function updateSkeletonSettings()
    for _, esp in pairs(ESP_CACHE) do
        for boneName, lineData in pairs(esp.Skeleton) do
            lineData.Main.Color = EspSettings.Skeletons.Color
            lineData.Main.Thickness = EspSettings.Skeletons.Thickness
            lineData.Main.Transparency = EspSettings.Skeletons.Transparency
            
            for _, outline in ipairs(lineData.Outlines) do
                outline.Color = EspSettings.Skeletons.OutlineColor
                outline.Thickness = EspSettings.Skeletons.Thickness
                outline.Transparency = EspSettings.Skeletons.Transparency
            end
        end
    end
end

local function updateBoxSettings()
    for _, esp in pairs(ESP_CACHE) do
        esp.Box.Color = EspSettings.Boxes.Color
        esp.Box.Thickness = EspSettings.Boxes.Thickness
        esp.Box.Transparency = EspSettings.Boxes.Transparency
    end
end

local function getTargetPlayer()
    return TARGET_PLAYER
end

local function getTargetLocked()
    return TARGET_LOCKED
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then

        for _, esp in pairs(ESP_CACHE) do
            removeESP(esp)
        end
        
        if FOV_CIRCLE then FOV_CIRCLE:Remove() end
        if AIM_LINE then AIM_LINE:Remove() end
        if TARGET_INDICATOR then TARGET_INDICATOR:Remove() end
    end
end)
