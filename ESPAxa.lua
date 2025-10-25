--===[ LocalScript di StarterPlayerScripts — UI + ShiftRun RUN + ESP Tab ]===--

-- ======================================================
-- SERVICES
-- ======================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ======================================================
-- KONFIGURASI ShiftRun
-- ======================================================
local ID = 10862419793      -- Animation ID
local RunningSpeed = 40
local NormalSpeed = 25
local RunFOV = 80
local NormalFOV = 70
local key = "LeftShift"
local ACTION_NAME = "RunBind"

-- STATE ShiftRun
local sprintEnabled = true
local Running = false
local Humanoid
local RAnimation
local T, rT
local HeartbeatConn

-- ======================================================
-- GUI Variabel
-- ======================================================
local toggleBtn
local mainFrame
local notifyBar
local footerFrame
local joinLabel
local leaveLabel
local ScreenGui
local afkLabel
local createdLabel

local AFKStart = {}
local WasAFK = {}
local ActiveResetDelay = 5

-- Sound
local joinSound, leaveSound

-- Data tambahan Player List
local playerRows = {} -- [Player] = {frame=Frame, dist=TextLabel}
local AFKTimers = {}

-- ======================================================
-- KONFIGURASI ESP
-- ======================================================
local ESP = {}
ESP.SETTINGS = {
	Enabled = false,
	ShowNames = true,
	ShowDistance = true,
	ShowLines = false,
	UseMeters = true,        -- 1 stud ~ 0.28 m
	LineThickness = 2,
	Font = Enum.Font.GothamMedium,
	TextSize = 14,
	MaxDrawDistance = 3000,
	RefreshRate = 1/60,
	LabelYOffset = 2.2,
}
ESP.STUDS_TO_M = 0.28

ESP.espByPlayer = {}
ESP.listEntries = {}
ESP.trackedPlayers = {}
ESP.connections = {}
ESP.lastUpdate = 0
ESP.isMinimized = false

ESP.LinesLayer = nil
ESP.ESPPage = nil
ESP.Controls = nil
ESP.SearchBox = nil
ESP.ListHolder = nil
ESP.UIList = nil
ESP.BtnAll = nil
ESP.BtnClear = nil
ESP.CountLabel = nil
ESP.BtnESPMaster = nil

-- ======================================================
-- UTIL UMUM
-- ======================================================
local function ensureTweens()
    local inInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
    local outInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
    T   = TweenService:Create(camera, inInfo,  {FieldOfView = RunFOV})
    rT  = TweenService:Create(camera, outInfo, {FieldOfView = NormalFOV})
end

local function safeCharParts(character)
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	if not (hrp and head) then return end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	return hrp, head, hum
end

-- NEW: helper posisi yang robust (HRP → PrimaryPart → GetPivot)
local function getCharPosition(char: Model?)
	if not char then return nil end
	-- coba HRP
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	-- coba PrimaryPart
	if char.PrimaryPart then
		return char.PrimaryPart.Position
	end
	-- fallback pivot (aman walau streaming)
	local ok, cframe = pcall(function() return char:GetPivot() end)
	if ok and typeof(cframe) == "CFrame" then
		return cframe.Position
	end
	return nil
end

-- ======================================================
-- SHIFT RUN
-- ======================================================
local function applyWalk()
    if Humanoid then Humanoid.WalkSpeed = NormalSpeed end
    if RAnimation and RAnimation.IsPlaying then pcall(function() RAnimation:Stop() end) end
    if rT then rT:Play() end
end

local function applyRun()
    if Humanoid then Humanoid.WalkSpeed = RunningSpeed end
    if RAnimation and not RAnimation.IsPlaying then pcall(function() RAnimation:Play() end) end
    if T then T:Play() end
end

local function setSprintEnabled(newVal, runBtn)
    sprintEnabled = newVal and true or false
    if runBtn then runBtn.Text = sprintEnabled and "RUN: ON" or "RUN: OFF" end

    if not Humanoid then return end
    if not sprintEnabled then
        Running = false
        applyWalk()
    else
        local keyEnum = Enum.KeyCode[key] or Enum.KeyCode.LeftShift
        local holding = UserInputService:IsKeyDown(keyEnum)
        if holding and Humanoid.MoveDirection.Magnitude > 0 then
            Running = true
            applyRun()
        else
            Running = false
            applyWalk()
        end
    end
end

local function bindShiftAction()
    local keyEnum = Enum.KeyCode[key] or Enum.KeyCode.LeftShift
    pcall(function() ContextActionService:UnbindAction(ACTION_NAME) end)
    ContextActionService:BindAction(ACTION_NAME, function(BindName, InputState)
        if BindName ~= ACTION_NAME then return end
        if InputState == Enum.UserInputState.Begin then
            Running = true
        elseif InputState == Enum.UserInputState.End then
            Running = false
        end

        if not sprintEnabled then
            applyWalk()
            return
        end

        if Running then
            applyRun()
        else
            applyWalk()
        end
    end, true, keyEnum)
end

local function startHeartbeatEnforcement()
    if HeartbeatConn then HeartbeatConn:Disconnect() HeartbeatConn = nil end
    HeartbeatConn = RunService.Heartbeat:Connect(function()
        if not Humanoid then return end
        if not sprintEnabled then
            if Humanoid.WalkSpeed ~= NormalSpeed or (RAnimation and RAnimation.IsPlaying) or camera.FieldOfView ~= NormalFOV then
                applyWalk()
            end
        else
            if Running then
                if Humanoid.WalkSpeed ~= RunningSpeed or (RAnimation and not RAnimation.IsPlaying) or camera.FieldOfView ~= RunFOV then
                    applyRun()
                end
            else
                if Humanoid.WalkSpeed ~= NormalSpeed or (RAnimation and RAnimation.IsPlaying) or camera.FieldOfView ~= NormalFOV then
                    applyWalk()
                end
            end
        end
    end)
end

local function attachCharacter(char)
    Humanoid = char:WaitForChild("Humanoid", 5)
    if not Humanoid then return end

    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://"..ID
    local ok, track = pcall(function() return Humanoid:LoadAnimation(anim) end)
    if ok then RAnimation = track end

    ensureTweens()
    camera.FieldOfView = NormalFOV
    Humanoid.WalkSpeed = NormalSpeed

    Humanoid.Running:Connect(function(Speed)
        if not sprintEnabled then
            applyWalk()
            return
        end
        if Speed >= 10 and Running and RAnimation and not RAnimation.IsPlaying then
            applyRun()
        elseif Speed >= 10 and (not Running) and RAnimation and RAnimation.IsPlaying then
            applyWalk()
        elseif Speed < 10 and RAnimation and RAnimation.IsPlaying then
            applyWalk()
        end
    end)

    Humanoid.Changed:Connect(function()
        if Humanoid.Jump and RAnimation and RAnimation.IsPlaying then
            pcall(function() RAnimation:Stop() end)
        end
    end)

    bindShiftAction()
    startHeartbeatEnforcement()
end

-- ======================================================
-- ESP HELPERS (dipertahankan)
-- ======================================================
function ESP.giveConn(conn) table.insert(ESP.connections, conn) return conn end

local function drawLine(frame, a, b, thickness)
	local dx = b.X - a.X
	local dy = b.Y - a.Y
	local len = math.sqrt(dx*dx + dy*dy)
	if len < 1 then frame.Visible = false; return end
	local angle = math.deg(math.atan2(dy, dx))
	frame.Visible = true
	frame.Size = UDim2.new(0, math.floor(len), 0, math.max(1, thickness))
	frame.Position = UDim2.fromOffset(math.floor(a.X), math.floor(a.Y))
	frame.Rotation = angle
end

local function formatDistanceStudsToMeters(studs: number)
	return string.format("%.1f m", studs * ESP.STUDS_TO_M)
end

local function espUpdateTitleCount()
	if not ESP.CountLabel then return end
	local total = 0
	for _,plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then total += 1 end
	end
	local selected = 0
	for _,sel in pairs(ESP.trackedPlayers) do
		if sel then selected += 1 end
	end
	ESP.CountLabel.Text = string.format("Players: %d selected / %d total", selected, total)
end

local function espAddListRow(plr)
	if plr == player or ESP.listEntries[plr] or not ESP.ListHolder then return end

	local row = Instance.new("Frame")
	row.Name = plr.Name:lower()
	row.Size = UDim2.new(1, -12, 0, 28)
	row.BackgroundColor3 = Color3.fromRGB(34,34,42)
	row.Parent = ESP.ListHolder
	Instance.new("UICorner", row).CornerRadius = UDim.new(0,6)

	local chk = Instance.new("TextButton")
	chk.Name = "Check"
	chk.Size = UDim2.new(0, 28, 1, 0)
	chk.Text = ESP.trackedPlayers[plr] and "☑" or "☐"
	chk.Font = Enum.Font.Gotham
	chk.TextSize = 18
	chk.TextColor3 = Color3.fromRGB(235,235,240)
	chk.BackgroundColor3 = Color3.fromRGB(46,46,56)
	chk.Parent = row
	Instance.new("UICorner", chk).CornerRadius = UDim.new(0,6)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.BackgroundTransparency = 1
	nameLbl.Font = Enum.Font.Gotham
	nameLbl.TextSize = 14
	nameLbl.TextColor3 = Color3.fromRGB(220,220,230)
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Text = plr.DisplayName .. " (@" .. plr.Name .. ")"
	nameLbl.Position = UDim2.new(0, 36, 0, 0)
	nameLbl.Size = UDim2.new(1, -36, 1, 0)
	nameLbl.Parent = row

	local function setChecked(val)
		ESP.trackedPlayers[plr] = val
		chk.Text = val and "☑" or "☐"
		espUpdateTitleCount()
	end

	chk.MouseButton1Click:Connect(function()
		setChecked(not ESP.trackedPlayers[plr])
	end)

	ESP.listEntries[plr] = { Frame = row, Check = chk, Label = nameLbl }
	if ESP.trackedPlayers[plr] == nil then
		ESP.trackedPlayers[plr] = true
		chk.Text = "☑"
	end
	espUpdateTitleCount()
end

local function espRemoveListRow(plr)
	local entry = ESP.listEntries[plr]
	if entry and entry.Frame then entry.Frame:Destroy() end
	ESP.listEntries[plr] = nil
	ESP.trackedPlayers[plr] = nil
	espUpdateTitleCount()
end

local function espApplySearchFilter()
	if not ESP.SearchBox then return end
	local q = string.lower(ESP.SearchBox.Text or "")
	for plr, entry in pairs(ESP.listEntries) do
		local txt = entry.Label.Text:lower()
		entry.Frame.Visible = (q == "" or string.find(txt, q, 1, true) ~= nil)
	end
end

local function espCreateUnit(plr)
	if plr == player or ESP.espByPlayer[plr] then return end

	local pack = {}

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ESP_Label"
	billboard.Size = UDim2.new(0, 220, 0, 34)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = ESP.SETTINGS.MaxDrawDistance
	billboard.StudsOffsetWorldSpace = Vector3.new(0, ESP.SETTINGS.LabelYOffset, 0)

	local text = Instance.new("TextLabel")
	text.BackgroundColor3 = Color3.fromRGB(0,0,0)
	text.BackgroundTransparency = 0.35
	text.BorderSizePixel = 0
	text.Size = UDim2.fromScale(1,1)
	text.Text = ""
	text.TextColor3 = Color3.fromRGB(255,255,255)
	text.Font = ESP.SETTINGS.Font
	text.TextSize = ESP.SETTINGS.TextSize
	text.TextWrapped = true
	text.Parent = billboard
	Instance.new("UICorner", text).CornerRadius = UDim.new(0,6)

	local line = Instance.new("Frame")
	line.Name = "ESP_Line"
	line.BackgroundColor3 = Color3.fromRGB(80,200,255)
	line.BorderSizePixel = 0
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Visible = false
	line.ZIndex = 2

	if ESP.LinesLayer then
		line.Parent = ESP.LinesLayer
	end

	pack.billboard = billboard
	pack.nameLabel = text
	pack.line = line
	ESP.espByPlayer[plr] = pack

	local function attachToCharacter(char)
		local hrp, head = safeCharParts(char)
		if hrp and head then
			billboard.Adornee = head
			billboard.Parent = head
		else
			billboard.Parent = nil
		end
		if char then
			char.ChildAdded:Connect(function(child)
				if child.Name == "Head" or child.Name == "HumanoidRootPart" then
					local hhrp, hhead = safeCharParts(char)
					if hhrp and hhead then
						billboard.Adornee = hhead
						billboard.Parent = hhead
					end
				end
			end)
		end
	end

	if plr.Character then attachToCharacter(plr.Character) end
	ESP.giveConn(plr.CharacterAdded:Connect(attachToCharacter))
	ESP.giveConn(plr.CharacterRemoving:Connect(function()
		pcall(function() billboard.Parent = nil end)
	end))
end

local function espDestroyUnit(plr)
	local pack = ESP.espByPlayer[plr]
	if not pack then return end
	if pack.billboard then pcall(function() pack.billboard:Destroy() end) end
	if pack.line then pcall(function() pack.line:Destroy() end) end
	ESP.espByPlayer[plr] = nil
end

-- ======================================================
-- UI + TAB SYSTEM (tetap)
-- ======================================================
local playersPage

local function createUI()
	if ScreenGui and ScreenGui.Parent then return end

	ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "SpectateUI"
	ScreenGui.ResetOnSpawn = false
	ScreenGui.IgnoreGuiInset = false
	ScreenGui.Parent = player:WaitForChild("PlayerGui")

	ESP.LinesLayer = Instance.new("Frame")
	ESP.LinesLayer.Name = "LinesLayer"
	ESP.LinesLayer.BackgroundTransparency = 1
	ESP.LinesLayer.Size = UDim2.fromScale(1,1)
	ESP.LinesLayer.Parent = ScreenGui
	ESP.LinesLayer.ZIndex = 1

	--joinSound = Instance.new("Sound"); joinSound.SoundId = "rbxassetid://12221967"; joinSound.Parent = ScreenGui
	--leaveSound = Instance.new("Sound"); leaveSound.SoundId = "rbxassetid://12222124"; leaveSound.Parent = ScreenGui

	-- spectate state
	local spectatingTarget, respawnConn, spectateIndex, filteredPlayers
	spectateIndex = 1; filteredPlayers = {}

	local function spectatePlayer(plr)
		if respawnConn then respawnConn:Disconnect(); respawnConn = nil end
		spectatingTarget = plr
		if plr and plr.Character then
			local hum = plr.Character:FindFirstChild("Humanoid")
			if hum then
				camera.CameraSubject = hum
				camera.AudioListener = Enum.CameraAudioListener.Character
			end
			respawnConn = plr.CharacterAdded:Connect(function(char)
				local hum2 = char:WaitForChild("Humanoid")
				camera.CameraSubject = hum2
				camera.AudioListener = Enum.CameraAudioListener.Character
			end)
		end
	end

	local function returnToSelf()
		spectatingTarget = nil
		if respawnConn then respawnConn:Disconnect(); respawnConn = nil end
		if player.Character then
			local hum = player.Character:FindFirstChild("Humanoid")
			if hum then
				camera.CameraSubject = hum
				camera.AudioListener = Enum.CameraAudioListener.Character
			end
		end
	end

	-- Toggle Button 👁
	toggleBtn = Instance.new("TextButton")
	toggleBtn.Size = UDim2.new(0,40,0,40)
	toggleBtn.Position = UDim2.new(1,-50,1,-50)
	toggleBtn.Text = "👁"
	toggleBtn.BackgroundTransparency = 0.3
	toggleBtn.Parent = ScreenGui
	toggleBtn.MouseButton1Click:Connect(function()
		if spectatingTarget ~= nil then
			returnToSelf()
			return
		end
		mainFrame.Visible = not mainFrame.Visible
		if mainFrame.Visible then
			notifyBar.Visible = false
			playersPage.Visible = true
			ESP.ESPPage.Visible = false
			headerTitle.Text = "Player Panel"
		end
	end)

	-- Main panel
	mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.new(0,360,0,460)
	mainFrame.Position = UDim2.new(1,-370,0.18,0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(24,24,30)
	mainFrame.BackgroundTransparency = 0.15
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = ScreenGui
	Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0,10)

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1,0,0,38)
	header.BackgroundColor3 = Color3.fromRGB(30,30,38)
	header.Parent = mainFrame
	Instance.new("UICorner", header).CornerRadius = UDim.new(0,10)

	headerTitle = Instance.new("TextLabel")
	headerTitle.Size = UDim2.new(1,-140,1,0)
	headerTitle.Position = UDim2.new(0,10,0,0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Font = Enum.Font.GothamSemibold
	headerTitle.TextSize = 16
	headerTitle.TextColor3 = Color3.fromRGB(230,230,235)
	headerTitle.Text = "Player Panel"
	headerTitle.Parent = header

	local minimizeBtn = Instance.new("TextButton")
	minimizeBtn.Size = UDim2.new(0,30,0,26)
	minimizeBtn.Position = UDim2.new(1,-72,0,6)
	minimizeBtn.Text = "-"
	minimizeBtn.Font = Enum.Font.GothamBold
	minimizeBtn.TextSize = 18
	minimizeBtn.BackgroundColor3 = Color3.fromRGB(50,50,64)
	minimizeBtn.TextColor3 = Color3.fromRGB(230,230,235)
	minimizeBtn.Parent = header
	Instance.new("UICorner", minimizeBtn).CornerRadius = UDim.new(0,6)

	local exitBtn = Instance.new("TextButton")
	exitBtn.Size = UDim2.new(0,30,0,26)
	exitBtn.Position = UDim2.new(1,-36,0,6)
	exitBtn.Text = "X"
	exitBtn.Font = Enum.Font.GothamBold
	exitBtn.TextSize = 16
	exitBtn.BackgroundColor3 = Color3.fromRGB(86,40,46)
	exitBtn.TextColor3 = Color3.fromRGB(255,235,235)
	exitBtn.Parent = header
	Instance.new("UICorner", exitBtn).CornerRadius = UDim.new(0,6)

	notifyBar = Instance.new("TextLabel")
	notifyBar.Size = UDim2.new(1,0,0,40)
	notifyBar.Position = UDim2.new(0,0,0,0)
	notifyBar.BackgroundColor3 = Color3.fromRGB(255,170,0)
	notifyBar.TextColor3 = Color3.fromRGB(0,0,0)
	notifyBar.Text = "Silahkan pencet huruf K untuk menampilkan kembali fitur spectate"
	notifyBar.Visible = false
	notifyBar.Parent = ScreenGui

	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, -20, 0, 32)
	tabBar.Position = UDim2.new(0,10,0,44)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = mainFrame

	local btnTabPlayers = Instance.new("TextButton")
	btnTabPlayers.Size = UDim2.new(0.5, -5, 1, 0)
	btnTabPlayers.Position = UDim2.new(0, 0, 0, 0)
	btnTabPlayers.Text = "Players"
	btnTabPlayers.Font = Enum.Font.GothamSemibold
	btnTabPlayers.TextSize = 14
	btnTabPlayers.TextColor3 = Color3.fromRGB(240,240,245)
	btnTabPlayers.BackgroundColor3 = Color3.fromRGB(45,45,58)
	btnTabPlayers.Parent = tabBar
	Instance.new("UICorner", btnTabPlayers).CornerRadius = UDim.new(0,8)

	local btnTabESP = Instance.new("TextButton")
	btnTabESP.Size = UDim2.new(0.5, -5, 1, 0)
	btnTabESP.Position = UDim2.new(0.5, 10, 0, 0)
	btnTabESP.Text = "ESP"
	btnTabESP.Font = Enum.Font.GothamSemibold
	btnTabESP.TextSize = 14
	btnTabESP.TextColor3 = Color3.fromRGB(240,240,245)
	btnTabESP.BackgroundColor3 = Color3.fromRGB(45,45,58)
	btnTabESP.Parent = tabBar
	Instance.new("UICorner", btnTabESP).CornerRadius = UDim.new(0,8)

	local quickRunBtn = Instance.new("TextButton")
	quickRunBtn.Size = UDim2.new(0,98,0,26)
	quickRunBtn.Position = UDim2.new(1,-210,0,6)
	quickRunBtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
	quickRunBtn.TextColor3 = Color3.fromRGB(255,255,255)
	quickRunBtn.Text = sprintEnabled and "RUN: ON" or "RUN: OFF"
	quickRunBtn.Font = Enum.Font.GothamSemibold
	quickRunBtn.TextSize = 14
	quickRunBtn.Parent = header
	Instance.new("UICorner", quickRunBtn).CornerRadius = UDim.new(0,6)

	ESP.BtnESPMaster = Instance.new("TextButton")
	ESP.BtnESPMaster.Size = UDim2.new(0,98,0,26)
	ESP.BtnESPMaster.Position = UDim2.new(1,-210,0,6)
	ESP.BtnESPMaster.BackgroundColor3 = Color3.fromRGB(40,40,40)
	ESP.BtnESPMaster.TextColor3 = Color3.fromRGB(255,255,255)
	ESP.BtnESPMaster.Text = ESP.SETTINGS.Enabled and "ESP: ON" or "ESP: OFF"
	ESP.BtnESPMaster.Font = Enum.Font.GothamSemibold
	ESP.BtnESPMaster.TextSize = 14
	ESP.BtnESPMaster.Parent = header
	Instance.new("UICorner", ESP.BtnESPMaster).CornerRadius = UDim.new(0,6)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -20, 1, -90)
	content.Position = UDim2.new(0,10,0,80)
	content.BackgroundTransparency = 1
	content.Parent = mainFrame

	playersPage = Instance.new("Frame")
	playersPage.Name = "PlayersPage"
	playersPage.Size = UDim2.new(1,0,1,0)
	playersPage.BackgroundTransparency = 1
	playersPage.Parent = content

	ESP.ESPPage = Instance.new("Frame")
	ESP.ESPPage.Name = "ESPPage"
	ESP.ESPPage.Size = UDim2.new(1,0,1,0)
	ESP.ESPPage.BackgroundTransparency = 1
	ESP.ESPPage.Visible = false
	ESP.ESPPage.Parent = content

	local headerLabel = Instance.new("TextLabel")
	headerLabel.Size = UDim2.new(1,0,0,30)
	headerLabel.BackgroundTransparency = 0.3
	headerLabel.Text = "Player List (0/0)"
	headerLabel.Font = Enum.Font.GothamSemibold
	headerLabel.TextSize = 14
	headerLabel.TextColor3 = Color3.fromRGB(230,230,235)
	headerLabel.Parent = playersPage

	local controlsFrame = Instance.new("Frame")
	controlsFrame.Size = UDim2.new(1,0,0,30)
	controlsFrame.Position = UDim2.new(0,0,0,30)
	controlsFrame.BackgroundTransparency = 1
	controlsFrame.Parent = playersPage

	local prevBtn = Instance.new("TextButton")
	prevBtn.Size = UDim2.new(0,40,1,0)
	prevBtn.Position = UDim2.new(0,5,0,0)
	prevBtn.Text = "<"
	prevBtn.Parent = controlsFrame

	local nextBtn = Instance.new("TextButton")
	nextBtn.Size = UDim2.new(0,40,1,0)
	nextBtn.Position = UDim2.new(0,50,0,0)
	nextBtn.Text = ">"
	nextBtn.Parent = controlsFrame

	local tpBtn = Instance.new("TextButton")
	tpBtn.Size = UDim2.new(0,80,1,0)
	tpBtn.Position = UDim2.new(1,-85,0,0)
	tpBtn.Text = "TP"
	tpBtn.Parent = controlsFrame

	local runBtn = Instance.new("TextButton")
	runBtn.Size = UDim2.new(0,85,1,0)
	runBtn.Position = UDim2.new(1,-175,0,0)
	runBtn.BackgroundColor3 = Color3.fromRGB(40,40,40)
	runBtn.TextColor3 = Color3.fromRGB(255,255,255)
	runBtn.AutoButtonColor = true
	runBtn.Text = sprintEnabled and "RUN: ON" or "RUN: OFF"
	runBtn.Parent = controlsFrame

	local searchBar = Instance.new("TextBox")
	searchBar.Size = UDim2.new(1,-10,0,25)
	searchBar.Position = UDim2.new(0,5,0,65)
	searchBar.Text = "axaxyz999"
	searchBar.TextColor3 = Color3.fromRGB(150,150,150)
	searchBar.ClearTextOnFocus = false
	searchBar.Parent = playersPage

	searchBar.Focused:Connect(function()
		if searchBar.Text == "axaxyz999" then
			searchBar.Text = ""
			searchBar.TextColor3 = Color3.fromRGB(255,255,255)
		end
	end)
	searchBar.FocusLost:Connect(function()
		if searchBar.Text == "" then
			searchBar.Text = "axaxyz999"
			searchBar.TextColor3 = Color3.fromRGB(150,150,150)
		end
	end)

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1,-10,1,-150)
	scrollFrame.Position = UDim2.new(0,5,0,95)
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.CanvasSize = UDim2.new(0,0,0,0)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.Parent = playersPage

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0,5)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scrollFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0,5)
	padding.PaddingRight = UDim.new(0,5)
	padding.PaddingTop = UDim.new(0,5)
	padding.Parent = scrollFrame

	footerFrame = Instance.new("Frame")
	footerFrame.Size = UDim2.new(1,0,0,100)
	footerFrame.Position = UDim2.new(0,0,1,-50)
	footerFrame.BackgroundColor3 = Color3.fromRGB(60,60,60)
	footerFrame.Parent = playersPage

	joinLabel = Instance.new("TextLabel")
	joinLabel.Size = UDim2.new(1,-10,0,25)
	joinLabel.Position = UDim2.new(0,5,0,0)
	joinLabel.Text = "✅ Tidak ada yang bergabung"
	joinLabel.TextColor3 = Color3.fromRGB(0,255,0)
	joinLabel.BackgroundTransparency = 1
	joinLabel.TextXAlignment = Enum.TextXAlignment.Left
	joinLabel.Font = Enum.Font.SourceSansItalic
	joinLabel.TextSize = 14
	joinLabel.Parent = footerFrame

	leaveLabel = Instance.new("TextLabel")
	leaveLabel.Size = UDim2.new(1,-10,0,25)
	leaveLabel.Position = UDim2.new(0,5,0,25)
	leaveLabel.Text = "❌ Tidak ada yang keluar"
	leaveLabel.TextColor3 = Color3.fromRGB(255,80,80)
	leaveLabel.BackgroundTransparency = 1
	leaveLabel.TextXAlignment = Enum.TextXAlignment.Left
	leaveLabel.Font = Enum.Font.SourceSansItalic
	leaveLabel.TextSize = 14
	leaveLabel.Parent = footerFrame

	afkLabel = Instance.new("TextLabel")
	afkLabel.Size = UDim2.new(1,-10,0,25)
	afkLabel.Position = UDim2.new(0,5,0,50)
	afkLabel.Text = "⚠ Tidak ada yang AFK"
	afkLabel.TextColor3 = Color3.fromRGB(255,255,0)
	afkLabel.BackgroundTransparency = 1
	afkLabel.TextXAlignment = Enum.TextXAlignment.Left
	afkLabel.Font = Enum.Font.SourceSansItalic
	afkLabel.TextSize = 14
	afkLabel.Parent = footerFrame

	createdLabel = Instance.new("TextLabel")
	createdLabel.Size = UDim2.new(1,-10,0,25)
	createdLabel.Position = UDim2.new(0,5,0,70)
	createdLabel.Text = "🏆 Created by AxaXyz"
	createdLabel.TextColor3 = Color3.fromRGB(255,255,0)
	createdLabel.BackgroundTransparency = 1
	createdLabel.TextXAlignment = Enum.TextXAlignment.Center
	createdLabel.Font = Enum.Font.SourceSansItalic
	createdLabel.TextSize = 14
	createdLabel.Parent = footerFrame

	-- ====== TAB ESP UI (tetap) ======
	ESP.CountLabel = Instance.new("TextLabel")
	ESP.CountLabel.BackgroundTransparency = 1
	ESP.CountLabel.Font = Enum.Font.Gotham
	ESP.CountLabel.TextSize = 12
	ESP.CountLabel.TextColor3 = Color3.fromRGB(180,180,190)
	ESP.CountLabel.TextXAlignment = Enum.TextXAlignment.Left
	ESP.CountLabel.Size = UDim2.new(1, -10, 0, 18)
	ESP.CountLabel.Position = UDim2.new(0, 5, 0, 0)
	ESP.CountLabel.Text = "Players: 0 selected / 0 total"
	ESP.CountLabel.Parent = ESP.ESPPage

	ESP.Controls = Instance.new("Frame")
	ESP.Controls.Name = "ESPControls"
	ESP.Controls.BackgroundTransparency = 1
	ESP.Controls.Position = UDim2.new(0, 5, 0, 22)
	ESP.Controls.Size = UDim2.new(1, -10, 0, 120)
	ESP.Controls.Parent = ESP.ESPPage

	local function makeToggle(parent, text, default, onChanged)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1,0,0,24)
		row.BackgroundTransparency = 1
		row.Parent = parent

		local box = Instance.new("TextButton")
		box.Name = "Toggle"
		box.Text = default and "☑" or "☐"
		box.AutoButtonColor = true
		box.Font = Enum.Font.Gotham
		box.TextSize = 18
		box.TextColor3 = Color3.fromRGB(230,230,235)
		box.BackgroundColor3 = Color3.fromRGB(40,40,48)
		box.Size = UDim2.new(0,28,1,0)
		box.Parent = row

		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 14
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextColor3 = Color3.fromRGB(220,220,225)
		lbl.Text = text
		lbl.Position = UDim2.new(0,36,0,0)
		lbl.Size = UDim2.new(1,-40,1,0)
		lbl.Parent = row

		local state = default
		box.MouseButton1Click:Connect(function()
			state = not state
			box.Text = state and "☑" or "☐"
			onChanged(state)
		end)

		return {
			Set = function(v) state=v; box.Text = v and "☑" or "☐"; onChanged(state) end,
			Get = function() return state end,
			Row = row,
		}
	end

	local tEnabled  = makeToggle(ESP.Controls, "ESP Enabled", ESP.SETTINGS.Enabled, function(v) ESP.SETTINGS.Enabled=v; if ESP.BtnESPMaster then ESP.BtnESPMaster.Text = v and "ESP: ON" or "ESP: OFF" end end)
	local tNames    = makeToggle(ESP.Controls, "Show Names", ESP.SETTINGS.ShowNames, function(v) ESP.SETTINGS.ShowNames=v end)
	local tDistance = makeToggle(ESP.Controls, "Show Distance", ESP.SETTINGS.ShowDistance, function(v) ESP.SETTINGS.ShowDistance=v end)
	local tLines    = makeToggle(ESP.Controls, "Draw Lines", ESP.SETTINGS.ShowLines, function(v) ESP.SETTINGS.ShowLines=v end)
	local tMeters   = makeToggle(ESP.Controls, "Use Meters (vs Studs)", ESP.SETTINGS.UseMeters, function(v) ESP.SETTINGS.UseMeters=v end)

	tNames.Row.Position    = UDim2.new(0,0,0,24)
	tDistance.Row.Position = UDim2.new(0,0,0,48)
	tLines.Row.Position    = UDim2.new(0,0,0,72)
	tMeters.Row.Position   = UDim2.new(0,0,0,96)
	ESP.Controls.Size      = UDim2.new(1, -10, 0, 120)

	ESP.SearchBox = Instance.new("TextBox")
	ESP.SearchBox.PlaceholderText = "Search player..."
	ESP.SearchBox.Text = ""
	ESP.SearchBox.ClearTextOnFocus = false
	ESP.SearchBox.Font = Enum.Font.Gotham
	ESP.SearchBox.TextSize = 14
	ESP.SearchBox.TextColor3 = Color3.fromRGB(230,230,235)
	ESP.SearchBox.BackgroundColor3 = Color3.fromRGB(32,32,40)
	ESP.SearchBox.Size = UDim2.new(1, -10, 0, 28)
	ESP.SearchBox.Position = UDim2.new(0, 5, 0, 150)
	ESP.SearchBox.Parent = ESP.ESPPage

	ESP.ListHolder = Instance.new("ScrollingFrame")
	ESP.ListHolder.Name = "List"
	ESP.ListHolder.Size = UDim2.new(1, -10, 1, -210)
	ESP.ListHolder.Position = UDim2.new(0, 5, 0, 184)
	ESP.ListHolder.BackgroundColor3 = Color3.fromRGB(26,26,32)
	ESP.ListHolder.BorderSizePixel = 0
	ESP.ListHolder.ScrollBarThickness = 6
	ESP.ListHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ESP.ListHolder.CanvasSize = UDim2.new(0,0,0,0)
	ESP.ListHolder.Parent = ESP.ESPPage
	Instance.new("UICorner", ESP.ListHolder).CornerRadius = UDim.new(0,10)

	ESP.UIList = Instance.new("UIListLayout")
	ESP.UIList.SortOrder = Enum.SortOrder.Name
	ESP.UIList.Padding = UDim.new(0,6)
	ESP.UIList.Parent = ESP.ListHolder

	local footerESP = Instance.new("Frame")
	footerESP.Size = UDim2.new(1, -10, 0, 32)
	footerESP.Position = UDim2.new(0, 5, 1, -36)
	footerESP.BackgroundTransparency = 1
	footerESP.Parent = ESP.ESPPage

	ESP.BtnAll = Instance.new("TextButton")
	ESP.BtnAll.Size = UDim2.new(0.5, -6, 1, 0)
	ESP.BtnAll.Text = "Select All"
	ESP.BtnAll.Font = Enum.Font.GothamSemibold
	ESP.BtnAll.TextSize = 14
	ESP.BtnAll.TextColor3 = Color3.fromRGB(20,20,24)
	ESP.BtnAll.BackgroundColor3 = Color3.fromRGB(190,235,190)
	ESP.BtnAll.Parent = footerESP
	Instance.new("UICorner", ESP.BtnAll).CornerRadius = UDim.new(0,8)

	ESP.BtnClear = Instance.new("TextButton")
	ESP.BtnClear.Size = UDim2.new(0.5, -6, 1, 0)
	ESP.BtnClear.Position = UDim2.new(0.5, 6, 0, 0)
	ESP.BtnClear.Text = "Clear"
	ESP.BtnClear.Font = Enum.Font.GothamSemibold
	ESP.BtnClear.TextSize = 14
	ESP.BtnClear.TextColor3 = Color3.fromRGB(240,240,245)
	ESP.BtnClear.BackgroundColor3 = Color3.fromRGB(70,70,85)
	ESP.BtnClear.Parent = footerESP
	Instance.new("UICorner", ESP.BtnClear).CornerRadius = UDim.new(0,8)

	-- Content container
	local content = content -- luaskan scope (sudah di atas)

	-- ====== Konten Tab Players ======
	local function showPlayers()
		playersPage.Visible = true
		ESP.ESPPage.Visible = false
		headerTitle.Text = "Player Panel"
	end
	local function showESP()
		playersPage.Visible = false
		ESP.ESPPage.Visible = true
		headerTitle.Text = "ESP Panel"
	end
	btnTabPlayers.MouseButton1Click:Connect(showPlayers)
	btnTabESP.MouseButton1Click:Connect(showESP)

	local function createPlayerButton(plr)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1,-10,0,40)
		row.BackgroundTransparency = 0.3
		row.Parent = scrollFrame

		local avatar = Instance.new("ImageLabel")
		avatar.Size = UDim2.new(0,30,0,30)
		avatar.Position = UDim2.new(0,5,0,5)
		avatar.BackgroundTransparency = 1
		avatar.Image = "https://www.roblox.com/headshot-thumbnail/image?userId="..plr.UserId.."&width=48&height=48&format=png"
		avatar.Parent = row

		local display = Instance.new("TextLabel")
		display.Size = UDim2.new(1,-100,0,20)
		display.Position = UDim2.new(0,45,0,0)
		display.Text = plr.DisplayName
		display.TextColor3 = Color3.fromRGB(255,255,255)
		display.Font = Enum.Font.SourceSansBold
		display.TextXAlignment = Enum.TextXAlignment.Left
		display.BackgroundTransparency = 1
		display.Parent = row

		local username = Instance.new("TextLabel")
		username.Size = UDim2.new(1,-100,0,15)
		username.Position = UDim2.new(0,45,0,20)
		username.Text = "@"..plr.Name
		username.TextColor3 = Color3.fromRGB(255,0,0)
		username.Font = Enum.Font.SourceSans
		username.TextSize = 14
		username.TextXAlignment = Enum.TextXAlignment.Left
		username.BackgroundTransparency = 1
		username.Parent = row

		local distLabel = Instance.new("TextLabel")
		distLabel.Size = UDim2.new(0,70,1,0)
		distLabel.Position = UDim2.new(1,-75,0,0)
		distLabel.Text = "0.0 m"
		distLabel.TextColor3 = Color3.fromRGB(150,255,150)
		distLabel.BackgroundTransparency = 1
		distLabel.TextXAlignment = Enum.TextXAlignment.Right
		distLabel.Font = Enum.Font.Gotham
		distLabel.TextSize = 13
		distLabel.Parent = row

		playerRows[plr] = {frame=row, dist=distLabel}
		AFKTimers[plr] = tick()

		local clickBtn = Instance.new("TextButton")
		clickBtn.Size = UDim2.new(1,0,1,0)
		clickBtn.BackgroundTransparency = 1
		clickBtn.Text = ""
		clickBtn.Parent = row
		clickBtn.MouseButton1Click:Connect(function()
			spectatePlayer(plr)
		end)

		return row
	end

	-- REFRESH LIST: bersihkan row lama & tabel playerRows
	local function refreshList()
		for _,child in ipairs(scrollFrame:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		playerRows = {} -- <== penting agar loop update jarak tidak iterasi row yang sudah dihapus

		local searchText = searchBar.Text
		if searchText == "axaxyz999" then searchText = "" end
		searchText = string.lower(searchText)
		local totalPlayers = #Players:GetPlayers()
		local shown = 0
		filteredPlayers = {}
		for _,plr in ipairs(Players:GetPlayers()) do
			if string.find(string.lower(plr.Name), searchText) or string.find(string.lower(plr.DisplayName), searchText) then
				createPlayerButton(plr)
				table.insert(filteredPlayers, plr)
				shown += 1
			end
		end
		headerLabel.Text = "Player List ("..shown.."/"..totalPlayers..")"
		scrollFrame.CanvasSize = UDim2.new(0,0,0,listLayout.AbsoluteContentSize.Y + 10)
	end

	prevBtn.MouseButton1Click:Connect(function()
		if #filteredPlayers > 0 then
			spectateIndex -= 1
			if spectateIndex < 1 then spectateIndex = #filteredPlayers end
			spectatePlayer(filteredPlayers[spectateIndex])
		end
	end)
	nextBtn.MouseButton1Click:Connect(function()
		if #filteredPlayers > 0 then
			spectateIndex += 1
			if spectateIndex > #filteredPlayers then spectateIndex = 1 end
			spectatePlayer(filteredPlayers[spectateIndex])
		end
	end)
	tpBtn.MouseButton1Click:Connect(function()
		if spectatingTarget and spectatingTarget.Character and player.Character then
			local targetPos = getCharPosition(spectatingTarget.Character)
			local myChar = player.Character
			local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
			if targetPos and myHrp then
				myHrp.CFrame = CFrame.new(targetPos) + Vector3.new(2,0,0)
			end
		end
	end)

	runBtn.MouseButton1Click:Connect(function()
		setSprintEnabled(not sprintEnabled, runBtn)
		quickRunBtn.Text = sprintEnabled and "RUN: ON" or "RUN: OFF"
	end)
	quickRunBtn.MouseButton1Click:Connect(function()
		setSprintEnabled(not sprintEnabled, quickRunBtn)
		runBtn.Text = sprintEnabled and "RUN: ON" or "RUN: OFF"
	end)

	Players.PlayerAdded:Connect(function(plr)
		refreshList()
		joinLabel.Text = "✅ "..plr.DisplayName.." (@"..plr.Name..") bergabung"
		joinSound:Play()
	end)
	Players.PlayerRemoving:Connect(function(plr)
		refreshList()
		leaveLabel.Text = "❌ "..plr.DisplayName.." (@"..plr.Name..") keluar"
		leaveSound:Play()
	end)
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.new(0,0,0,listLayout.AbsoluteContentSize.Y + 10)
	end)
	searchBar:GetPropertyChangedSignal("Text"):Connect(refreshList)

	-- ====== UPDATE JARAK: gunakan helper posisi + meter ======
	RunService.RenderStepped:Connect(function()
		local myPos = getCharPosition(player.Character)
		if not myPos then return end
		for plr, data in pairs(playerRows) do
			local pos = getCharPosition(plr.Character)
			if pos and data.dist then
				local studs = (myPos - pos).Magnitude
				-- tampilkan meter 1 desimal
				data.dist.Text = formatDistanceStudsToMeters(studs)
			end
		end
	end)

	-- ====== AFK Detector (tetap) ======
	RunService.Stepped:Connect(function()
		local anyAFK = false
		for plr,_ in pairs(playerRows) do
			if plr.Character and plr.Character:FindFirstChild("Humanoid") then
				local hum = plr.Character:FindFirstChild("Humanoid")
				if hum.MoveDirection.Magnitude > 0 then
					AFKTimers[plr] = tick()
					if WasAFK[plr] then
						WasAFK[plr] = false
						AFKStart[plr] = nil
						afkLabel.Text = "✅ " .. plr.DisplayName .. " kembali aktif"
						task.delay(ActiveResetDelay, function()
							if not WasAFK[plr] then
								afkLabel.Text = "⚠ Tidak ada yang AFK"
							end
						end)
					end
				else
					local idleTime = tick() - AFKTimers[plr]
					if idleTime > 60 then
						if not AFKStart[plr] then AFKStart[plr] = tick() end
						local afkDuration = tick() - AFKStart[plr]
						local minutes = math.floor(afkDuration / 60)
						local seconds = math.floor(afkDuration % 60)
						local timeStr = (minutes > 0) and string.format("%d menit %02d detik", minutes, seconds) or string.format("%d detik", seconds)
						afkLabel.Text = "⚠ " .. plr.DisplayName .. " sedang AFK (" .. timeStr .. ")"
						anyAFK = true
						WasAFK[plr] = true
					end
				end
			end
		end
		if not anyAFK then
			local stillAFK = false
			for _,state in pairs(WasAFK) do if state then stillAFK = true break end end
			if not stillAFK then afkLabel.Text = "⚠ Tidak ada yang AFK" end
		end
	end)

	-- Inisialisasi
	local function initPlayers()
		runBtn.Text = sprintEnabled and "RUN: ON" or "RUN: OFF"
		quickRunBtn.Text = sprintEnabled and "RUN: ON" or "RUN: OFF"
		refreshList()
	end
	initPlayers()

	-- ESP hooks
	ESP.SearchBox:GetPropertyChangedSignal("Text"):Connect(espApplySearchFilter)
	ESP.BtnAll.MouseButton1Click:Connect(function()
		for _,plr in ipairs(Players:GetPlayers()) do
			if plr ~= player then
				ESP.trackedPlayers[plr] = true
				local e = ESP.listEntries[plr]
				if e and e.Check then e.Check.Text = "☑" end
			end
		end
		espUpdateTitleCount()
	end)
	ESP.BtnClear.MouseButton1Click:Connect(function()
		for plr,_ in pairs(ESP.trackedPlayers) do
			ESP.trackedPlayers[plr] = false
			local e = ESP.listEntries[plr]
			if e and e.Check then e.Check.Text = "☐" end
		end
		espUpdateTitleCount()
	end)
	ESP.BtnESPMaster.MouseButton1Click:Connect(function()
		ESP.SETTINGS.Enabled = not ESP.SETTINGS.Enabled
		ESP.BtnESPMaster.Text = ESP.SETTINGS.Enabled and "ESP: ON" or "ESP: OFF"
	end)

	for _,plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			espAddListRow(plr)
			espCreateUnit(plr)
		end
	end
	Players.PlayerAdded:Connect(function(plr)
		espAddListRow(plr)
		espCreateUnit(plr)
		espApplySearchFilter()
	end)
	Players.PlayerRemoving:Connect(function(plr)
		espRemoveListRow(plr)
		espDestroyUnit(plr)
	end)

	-- Minimize / Exit / Drag (tetap)
	minimizeBtn.MouseButton1Click:Connect(function()
		mainFrame.Visible = false
	end)
	exitBtn.MouseButton1Click:Connect(function()
		mainFrame.Visible = false
		notifyBar.Visible = true
	end)
	do
		local dragging = false
		local dragInput, dragStart, startPos
		local function update(input)
			local delta = input.Position - dragStart
			mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
		header.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				dragStart = input.Position
				startPos = mainFrame.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end)
		header.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then dragInput = input end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input == dragInput and dragging then update(input) end
		end)
	end
end

-- ======================================================
-- RENDER LOOP ESP
-- ======================================================
RunService.RenderStepped:Connect(function(dt)
	if not ESP.SETTINGS.Enabled then
		for _, pack in pairs(ESP.espByPlayer) do
			if pack.billboard then pack.billboard.Enabled = false end
			if pack.line then pack.line.Visible = false end
		end
		return
	end

	ESP.lastUpdate += dt
	if ESP.lastUpdate < ESP.SETTINGS.RefreshRate then return end
	ESP.lastUpdate = 0

	local viewportSize = camera.ViewportSize
	local screenCenter = Vector2.new(viewportSize.X/2, viewportSize.Y/2)
	local camPos = camera.CFrame.Position

	for plr, pack in pairs(ESP.espByPlayer) do
		local selected = ESP.trackedPlayers[plr]
		local char = plr.Character
		local hrp, head, hum = safeCharParts(char)

		if pack.billboard and (pack.billboard.Parent == nil) and head then
			pack.billboard.Adornee = head
			pack.billboard.Parent = head
		end

		if not (selected and hrp and head and hum) then
			if pack.billboard then pack.billboard.Enabled = false end
			if pack.line then pack.line.Visible = false end
		else
			local distanceStuds = (camPos - hrp.Position).Magnitude
			local inRange = (distanceStuds <= ESP.SETTINGS.MaxDrawDistance)

			local hrpScreen, hrpOnScreen = camera:WorldToViewportPoint(hrp.Position)
			local behindCam = (hrpScreen.Z <= 0)

			if pack.billboard then
				local parts = {}
				if ESP.SETTINGS.ShowNames then
					table.insert(parts, plr.DisplayName)
					table.insert(parts, "@"..plr.Name)
				end
				if ESP.SETTINGS.ShowDistance then
					table.insert(parts, formatDistanceStudsToMeters(distanceStuds))
				end
				pack.nameLabel.Text = (#parts > 0) and table.concat(parts, "  |  ") or ""
				pack.billboard.Enabled = (not behindCam) and inRange and (#parts > 0)
			end

			if pack.line and ESP.LinesLayer then
				if ESP.SETTINGS.ShowLines and inRange and (not behindCam) and hrpOnScreen then
					local target2D = Vector2.new(hrpScreen.X, hrpScreen.Y)
					drawLine(pack.line, screenCenter, target2D, ESP.SETTINGS.LineThickness)
				else
					pack.line.Visible = false
				end
			end
		end
	end
end)

-- ======================================================
-- INIT
-- ======================================================
if player.Character then attachCharacter(player.Character) end
player.CharacterAdded:Connect(attachCharacter)

createUI()

-- K untuk munculkan GUI jika notifikasi aktif
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.K and notifyBar.Visible then
		mainFrame.Visible = true
		notifyBar.Visible = false
	end
end)

-- Q untuk destroy/restore UI
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		if ScreenGui and ScreenGui.Parent then
			ScreenGui:Destroy()
			ScreenGui = nil
			mainFrame = nil
			toggleBtn = nil
			notifyBar = nil
			footerFrame = nil
			joinLabel = nil
			leaveLabel = nil
			afkLabel = nil
			createdLabel = nil
			joinSound = nil
			leaveSound = nil
			ESP.LinesLayer = nil
		else
			createUI()
		end
	end
end)

pcall(function()
	StarterGui:SetCore("SendNotification", {
		Title = "Panel Ready",
		Text = "ShiftRun & ESP siap. Jarak player kini akurat (meter).",
		Duration = 30
	})
end)

--========================================================
-- Double Jump (Single LocalScript)
-- Tempatkan: StarterPlayer > StarterPlayerScripts
--========================================================
--====================--
--  SETTINGS / OPSI   --
--====================--
local Settings = {
	ExtraJumps = 5,        -- berapa kali bisa lompat di udara (di luar lompat awal)
	WhiteList  = {},       -- kosong = semua boleh; contoh: {17258879, 178439272}

	-- VFX pijakan di udara (jika tidak ada model template, script buat part sederhana)
	EnableAirStepVFX = true,
	AirStepLife = 0.5,     -- detik umur pijakan
	AirStepSize = Vector3.new(2.5, 0.35, 2.5),
	AirStepTransparency = 0.25,
	AirStepMaterial = Enum.Material.Neon,
}

--====================--
--    SERVICES        --
--====================--
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

--====================--
--   STATE VARIABEL   --
--====================--
local humanoid : Humanoid
local root : BasePart
local jumpsDone = 0
local grounded = false
local airTimer = 0

--====================--
--   UTIL / HELPERS   --
--====================--

local function isWhitelisted(p: Player): boolean
	local wl = Settings.WhiteList
	if wl and #wl > 0 then
		for _, id in ipairs(wl) do
			if id == p.UserId then
				return true
			end
		end
		return false
	end
	return true -- whitelist kosong -> semua boleh
end

-- Coba cari template VFX bernama "JumpPlatform" di ReplicatedStorage bila ada
local JumpPlatformTemplate = ReplicatedStorage:FindFirstChild("JumpPlatform")

local function spawnAirStepVFX(pos: Vector3)
	if not Settings.EnableAirStepVFX then return end

	if JumpPlatformTemplate then
		-- Pakai template user (Model atau Part)
		local obj = JumpPlatformTemplate:Clone()
		obj.Name = "DJ_Pivot"
		obj.Parent = workspace

		if obj:IsA("BasePart") then
			obj.Anchored = true
			obj.CanCollide = false
			obj.CFrame = CFrame.new(pos)
		else
			-- Model
			if obj.PrimaryPart then
				obj:SetPrimaryPartCFrame(CFrame.new(pos))
			else
				obj:PivotTo(CFrame.new(pos))
			end
			for _, d in ipairs(obj:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
				end
			end
		end

		Debris:AddItem(obj, Settings.AirStepLife)
	else
		-- Buat part sederhana
		local p = Instance.new("Part")
		p.Name = "AirStep"
		p.Anchored = true
		p.CanCollide = false
		p.Size = Settings.AirStepSize
		p.Material = Settings.AirStepMaterial
		p.Color = Color3.new(1, 1, 1)
		p.Transparency = Settings.AirStepTransparency
		p.CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad((tick()*180)%360), 0)
		p.Parent = workspace
		Debris:AddItem(p, Settings.AirStepLife)
	end
end

local function bindCharacter(char: Model)
	humanoid = char:WaitForChild("Humanoid") :: Humanoid
	root = char:WaitForChild("HumanoidRootPart") :: BasePart
	jumpsDone = 0
	grounded = false

	-- Reset counter saat mendarat/berlari/berenang
	humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Landed
		or newState == Enum.HumanoidStateType.Running
		or newState == Enum.HumanoidStateType.RunningNoPhysics
		or newState == Enum.HumanoidStateType.Swimming then
			jumpsDone = 0
			grounded = true
		elseif newState == Enum.HumanoidStateType.Freefall then
			grounded = false
		end
	end)
end

--====================--
--    INPUT LOMPAT    --
--====================--

-- Dipicu tiap kali tombol lompat ditekan (space / mobile jump)
UserInputService.JumpRequest:Connect(function()
	if not humanoid or humanoid.Health <= 0 then return end
	if not isWhitelisted(player) then return end

	-- Bila masih "grounded", biarkan lompat normal (counter direset saat state berubah)
	if grounded then return end

	-- Di udara -> perbolehkan extra jump
	if jumpsDone < (Settings.ExtraJumps or 0) then
		jumpsDone += 1

		-- Tambah kecepatan vertikal agar terasa "lompat lagi"
		local v = root.Velocity
		local upward = math.max(50, humanoid.JumpPower * 1.15)
		root.Velocity = Vector3.new(v.X, upward, v.Z)

		-- Paksa state lompat untuk sinkron animasi
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

		-- VFX lokal (pijakan di bawah kaki)
		spawnAirStepVFX(root.Position - Vector3.new(0, 3, 0))
	end
end)

--====================--
--   SAFETY / INIT    --
--====================--

-- Safety: kalau terlalu lama di Freefall, jangan kunci counter
RunService.Heartbeat:Connect(function(dt)
	if humanoid and humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		airTimer += dt
		if airTimer > 3 then
			-- tidak menambah jump, hanya mencegah soft-lock
			jumpsDone = math.min(jumpsDone, Settings.ExtraJumps or 0)
		end
	else
		airTimer = 0
	end
end)

-- Bind awal + respawn
if player.Character then
	bindCharacter(player.Character)
end
player.CharacterAdded:Connect(bindCharacter)


--// SCRIPT !REJOIN KE SERVER/MAP
--// SCRIPT !REJOIN KE SERVER/MAP
local TeleportService = game:GetService("TeleportService")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local PLACE_ID, JOB_ID = game.PlaceId, game.JobId

-- ======== KONFIG COMMAND ========
-- Tambah/ubah perintah di sini (huruf besar/kecil diabaikan)
local COMMANDS = {
	["!rejoin"] = true,
	["!rej"] = true,
}
-- ================================

local busy = false

local function notify(title, text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = title or "Info";
			Text = text or "";
			Duration = 3;
		})
	end)
end

local function doRejoin()
	if busy then return end
	busy = true
	notify("Rejoin", "Mencoba masuk ulang...")
	-- 1) Coba balik ke server instance yang sama (JOB_ID sama)
	local ok = pcall(function()
		TeleportService:TeleportToPlaceInstance(PLACE_ID, JOB_ID, player)
	end)
	if not ok then
		pcall(function()
			TeleportService:Teleport(PLACE_ID, player)
		end)
	end
end

local function trimLower(s)
	s = tostring(s or "")
	s = s:match("^%s*(.-)%s*$") or s
	return string.lower(s)
end

local function isCommand(msg)
	msg = trimLower(msg)
	-- terima tepat sama atau ada spasi di belakang (mis. "!rejoin   ")
	if COMMANDS[msg] then return true end
	if COMMANDS[msg:gsub("%s+$","")] then return true end
	return false
end

-- ========= DUKUNG CHAT BARU (TextChatService) =========
-- Blokir pesan command agar tidak muncul di chat dan langsung rejoin
local function hookTextChatService()
	if not TextChatService then return false end
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then return false end

	TextChatService.SendingMessage:Connect(function(props)
		-- props: TextChatMessageProperties
		if isCommand(props.Text) then
			doRejoin()
			-- Tolak pengiriman agar command tidak tampil di chat
			return Enum.TextChatMessageResultEnum.MessageRejected
		end
		-- kalau bukan command, biarkan chat terkirim (return nil)
	end)
	return true
end

-- ========= DUKUNG CHAT LAMA (Legacy ChatService) =========
local function hookLegacyChat()
	-- Event ini hanya ada di sistem lama
	player.Chatted:Connect(function(msg)
		if isCommand(msg) then
			doRejoin()
			-- Di legacy, tidak bisa membatalkan pesan; akan tetap muncul.
			-- Jika ingin menyembunyikan, pakai TextChatService di pengalamanmu.
		end
	end)
end

local okNew = false
pcall(function()
	okNew = hookTextChatService()
end)

if not okNew then
	hookLegacyChat()
end

-- INFO awal
notify("Rejoin Command Siap", "Ketik !rejoin atau !rej di chat.")

-- SCRIPT KOMPAS
-- SCRIPT KOMPAS
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local cam    = workspace.CurrentCamera

-- =======================
-- PARAMETER TAMPILAN
-- =======================
local WIDTH            = 480      -- lebar kompas (px)
local HEIGHT           = 44       -- tinggi kompas (px)
local MARGIN_BOTTOM    = 16       -- jarak dari bawah layar (px)
local BG_TRANSP        = 0.35     -- transparansi latar belakang
local PIXELS_PER_DEG   = 2        -- skala pita (px/derajat)
local TICK_EVERY       = 10       -- jarak antar tick utama (deg)
local TICK_HEIGHT_MIN  = 8
local TICK_HEIGHT_MID  = 12
local TICK_HEIGHT_MAX  = 18

-- =======================
-- UTIL
-- =======================
local function yawDegFromLook(v: Vector3)
	-- 0° = Utara (Z+), 90° = Timur (X+)
	local deg = math.deg(math.atan2(v.X, v.Z))
	return (deg % 360 + 360) % 360
end

-- =======================
-- BANGUN UI
-- =======================
local pg = player:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("CenterCompassHUD")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "CenterCompassHUD"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = pg

local container = Instance.new("Frame")
container.Name = "CompassContainer"
container.AnchorPoint = Vector2.new(0.5, 0)
container.Position = UDim2.new(0.5, 0, 0, MARGIN_TOP) 
container.Size = UDim2.fromOffset(WIDTH, HEIGHT)
container.BackgroundColor3 = Color3.fromRGB(0,0,0)
container.BackgroundTransparency = BG_TRANSP
container.BorderSizePixel = 0
container.ClipsDescendants = true
container.Parent = gui

Instance.new("UICorner", container).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", container)
stroke.Thickness = 1
stroke.Color = Color3.fromRGB(255,255,255)
stroke.Transparency = 0.75

local headingLabel = Instance.new("TextLabel")
headingLabel.BackgroundTransparency = 1
headingLabel.Size = UDim2.new(1, -16, 0, 18)
headingLabel.Position = UDim2.fromOffset(8, 4)
headingLabel.Font = Enum.Font.GothamBold
headingLabel.TextSize = 14
headingLabel.TextColor3 = Color3.fromRGB(230,230,230)
headingLabel.TextXAlignment = Enum.TextXAlignment.Left
headingLabel.Text = "Arah: -"
headingLabel.Parent = container

local centerArrow = Instance.new("TextLabel")
centerArrow.BackgroundTransparency = 1
centerArrow.Size = UDim2.fromOffset(20, 20)
centerArrow.AnchorPoint = Vector2.new(0.5, 1)
centerArrow.Position = UDim2.new(0.5, 0, 1, -4)
centerArrow.Font = Enum.Font.GothamBold
centerArrow.TextSize = 16
centerArrow.TextColor3 = Color3.fromRGB(255, 90, 90)
centerArrow.Text = "▲"
centerArrow.Parent = container

local tapeHolder = Instance.new("Frame")
tapeHolder.Name = "TapeHolder"
tapeHolder.BackgroundTransparency = 1
tapeHolder.Size = UDim2.new(1, 0, 1, -20) -- ruang untuk heading
tapeHolder.Position = UDim2.fromOffset(0, 20)
tapeHolder.Parent = container

local SEG_W = 360 * PIXELS_PER_DEG
local tape = Instance.new("Frame")
tape.Name = "Tape"
tape.BackgroundTransparency = 1
tape.Size = UDim2.fromOffset(SEG_W * 3, tapeHolder.AbsoluteSize.Y)
tape.Position = UDim2.fromOffset(0, 0)
tape.Parent = tapeHolder

tapeHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	tape.Size = UDim2.fromOffset(SEG_W * 3, tapeHolder.AbsoluteSize.Y)
end)

local function addTick(parent, x, h)
	local tick = Instance.new("Frame")
	tick.Size = UDim2.fromOffset(2, h)
	tick.AnchorPoint = Vector2.new(0.5, 1)
	tick.Position = UDim2.fromOffset(x, tapeHolder.AbsoluteSize.Y - 4)
	tick.BackgroundColor3 = Color3.fromRGB(220,220,220)
	tick.BorderSizePixel = 0
	tick.Parent = parent
	return tick
end

local function addText(parent, x, text, size)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = size
	lbl.TextColor3 = Color3.fromRGB(230,230,230)
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.fromOffset(x, tapeHolder.AbsoluteSize.Y - 6 - TICK_HEIGHT_MAX)
	lbl.Size = UDim2.fromOffset(44, 18)
	lbl.Parent = parent
	return lbl
end

-- Label pita dalam Bahasa Indonesia (singkat)
-- U, TL, T, TG, S, BD, B, BL
local function labelForDeg(degInt)
	local d = (degInt % 360 + 360) % 360
	if d == 0   then return "U"  -- Utara
	elseif d == 45  then return "TL" -- Timur Laut
	elseif d == 90  then return "T"  -- Timur
	elseif d == 135 then return "TG" -- Tenggara
	elseif d == 180 then return "S"  -- Selatan
	elseif d == 225 then return "BD" -- Barat Daya
	elseif d == 270 then return "B"  -- Barat
	elseif d == 315 then return "BL" -- Barat Laut
	end
	return nil
end

local function buildSegment(parent, xOffset)
	for deg = 0, 359, TICK_EVERY do
		local px = xOffset + deg * PIXELS_PER_DEG
		local lbl = labelForDeg(deg)
		if lbl then
			addTick(parent, px, TICK_HEIGHT_MAX)
			addText(parent, px, lbl, 12)
		elseif deg % 30 == 0 then
			addTick(parent, px, TICK_HEIGHT_MID)
			addText(parent, px, tostring(deg), 10)
		else
			addTick(parent, px, TICK_HEIGHT_MIN)
		end
	end
end

buildSegment(tape, 0)
buildSegment(tape, SEG_W)
buildSegment(tape, SEG_W * 2)

-- Nama arah lengkap untuk heading
local FULL_DIRS = {
	"Utara", "Timur Laut", "Timur", "Tenggara",
	"Selatan", "Barat Daya", "Barat", "Barat Laut"
}

-- =======================
-- UPDATE LOOP
-- =======================
local function updateTape()
	if not cam then return end
	local look = cam.CFrame.LookVector
	local deg = yawDegFromLook(look) -- 0..359.999

	-- posisikan pita agar derajat 'deg' berada di tengah container
	local centerX = math.floor(container.AbsoluteSize.X / 2 + 0.5)
	local desired = centerX - (SEG_W + deg * PIXELS_PER_DEG)
	tape.Position = UDim2.fromOffset(desired, 0)

	-- Teks heading: Bahasa Indonesia
	local idx8 = math.floor((deg + 22.5) / 45) % 8 + 1
	headingLabel.Text = ("Arah: %s (%.0f°)"):format(FULL_DIRS[idx8], deg)
end

local function rebuildTicksY()
	for _, c in ipairs(tape:GetChildren()) do
		if c:IsA("Frame") then
			c.Position = UDim2.fromOffset(c.Position.X.Offset, tapeHolder.AbsoluteSize.Y - 4)
		elseif c:IsA("TextLabel") then
			c.Position = UDim2.fromOffset(c.Position.X.Offset, tapeHolder.AbsoluteSize.Y - 6 - TICK_HEIGHT_MAX)
		end
	end
end

tapeHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	tape.Size = UDim2.fromOffset(SEG_W * 3, tapeHolder.AbsoluteSize.Y)
	rebuildTicksY()
	updateTape()
end)
container:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTape)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateTape)

RunService.RenderStepped:Connect(function()
	updateTape()
end)

task.defer(function()
	for _ = 1, 5 do
		updateTape()
		task.wait(0.05)
	end
end)

-- SCRIPT CIMEATIC / SINEMATIK PHOTO
-- SCRIPT CIMEATIC / SINEMATIK PHOTO
local lp=game:GetService("Players").LocalPlayer; local pg=lp:WaitForChild("PlayerGui")
local uis=game:GetService("UserInputService"); local cam=workspace.CurrentCamera
local on=false
local sg=Instance.new("ScreenGui",pg); sg.Name="PhotoMode"; sg.IgnoreGuiInset=true
local top=Instance.new("Frame",sg); top.BackgroundColor3=Color3.new(0,0,0); top.Size=UDim2.new(1,0,0,0)
local bot=Instance.new("Frame",sg); bot.BackgroundColor3=Color3.new(0,0,0); bot.AnchorPoint=Vector2.new(0,1)
bot.Position=UDim2.new(0,0,1,0); bot.Size=UDim2.new(1,0,0,0)
uis.InputBegan:Connect(function(i,gp)
	if gp or i.KeyCode~=Enum.KeyCode.C then return end
	on = not on
	-- hide other guis
	for _,g in ipairs(pg:GetChildren()) do if g~=sg then g.Enabled = not on end end
	-- bars
	top:TweenSize(UDim2.new(1,0,0,on and 60 or 0), "Out","Quad",0.2,true)
	bot:TweenSize(UDim2.new(1,0,0,on and 60 or 0), "Out","Quad",0.2,true)
	-- FOV subtle
	cam.FieldOfView = on and 75 or 70
end)

-- SCRIPT ID SERVER, PLACE ID, WAKTU, SPEED, DLL
-- SCRIPT ID SERVER, PLACE ID, WAKTU, SPEED, DLL
-- LocalScript @ StarterPlayerScripts

local CollectionService = game:GetService("CollectionService")
local GuiService        = game:GetService("GuiService")
local Stats             = game:FindService("Stats") -- bisa nil di beberapa environment

local player            = Players.LocalPlayer
local cam               = workspace.CurrentCamera

-- =========================
-- KONFIGURASI: ON / OFF
-- =========================
local SHOW = {
	-- Server-ish
	ServerID   = true,
	PlaceId    = true,
	PlaceLink  = true,   -- baris "Link    : roblox.com/games/<id>" di panel info
	PlayerCnt  = true,
	Uptime     = true,
	TimeWIB    = true,   -- waktu Indonesia (UTC+7)

	-- Map-ish
	Coords     = true,
	Heading    = true,
	Speed      = true,
	FPS        = true,
	Ping       = true,
	Waypoint   = false,  -- set true jika isi WAYPOINT di bawah
	ZoneName   = false,  -- tag Part/Model dengan CollectionService "Zone"
}

-- Waypoint opsional (jika SHOW.Waypoint = true)
local WAYPOINT = nil -- contoh: Vector3.new(100, 50, -200)

-- =========================
-- HELPERS
-- =========================
local function mkLabel(parent, anchor, pos)
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(0,0,0)
	frame.BackgroundTransparency = 0.35
	frame.BorderSizePixel = 0
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.AnchorPoint = anchor
	frame.Position = pos
	frame.Parent = parent

	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = Color3.fromRGB(255,255,255)
	stroke.Transparency = 0.75
	stroke.Thickness = 1

	local pad = Instance.new("UIPadding", frame)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextColor3 = Color3.fromRGB(235,235,235)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Parent = frame
	return label, frame
end

local function shortJobId(id)
	if not id or #id == 0 then return "?" end
	return string.sub(id, 1, 8) .. "…" .. string.sub(id, -6)
end

local function fmt(n, dig)
	local p = 10 ^ (dig or 0)
	return math.floor(n * p + 0.5)/p
end

local function headingText(dir: Vector3)
	local angle = math.atan2(dir.X, dir.Z)
	local deg = math.deg(angle)
	local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
	local idx = math.floor((deg + 22.5) / 45) % 8 + 1
	return dirs[idx], math.floor((deg + 360) % 360 + 0.5)
end

local function getPingMs()
	if not Stats then return nil end
	local net = Stats:FindFirstChild("Network")
	if not net then return nil end
	local item = net.ServerStatsItem and net.ServerStatsItem:FindFirstChild("Data Ping")
	if not item or not item.GetValue then return nil end
	local ok, val = pcall(function() return item:GetValue() end)
	if ok and typeof(val) == "number" then return math.floor(val + 0.5) end
	return nil
end

local function nearestZoneName(pos: Vector3)
	local candidates = CollectionService:GetTagged("Zone")
	local bestName, bestDist = nil, math.huge
	for _, inst in ipairs(candidates) do
		local p
		if inst:IsA("BasePart") then
			p = inst.Position
		elseif inst:IsA("Model") and inst.PrimaryPart then
			p = inst.PrimaryPart.Position
		end
		if p then
			local d = (p - pos).Magnitude
			if d < bestDist then
				bestDist = d
				bestName = inst.Name
			end
		end
	end
	return bestName
end

-- WIB (UTC+7)
local MONTH_ID = {
	"Januari","Februari","Maret","April","Mei","Juni",
	"Juli","Agustus","September","Oktober","November","Desember"
}
local function nowWIBString()
	local utcEpoch = os.time(os.date("!*t"))
	local wibEpoch = utcEpoch + 7*3600
	local t = os.date("!*t", wibEpoch)
	return string.format("%02d %s %04d %02d:%02d:%02d",
		t.day, MONTH_ID[t.month] or tostring(t.month), t.year, t.hour, t.min, t.sec)
end

local function placeUrl()
	return ("https://www.roblox.com/games/%d"):format(game.PlaceId)
end

-- =========================
-- GUI
-- =========================
local pg = player:WaitForChild("PlayerGui")
local existing = pg:FindFirstChild("HUD_MAP_INFO")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "HUD_MAP_INFO"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 60
gui.Parent = pg

-- Container stack kiri-bawah (LinkBox DI ATAS, Panel info DI BAWAH)
local stack = Instance.new("Frame")
stack.Name = "StackLeft"
stack.Parent = gui
stack.AnchorPoint = Vector2.new(0,1)
stack.Position = UDim2.new(0, 12, 1, -12)
stack.BackgroundTransparency = 1
stack.AutomaticSize = Enum.AutomaticSize.XY

local stackLayout = Instance.new("UIListLayout", stack)
stackLayout.FillDirection = Enum.FillDirection.Vertical
stackLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
stackLayout.VerticalAlignment = Enum.VerticalAlignment.Top
stackLayout.Padding = UDim.new(0, 6)

-- LinkBox (selalu tampil di baris paling atas)
local linkBox = Instance.new("TextBox")
linkBox.Name = "LinkBox"
linkBox.Parent = stack
linkBox.BackgroundColor3 = Color3.fromRGB(12,12,16)
linkBox.BackgroundTransparency = 0.1
linkBox.BorderSizePixel = 0
linkBox.ClearTextOnFocus = false
linkBox.Font = Enum.Font.Code
linkBox.TextSize = 14
linkBox.TextXAlignment = Enum.TextXAlignment.Left
linkBox.TextYAlignment = Enum.TextYAlignment.Center
linkBox.TextColor3 = Color3.fromRGB(235,235,245)
linkBox.TextEditable = true
linkBox.Size = UDim2.fromOffset(360, 28)
linkBox.Text = placeUrl()
local lbCorner = Instance.new("UICorner", linkBox); lbCorner.CornerRadius = UDim.new(0, 8)
local lbStroke = Instance.new("UIStroke", linkBox); lbStroke.Color = Color3.fromRGB(255,255,255); lbStroke.Transparency = 0.82
local lbPad = Instance.new("UIPadding", linkBox); lbPad.PaddingLeft = UDim.new(0, 8); lbPad.PaddingRight = UDim.new(0, 8)

-- Panel info (tetap seperti sebelumnya)
local leftLabel, leftFrame = mkLabel(stack, Vector2.new(0,0), UDim2.fromOffset(0, 0)) -- ditaruh di bawah LinkBox via UIListLayout

-- =========================
-- STATE
-- =========================
local hrp
local function bindChar(char)
	hrp = nil
	if not char then return end
	hrp = char:WaitForChild("HumanoidRootPart", 5)
end
if player.Character then bindChar(player.Character) end
player.CharacterAdded:Connect(bindChar)

-- FPS estimator
local smoothedDt = 1/60
RunService.RenderStepped:Connect(function(dt)
	smoothedDt = smoothedDt*0.9 + dt*0.1
end)

-- =========================
-- UPDATE LOOP
-- =========================
local accum = 0
RunService.RenderStepped:Connect(function(dt)
	accum += dt
	if accum < 0.2 then return end
	accum = 0

	-- sinkronkan LinkBox dengan PlaceId (kecuali saat sedang fokus ngetik)
	local wantText = placeUrl()
	if linkBox.Text ~= wantText and not linkBox:IsFocused() then
		linkBox.Text = wantText
	end

	local lines = {}

	-- ===== SERVER =====
	if SHOW.ServerID then
		table.insert(lines, ("ServerID: %s"):format(shortJobId(game.JobId)))
	end
	if SHOW.PlaceId then
		table.insert(lines, ("PlaceId : %d"):format(game.PlaceId))
	end
	if SHOW.PlaceLink then
		table.insert(lines, ("Link    : roblox.com/games/%d"):format(game.PlaceId))
	end
	if SHOW.PlayerCnt then
		table.insert(lines, ("Players : %d"):format(#Players:GetPlayers()))
	end
	if SHOW.Uptime then
		local t = math.floor(workspace.DistributedGameTime)
		table.insert(lines, ("Uptime  : %02d:%02d:%02d"):format(math.floor(t/3600), math.floor((t%3600)/60), t%60))
	end
	if SHOW.TimeWIB then
		table.insert(lines, ("Waktu : %s (WIB)"):format(nowWIBString()))
	end

	table.insert(lines, " ")

	-- ===== MAP =====
	local look = cam and cam.CFrame.LookVector or Vector3.zAxis
	local pos  = hrp and hrp.Position

	if SHOW.Coords then
		if pos then
			table.insert(lines, ("XYZ    : %s, %s, %s"):format(fmt(pos.X,1), fmt(pos.Y,1), fmt(pos.Z,1)))
		else
			table.insert(lines, "XYZ    : -")
		end
	end
	if SHOW.Heading then
		local hText, deg = headingText(look)
		table.insert(lines, ("Heading: %s (%d°)"):format(hText, deg))
	end
	if SHOW.Speed then
		local speed = (hrp and hrp.Velocity and hrp.Velocity.Magnitude) or 0
		table.insert(lines, ("Speed  : %s m/s"):format(fmt(speed,1)))
	end
	if SHOW.Waypoint and WAYPOINT and pos then
		local dist = (WAYPOINT - pos).Magnitude
		table.insert(lines, ("To WP  : %s m"):format(fmt(dist,1)))
	end
	if SHOW.ZoneName and pos then
		local zn = nearestZoneName(pos)
		if zn then table.insert(lines, ("Zone   : %s"):format(zn)) end
	end
	if SHOW.FPS then
		local fps = math.floor(1 / math.max(smoothedDt, 1e-3) + 0.5)
		table.insert(lines, ("FPS    : %d"):format(fps))
	end
	if SHOW.Ping then
		local ping = getPingMs()
		table.insert(lines, ("Ping   : %s ms"):format(ping and tostring(ping) or "-"))
	end

	leftLabel.Text = table.concat(lines, "\n")
end)

-- =========================
-- COPY LINK (klik LinkBox)
-- =========================
local function tryCopyClipboard(text)
	if GuiService and typeof(GuiService.CopyToClipboard) == "function" then
		local ok = pcall(function() GuiService:CopyToClipboard(text) end)
		if ok then return true end
	end
	if typeof(setclipboard) == "function" then
		local ok = pcall(function() setclipboard(text) end)
		if ok then return true end
	end
	return false
end

-- Fokus → auto-select
linkBox.Focused:Connect(function()
	task.defer(function()
		linkBox.SelectionStart = 1
		linkBox.CursorPosition = #linkBox.Text + 1
	end)
end)

-- Klik → fokus + auto-select + coba copy
linkBox.MouseButton1Click:Connect(function()
	linkBox:CaptureFocus()
	task.defer(function()
		linkBox.SelectionStart = 1
		linkBox.CursorPosition = #linkBox.Text + 1
	end)
	local ok = tryCopyClipboard(linkBox.Text)
	if ok then
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = "Disalin",
				Text  = "Link map disalin ke clipboard.",
				Duration = 2.0
			})
		end)
	else
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = "Salin Manual",
				Text  = "Command+C (Mac) / Ctrl+C (PC) / tap & tahan (Mobile).",
				Duration = 3
			})
		end)
	end
end)

-- =========================
-- Klik panel info: info ringkas (opsional)
-- =========================
leftLabel.Active = true
leftLabel.MouseButton1Click:Connect(function()
	local coordText = "-"
	if hrp then
		local p = hrp.Position
		coordText = string.format("X=%.1f Y=%.1f Z=%.1f", p.X, p.Y, p.Z)
	end
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Info",
			Text  = string.format(
				"ServerID: %s\nPlaceId : %d\nKoordinat: %s\nLink    : %s",
				shortJobId(game.JobId), game.PlaceId, coordText, placeUrl()
			),
			Duration = 4
		})
	end)
end)