
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local hrp


local ROUTE_LINKS = {
    "https://raw.githubusercontent.com/WataXMenu/WataXSc/refs/heads/main/700.lua",
}


local routes = {}
local animConn
local isMoving = false
local frameTime = 1/30
local playbackRate = 1
local isReplayRunning = false


for i, link in ipairs(ROUTE_LINKS) do
    if link ~= "" then
        local ok, data = pcall(function()
            return loadstring(game:HttpGet(link))()
        end)
        if ok and typeof(data) == "table" and #data > 0 then
            table.insert(routes, {"Route "..i, data})
        end
    end
end
if #routes == 0 then warn("Tidak ada route valid ditemukan.") return end


local function refreshHRP(char)
    if not char then char = player.Character or player.CharacterAdded:Wait() end
    hrp = char:WaitForChild("HumanoidRootPart")
end
player.CharacterAdded:Connect(refreshHRP)
if player.Character then refreshHRP(player.Character) end


local function setupMovement(char)
    task.spawn(function()
        if not char then
            char = player.Character or player.CharacterAdded:Wait()
        end
        local humanoid = char:WaitForChild("Humanoid", 5)
        local root = char:WaitForChild("HumanoidRootPart", 5)
        if not humanoid or not root then return end

        -- ✅ Tambahan stop kalau mati + update tombol UI
        humanoid.Died:Connect(function()
            print("[WataX] Karakter mati, replay otomatis berhenti.")
            isReplayRunning = false
            stopMovement()
            isRunning = false
            if toggleBtn and toggleBtn.Parent then
                toggleBtn.Text = "▶ Start"
                toggleBtn.BackgroundColor3 = Color3.fromRGB(70,200,120)
            end
        end)

        if animConn then animConn:Disconnect() end
        local lastPos = root.Position
        local jumpCooldown = false

        animConn = RunService.RenderStepped:Connect(function()
            if not isMoving then return end

            -- otomatis perbarui HRP jika ganti karakter / respawn
            if not hrp or not hrp.Parent or not hrp:IsDescendantOf(workspace) then
                if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                    hrp = player.Character:FindFirstChild("HumanoidRootPart")
                    root = hrp
                else
                    return -- skip frame kalau belum siap
                end
            end

            if not humanoid or humanoid.Health <= 0 then return end

            local direction = root.Position - lastPos
            local dist = direction.Magnitude

            if dist > 0.01 then
                humanoid:Move(direction.Unit * math.clamp(dist * 5, 0, 1), false)
            else
                humanoid:Move(Vector3.zero, false)
            end

            local deltaY = root.Position.Y - lastPos.Y
            if deltaY > 0.9 and not jumpCooldown then
                humanoid.Jump = true
                jumpCooldown = true
                task.delay(0.4, function()
                    jumpCooldown = false
                end)
            end

            lastPos = root.Position
        end)
    end)
end

player.CharacterAdded:Connect(function(char)
    refreshHRP(char)
    setupMovement(char)
end)

if player.Character then
    refreshHRP(player.Character)
    setupMovement(player.Character)
end

local function startMovement() isMoving=true end
local function stopMovement() isMoving=false end


local DEFAULT_HEIGHT = 2.9
local function getCurrentHeight()
    local char = player.Character or player.CharacterAdded:Wait()
    local humanoid = char:WaitForChild("Humanoid")
    return humanoid.HipHeight + (char:FindFirstChild("Head") and char.Head.Size.Y or 2)
end

local function adjustRoute(frames)
    local adjusted = {}
    local offsetY = getCurrentHeight() - DEFAULT_HEIGHT
    for _,cf in ipairs(frames) do
        local pos, rot = cf.Position, cf - cf.Position
        table.insert(adjusted, CFrame.new(Vector3.new(pos.X,pos.Y+offsetY,pos.Z)) * rot)
    end
    return adjusted
end

for i, data in ipairs(routes) do
    data[2] = adjustRoute(data[2])
end

local function getNearestRoute()
    local nearestIdx, dist = 1, math.huge
    if hrp then
        local pos = hrp.Position
        for i,data in ipairs(routes) do
            for _,cf in ipairs(data[2]) do
                local d = (cf.Position - pos).Magnitude
                if d < dist then dist=d nearestIdx=i end
            end
        end
    end
    return nearestIdx
end

local function getNearestFrameIndex(frames)
    local startIdx, dist = 1, math.huge
    if hrp then
        local pos = hrp.Position
        for i,cf in ipairs(frames) do
            local d = (cf.Position - pos).Magnitude
            if d < dist then dist=d startIdx=i end
        end
    end
    if startIdx >= #frames then startIdx = math.max(1,#frames-1) end
    return startIdx
end

local function lerpCF(fromCF,toCF)
    local duration = frameTime/math.max(0.05,playbackRate)
    local t = 0
    while t < duration do
        if not isReplayRunning then break end
        local dt = task.wait()
        t += dt
        local alpha = math.min(t/duration,1)
        if hrp and hrp.Parent and hrp:IsDescendantOf(workspace) then
            hrp.CFrame = fromCF:Lerp(toCF,alpha)
        end
    end
end

local function runRoute()
    if #routes==0 then return end
    if not hrp then refreshHRP() end
    isReplayRunning = true
    startMovement()
    local idx = getNearestRoute()
    local frames = routes[idx][2]
    if #frames<2 then isReplayRunning=false return end
    local startIdx = getNearestFrameIndex(frames)
    for i=startIdx,#frames-1 do
        if not isReplayRunning then break end
        lerpCF(frames[i],frames[i+1])
    end
    isReplayRunning=false
    stopMovement()
end

local function stopRoute()
    isReplayRunning=false
    stopMovement()
end


local screenGui = Instance.new("ScreenGui")
screenGui.Name="WataXReplayUI"
screenGui.Parent=game.CoreGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 220, 0, 130) -- frame pas
frame.Position = UDim2.new(0.05,0,0.75,0)
frame.BackgroundColor3 = Color3.fromRGB(50,30,70)
frame.BackgroundTransparency = 0.3
frame.Active = true
frame.Draggable = true
frame.Parent = screenGui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0,16)

local glow = Instance.new("UIStroke")
glow.Parent = frame
glow.Color = Color3.fromRGB(180,120,255)
glow.Thickness = 2
glow.Transparency = 0.4


local title = Instance.new("TextLabel", frame)
title.Size = UDim2.new(0.75,0,0,28)
title.Position = UDim2.new(0.05,0,0,4)
title.Text = "WataX Script"
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.BackgroundTransparency = 0.3
title.BackgroundColor3 = Color3.fromRGB(70,40,120)
Instance.new("UICorner", title).CornerRadius = UDim.new(0,12)


local hue = 0
RunService.RenderStepped:Connect(function()
    hue = (hue + 0.5) % 360
    title.TextColor3 = Color3.fromHSV(hue/360,1,1)
end)


local closeBtn = Instance.new("TextButton", frame)
closeBtn.Size = UDim2.new(0,28,0,28)
closeBtn.Position = UDim2.new(0.78,0,0,4)
closeBtn.Text = "✖"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextScaled = true
closeBtn.BackgroundColor3 = Color3.fromRGB(180,60,60)
closeBtn.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,10)

local closeGlow = Instance.new("UIStroke")
closeGlow.Parent = closeBtn
closeGlow.Color = Color3.fromRGB(255,0,100)
closeGlow.Thickness = 2
closeGlow.Transparency = 0.6

closeBtn.MouseEnter:Connect(function()
    TweenService:Create(closeGlow, TweenInfo.new(0.2), {Transparency=0.1, Thickness=4}):Play()
end)
closeBtn.MouseLeave:Connect(function()
    TweenService:Create(closeGlow, TweenInfo.new(0.2), {Transparency=0.6, Thickness=2}):Play()
end)
closeBtn.MouseButton1Click:Connect(function()
    screenGui:Destroy()
end)


local toggleBtn = Instance.new("TextButton", frame)
toggleBtn.Size = UDim2.new(0.8,0,0.25,0)
toggleBtn.Position = UDim2.new(0.1,0,0.35,0)
toggleBtn.Text = "▶ Start"
toggleBtn.TextScaled = true
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.BackgroundColor3 = Color3.fromRGB(70,200,120)
toggleBtn.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,14)

local toggleGlow = Instance.new("UIStroke")
toggleGlow.Parent = toggleBtn
toggleGlow.Color = Color3.fromRGB(0,255,255)
toggleGlow.Thickness = 2
toggleGlow.Transparency = 0.5

toggleBtn.MouseEnter:Connect(function()
    TweenService:Create(toggleGlow, TweenInfo.new(0.2), {Transparency=0.1, Thickness=4}):Play()
end)
toggleBtn.MouseLeave:Connect(function()
    TweenService:Create(toggleGlow, TweenInfo.new(0.2), {Transparency=0.5, Thickness=2}):Play()
end)

local isRunning = false
toggleBtn.MouseButton1Click:Connect(function()
    if not isRunning then
        isRunning = true
        toggleBtn.Text = "■ Stop"
        task.spawn(runRoute)
    else
        isRunning = false
        toggleBtn.Text = "▶ Start"
        stopRoute()
    end
end)


local speedLabel = Instance.new("TextLabel", frame)
speedLabel.Size = UDim2.new(0.35,0,0.2,0)
speedLabel.Position = UDim2.new(0.325,0,0.7,0)
speedLabel.BackgroundTransparency = 1
speedLabel.TextColor3 = Color3.fromRGB(180,180,255)
speedLabel.Font = Enum.Font.GothamBold
speedLabel.TextScaled = true
speedLabel.Text = playbackRate.."x"

local speedDown = Instance.new("TextButton", frame)
speedDown.Size = UDim2.new(0.2,0,0.2,0)
speedDown.Position = UDim2.new(0.05,0,0.7,0)
speedDown.Text = "-"
speedDown.Font = Enum.Font.GothamBold
speedDown.TextScaled = true
speedDown.BackgroundColor3 = Color3.fromRGB(100,100,100)
speedDown.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", speedDown).CornerRadius = UDim.new(0,6)
speedDown.MouseButton1Click:Connect(function()
    playbackRate = math.max(0.25, playbackRate-0.25)
    speedLabel.Text = playbackRate.."x"
end)

local speedUp = Instance.new("TextButton", frame)
speedUp.Size = UDim2.new(0.2,0,0.2,0)
speedUp.Position = UDim2.new(0.75,0,0.7,0)
speedUp.Text = "+"
speedUp.Font = Enum.Font.GothamBold
speedUp.TextScaled = true
speedUp.BackgroundColor3 = Color3.fromRGB(100,100,150)
speedUp.TextColor3 = Color3.fromRGB(255,255,255)
Instance.new("UICorner", speedUp).CornerRadius = UDim.new(0,6)
speedUp.MouseButton1Click:Connect(function()
    playbackRate = math.min(3, playbackRate+0.25)
    speedLabel.Text = playbackRate.."x"
end)