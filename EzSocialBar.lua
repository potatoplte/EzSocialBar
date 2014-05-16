-----------------------------------------------------------------------------------------------
-- Client Lua Script for EzSocialBar
-- Copyright (c) NCsoft. All rights reserved
----------------------------------------------------------------------------------------------- 
require "Window"
require "FriendshipLib"
require "GuildLib"

-----------------------------------------------------------------------------------------------
-- EzSocialBar Module Definition
-----------------------------------------------------------------------------------------------
local EzSocialBar = {} 

local function CPrint(string)
	ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Command, string, "")
end

-- table dump functions
function table.val_to_str ( v )
  if "string" == type( v ) then
    v = string.gsub( v, "\n", "\\n" )
    if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
      return "'" .. v .. "'"
    end
    return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
  else
    return "table" == type( v ) and table.tostring( v ) or
      tostring( v )
  end
end
function table.key_to_str ( k )
  if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
    return k
  else
    return "[" .. table.val_to_str( k ) .. "]"
  end
end
function table.tostring( tbl )
  local result, done = {}, {}
  for k, v in ipairs( tbl ) do
    table.insert( result, table.val_to_str( v ) )
    done[ k ] = true
  end
  for k, v in pairs( tbl ) do
    if not done[ k ] then
      table.insert( result,
        table.key_to_str( k ) .. "=" .. table.val_to_str( v ) )
    end
  end
  return "{" .. table.concat( result, "," ) .. "}"
end
function table.reverse ( tab )
    local size = #tab
    local newTable = {}
 
    for i,v in ipairs ( tab ) do
        newTable[size-i] = v
    end
 
    return newTable
end

function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

--Default Settings
local DefaultSettings = {	
		--position of the window
		position = { 
			top = -3,
			left = 0,
			right = 500,
			bottom = 70,
		},
			
		-- which nodes we are displaying
		noduleStates = {			
			Friends = true,
			Guild = true,
			Circles = false,	
		},
							
		-- some other control settings
		notificationDuration = 10,
		updateFreq = 1,
		displayBackground = true,
		isLocked = true,
		playSound = false,
		enableNotifications = true,
		isResizeable = false,
		showMail = true,
		showWelcomeMessage = true,
	}
	
local LoadingState = { Unloaded = 1, Restore = 2, Loaded = 4 }	
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function EzSocialBar:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 	
	self.LoadingState = LoadingState.Unloaded	
		
    -- varaibles holding display data
	self.settings = deepcopy(DefaultSettings)			
	self.data = {
		onlineFriendsCount = 0,
		accountOnlineFriendsCount = 0,
		onlineGuildCount = 0,
		hasGuild = false,
		circles =  { },		
		UnreadMessages = 0,
	}		
		
    return o
end

function EzSocialBar:Init()	
    Apollo.RegisterAddon(self, false, "", { })
end 

-----------------------------------------------------------------------------------------------
-- EzSocialBar Loads and save Methods
-----------------------------------------------------------------------------------------------
function EzSocialBar:OnLoad()
	Apollo.RegisterSlashCommand("ezs", "EzSlashCommand", self)
	self.xmlDoc = XmlDoc.CreateFromFile("EzSocialBar.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end
function EzSocialBar:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return nil
	else
		return self.settings
	end		
end
function EzSocialBar:OnRestore(eType, tData)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end		

	--Load in settings
	--self.settings = DefaultSettings 	
	for Dkey, Dvalue in pairs(self.settings) do
		if tData[Dkey] ~= nil then
			self.settings[Dkey] = tData[Dkey]
		end
	end		
	
	if self.LoadingState == LoadingState.Loaded then
		-- we have already loaded a defualt bar, rebuild with new settings
		self:Rebuild()
	end	
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar ApplySettings
-----------------------------------------------------------------------------------------------
function EzSocialBar:ApplySettings()	
	--movable
	if self.settings.isLocked then
		self.mainContainer:RemoveStyle("Moveable")
	else
		self.mainContainer:AddStyle("Moveable")
	end
	
	-- show background	
	if self.settings.displayBackground then
		self.background:Show(true)
	else
		self.background:Show(false)
	end	
	
	-- show Mail	
	if self.settings.showMail then
		self.mailControl:Show(true)
	else
		self.mailControl:Show(false)
	end	
	
			
	--set the position of the window
	self.mainContainer:SetAnchorOffsets(
		self.settings.position.left,
	 	self.settings.position.top,
		self.settings.position.right,
	 	self.settings.position.bottom)
	
	--local l,t,r,b = self.mainContainer:GetAnchorOffsets()
	--CPrint(string.format("offsets: l:%i t:%i b:%i r:%i", l, t, r, b))

end

-----------------------------------------------------------------------------------------------
-- EzSocialBar OnDocLoaded
-----------------------------------------------------------------------------------------------
function EzSocialBar:OnDocLoaded()
	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.mainContainer = Apollo.LoadForm(self.xmlDoc, "EzSocialBarForm", nil, self)				
	    self.mainContainer:Show(true)	
		
		self.background = self.mainContainer:FindChild("SocialbarBackground")
		self.mailControl = self.mainContainer:FindChild("MailNodule")
		
		self.notificationsWindow = self.mainContainer:FindChild("EzSocialNotification")
		self.notificationsWindow:Show(false)		
		
		self.optionsWindow = Apollo.LoadForm(self.xmlDoc, "EzSocialSettingsForm", nil, self)
		self.optionsWindow:Show(false)
				
		--timer handlers		
		Apollo.CreateTimer("EzUpdateTimer", 5, true)
		Apollo.CreateTimer("NotificationTimer", 10.0, false)		
		Apollo.RegisterTimerHandler("NotificationTimer", "OnNotificationTimerTick", self)
		Apollo.RegisterTimerHandler("EzUpdateTimer", "OnEzTimerTick", self)		
		Apollo.StopTimer("NotificationTimer")
		Apollo.StopTimer("EzUpdateTimer")

		-- Register for some Events
		Apollo.RegisterEventHandler("FriendshipUpdateOnline", "OnFriendshipUpdateOnline", self)	
		Apollo.RegisterEventHandler("FriendshipInvitesRecieved", "OnFriendshipRequest", self)		
		Apollo.RegisterEventHandler("FriendshipAccountInvitesRecieved", "OnFriendshipAccountInvitesRecieved", self)
		Apollo.RegisterEventHandler("GuildChange", "OnGuildChanged", self)
							
		self:Rebuild()
		self:SetMailIcon(0)
		self:SetFriendsPending(0)
		Apollo.StartTimer("EzUpdateTimer")		
		self.LoadingState = LoadingState.Loaded		
		
		if self.settings.showWelcomeMessage then
			CPrint("Thank you for downloading the EzSocial Bar.")
			CPrint("please use /ezs options to configure this addon and hide this message")
			CPrint("Update 0.9a: If you cannot see your bar after the update, please do /ezs reset")
		end
	end
end

function EzSocialBar:BuildSocialBar()
	-- Builds the acctual social bar			
	local currentWidth = 0	
	local container = self.mainContainer:FindChild("EzSocialBar")
	container:DestroyChildren() -- remove all components ?is there a perf issue here??
	local ctrl, w	
	
	-- Build Friends Bar
	if self.settings.noduleStates.Friends then	 
		--CPrint("Building Friends nodule")
		ctrl, w = self:BuildItem("FriendsNodule", "FriendsView", container)
		ctrl:SetAnchorPoints(0, 0, 0, 1)
		ctrl:SetAnchorOffsets(currentWidth, 0, currentWidth + w, 0)
		currentWidth = currentWidth + w		
		--assign to the windows
	end
	
	-- Build Guilds Bar
	if self.settings.noduleStates.Guild then
		--CPrint("Building Guild nodule")
		ctrl, w = self:BuildItem("GuildsNodule", "GuildsView", container)
		ctrl:SetAnchorPoints(0, 0, 0, 1)
		ctrl:SetAnchorOffsets(currentWidth, 0, currentWidth + w, 0)
		currentWidth = currentWidth + w		
		--assign to the windows
	end
	
	if self.settings.noduleStates.Circles and #self.data.circles > 0  then -- dont dispaly circles unless there are some
		--CPrint("Building Circles nodule")
		ctrl, w = self:BuildItem("CirclesNodule", "CirclesView", container)
		ctrl:SetAnchorPoints(0, 0, 0, 1)
		ctrl:SetAnchorOffsets(currentWidth, 0, currentWidth + w, 0)
		currentWidth = currentWidth + w	
		
		local circlesCount = 0
	 	for i = 1, #self.data.circles do			
			ctrl, w = self:BuildItem("CircleNodule", "Circle_" .. i, container)
			ctrl:SetAnchorPoints(0, 0, 0, 1)
			ctrl:SetAnchorOffsets(currentWidth, 0, currentWidth + w, 0)	
			currentWidth = currentWidth + w	
			circlesCount = circlesCount + 1	
		end	
	end	
	
	-- Now we know how long to container is, we can adjust the poisition of
	--the acctual mainContainer
	--   according to the users settins, position should not be lost
	self.settings.position.right = self.settings.position.left + currentWidth + 40 -- 40 for mail container? 
	--CPrint(string.format("Width: w%i cw: r:%i", currentWidth, self.settings.position.right))
	self:ApplySettings()
end 

function EzSocialBar:BuildItem(type, name, parent)
	local newItem = Apollo.LoadForm(self.xmlDoc, type, parent, self)
	
	if newItem == nil then
		CPrint("Failed to create" .. name)		
	end
	
	newItem:SetName(name)
	return newItem, newItem:GetWidth()
end

function EzSocialBar:Rebuild()
	--CPrint("Rebuilding social bar")
	Apollo.StopTimer("EzUpdateTimer")
	self:UpdateData()
	self:BuildSocialBar()
	self:UpdateInterface()
	Apollo.StartTimer("EzUpdateTimer")
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar EzSlashCommand
-----------------------------------------------------------------------------------------------
function EzSocialBar:EzSlashCommand(sCmd, sInput) 
	local s = string.lower(sInput)
	
	if s == nil or s == "" then
		CPrint("EzSocial Bar Addon")
		CPrint("/ezs options for options menu")
		CPrint("/ezs reset to reset the addon")
		
	-- Options
	elseif s == "reset" then
		CPrint("Reseting EzSocial bar")
		self.settings = deepcopy(DefaultSettings)
		self:Rebuild()
		
	-- Options
	elseif s == "options" then
		self:ShowOptions()
	
	-- Lock / Unlock Commands
	elseif s == "lock" then
		self.settings.isLocked = true
		self:ApplySettings()
				
	elseif s == "unlock" then
		self.settings.isLocked = false
		self:ApplySettings()
		
	end	
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar SetNotification
-----------------------------------------------------------------------------------------------
function EzSocialBar:SetNotification(text)	
	-- is settings enabled
	if not self.settings.enableNotifications then
		return
	end
	
	if text == nil or text == "" then		
		self.notificationsWindow:Show(false)
		return
	end
	
	-- show a notification
	self.notificationsWindow:Show(true)
	self.notificationsWindow:FindChild("NotificationText"):SetText(text)
	Apollo.StartTimer("NotificationTimer")
	
	if self.settings.playSound then 
		Sound.Play(Sound.PlayUISocialFriendAlert)
	end
end
-----------------------------------------------------------------------------------------------
-- EzSocialBar SetMailIcon
-----------------------------------------------------------------------------------------------
function EzSocialBar:SetMailIcon(nMail)
	if nMail == 0 then
		self.mailControl:Show(false)
		return
	end	
	
	self.mailControl:FindChild("mailText"):SetText("" .. nMail)
	self.mailControl:Show(true)	
end
-----------------------------------------------------------------------------------------------
-- EzSocialBar SetFriendsPending
-----------------------------------------------------------------------------------------------
function EzSocialBar:SetFriendsPending(nFriends)
	local friendsControl = self.mainContainer:FindChild("FriendsView")
	if not self.settings.noduleStates.Friends or friendsControl == nil then
		return
	end
	
	local friendsRotateyThingy = friendsControl:FindChild("rotateythingy")
	local friendsPendingCtrl = friendsControl:FindChild("Pending")
	
	if nFriends == 0 then
		friendsRotateyThingy:Show(false)
		friendsPendingCtrl:Show(false)
	else
		friendsRotateyThingy:Show(true)
		friendsPendingCtrl:Show(true)
		friendsPendingCtrl:SetText(nFriends .. "")
		
		if self.settings.playSound then 
			Sound.Play(Sound.PlayUISocialFriendAlert)
		end		
	end	
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar OnNotificationTimerTick
-----------------------------------------------------------------------------------------------
function EzSocialBar:OnNotificationTimerTick()
	-- stop the timer, turn off the notification
	Apollo.StopTimer("NotificationTimer")
	self:SetNotification("")	
end
-----------------------------------------------------------------------------------------------
-- EzSocialBar UpdateValues
-----------------------------------------------------------------------------------------------
function EzSocialBar:OnEzTimerTick()
	self:UpdateData()	
	self:UpdateInterface()
end

function EzSocialBar:UpdateInterface()
	if self.settings.noduleStates.Friends then
		--Update Friends interface
		local totalFriends = self.data.onlineFriendsCount + self.data.accountOnlineFriendsCount	
		if totalFriends > 0 then
			self.mainContainer:FindChild("FriendsView"):FindChild("Text"):SetText(string.format("Friends: %u", totalFriends))
		else
			self.mainContainer:FindChild("FriendsView"):FindChild("Text"):SetText("Friends: --")
		end	
	end
	
	--Update Guilds interface
	if self.settings.noduleStates.Guild then
		if self.hasGuild then
			self.mainContainer:FindChild("GuildsView"):FindChild("Text"):SetText(string.format("Guild: %u", self.onlineGuildCount));
		else
			self.mainContainer:FindChild("GuildsView"):FindChild("Text"):SetText("Guild: --");
		end			
	end	
	
	--Update Circles interface
	if self.settings.noduleStates.Circles then		
		for i = 1, #self.data.circles do			
			local wnd = self.mainContainer:FindChild("Circle_"..i)
			
			if wnd ~= nil then						
				wnd:FindChild("Text"):SetText(string.format("%u", self.data.circles[i].count))
				wnd:SetTooltip(self.data.circles[i].name)
			end
		end
	end
	
	--Mail
	self:SetMailIcon(self.data.UnreadMessages)
	self:CalcFriendInvites(0)	
	
end
function EzSocialBar:UpdateData()	
	-- First Friends, only bother to update if we are showing the values	
	if self.settings.noduleStates.Friends then	
		--CPrint("Updating Friends Data")
		self.data.onlineFriendsCount = 0
		self.data.accountOnlineFriendsCount = 0
		
		for key, tFriend in pairs(FriendshipLib.GetList()) do
			if tFriend.fLastOnline == 0 then
				self.data.onlineFriendsCount = self.data.onlineFriendsCount + 1
			end
		end		
		for key, tAccFriend in pairs(FriendshipLib.GetAccountList()) do
			if tAccFriend.arCharacters then 
				self.data.accountOnlineFriendsCount = self.data.accountOnlineFriendsCount + 1
			end
		end	
	end

	-- Next Guilds
	if self.settings.noduleStates.Guild or self.settings.noduleStates.Circles then
		--CPrint("Updating Circle and Guild data")
		local guild = nil
		local circle = 1
		
		--init circles
		self.data.circles = { }
		
		--data
		for idx, guildCurr in pairs(GuildLib.GetGuilds()) do
			if guildCurr:GetType() == GuildLib.GuildType_Guild then
				guild = guildCurr
			elseif guildCurr:GetType() == GuildLib.GuildType_Circle then
				self.data.circles[circle] = { name=guildCurr:GetName(), count=guildCurr:GetOnlineMemberCount() } 				
				circle = circle  + 1
			end
		end		
		--table.reverse(self.data.circles)		
		-- assign guild numbers
		if guild == nil then
			self.hasGuild = false
			self.onlineGuildCount = 0
		else
			self.hasGuild = true
			self.onlineGuildCount = guild:GetOnlineMemberCount()
		end	
		
	end
	
	--Mail
	if self.settings.showMail then
		self.data.UnreadMessages = 0
		for idx, tMessage in pairs(MailSystemLib.GetInbox()) do
			local tMessageInfo = tMessage:GetMessageInfo()
			
			if tMessageInfo and not tMessageInfo.bIsRead then
				self.data.UnreadMessages = self.data.UnreadMessages + 1
			end
		end	
	end	
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar CalcFriendInvites
-----------------------------------------------------------------------------------------------
function EzSocialBar:CalcFriendInvites(nDelta)
	--nDelta is a testing value
	local lastUnseen = ""
	local nUnseenFriendInviteCount = nDelta
	
	for idx, tInvite in pairs(FriendshipLib.GetInviteList()) do
		if tInvite.bIsNew then
			nUnseenFriendInviteCount = nUnseenFriendInviteCount + 1
			lastUnseen  = tInvite.strCharacterName
		end
	end
	for idx, tInvite in pairs(FriendshipLib.GetAccountInviteList()) do
		if tInvite.bIsNew then
			nUnseenFriendInviteCount = nUnseenFriendInviteCount + 1
			lastUnseen = tInvite.strDisplayName
		end
	end

	self:SetFriendsPending(nUnseenFriendInviteCount)
	
	if nUnseenFriendInviteCount == 1 then
		self:SetNotification(string.format("Friendship invite from " .. lastUnseen))
	elseif nUnseenFriendInviteCount  > 1 then
		self:SetNotification(string.format("%i Friendship invites pending", nUnseenFriendInviteCount))
	end
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar Event Listeners
-----------------------------------------------------------------------------------------------
function EzSocialBar:OnFriendshipUpdateOnline(nFriendId)
	local tFriend = FriendshipLib.GetById(nFriendId)
	
	--  honestly, idk, i found this in FriendsList - wut do
	if not tFriend.bFriend then
		return
	end	
	
	if tFriend.fLastOnline == 0 then --just come online
		self:SetNotification(string.format("%s has come Online", tFriend.strCharacterName))
	else
		self:SetNotification(string.format("%s has gone Offline", tFriend.strCharacterName))
	end	
end

function EzSocialBar:OnFriendshipRequest(tRequest)
	self:CalcFriendInvites(0)
end

function EzSocialBar:OnFriendshipAccountInvitesRecieved(tInviteList)			
	self:CalcFriendInvites(0)
end

-----------------------------------------------------------------------------------------------
-- EzSocialBarForm Functions
-----------------------------------------------------------------------------------------------

function EzSocialBar:OnFriendsButtonDown( wndHandler, wndControl, eMouseButton )
	Event_FireGenericEvent("GenericEvent_OpenFriendsPanel")
end

function EzSocialBar:OnGuildButtonDown( wndHandler, wndControl, eMouseButton )	
	Event_FireGenericEvent("GenericEvent_OpenGuildPanel")
end

function EzSocialBar:OnCircleButtonDown( wndHandler, wndControl, eMouseButton )	
	Event_FireGenericEvent("GenericEvent_InitializeCircles") --TODO: can this be fixed?
end

-- has clicked the notification, register as seen and hide
function EzSocialBar:OnNotificationClick( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY, bDoubleClick, bStopPropagation )
	self:SetNotification("")
end

function EzSocialBar:OnMailIconClick( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY, bDoubleClick, bStopPropagation )
	Event_FireGenericEvent("GenericEvent_OpenMailPanel")
end

function EzSocialBar:OnFormMove( wndHandler, wndControl, nOldLeft, nOldTop, nOldRight, nOldBottom )
	local l,t,r,b = self.mainContainer:GetAnchorOffsets()	
	self.settings.position.left = l
	self.settings.position.top = t
	self.settings.position.right = r
	self.settings.position.bottom = b	
end

function EzSocialBar:OnGuildChanged()
	self:Rebuild()
end

-----------------------------------------------------------------------------------------------
-- EzSocial Options
-----------------------------------------------------------------------------------------------
function EzSocialBar:ShowOptions() 
	-- only developer options atm
	-- if you change to dev mode, strange things will happen
		
	self.optionsWindow:FindChild("toggleLock"):SetCheck(self.settings.isLocked)
	self.optionsWindow:FindChild("toggleBackground"):SetCheck(self.settings.displayBackground)
	self.optionsWindow:FindChild("toggleSounds"):SetCheck(self.settings.playSound)
	self.optionsWindow:FindChild("toggleNotifications"):SetCheck(self.settings.enableNotifications)
	self.optionsWindow:FindChild("toggleMail"):SetCheck(self.settings.showMail)
	self.optionsWindow:FindChild("toggleWelcome"):SetCheck(self.settings.showWelcomeMessage)
	
	self.optionsWindow:FindChild("ShowFriends"):SetCheck(self.settings.noduleStates.Friends)
	self.optionsWindow:FindChild("ShowGuild"):SetCheck(self.settings.noduleStates.Guild)
	self.optionsWindow:FindChild("ShowCircles"):SetCheck(self.settings.noduleStates.Circles)	
	
	self.optionsWindow:Show(true)	
end

---------------------------------------------------------------------------------------------------
-- EzSocialSettings Functions
---------------------------------------------------------------------------------------------------
function EzSocialBar:OnLockToggle(wndHandler, wndControl, eMouseButton )	
	self.settings.isLocked = wndControl:IsChecked()
	self:ApplySettings()
end
function EzSocialBar:OnBackgroundToggle( wndHandler, wndControl, eMouseButton )
	self.settings.displayBackground = wndControl:IsChecked()
	self:ApplySettings()
end
function EzSocialBar:OnSoundsToggle( wndHandler, wndControl, eMouseButton )
	self.settings.playSound = wndControl:IsChecked()
	self:ApplySettings()
end
function EzSocialBar:OnNotificationsToggle( wndHandler, wndControl, eMouseButton )
	self.settings.enableNotifications = wndControl:IsChecked()
	self:ApplySettings()
end
function EzSocialBar:OnMailToggle( wndHandler, wndControl, eMouseButton )
	self.settings.showMail = wndControl:IsChecked()
	self:ApplySettings()
end
function EzSocialBar:OnWelcomeToggle( wndHandler, wndControl, eMouseButton )
	self.settings.showWelcomeMessage = wndControl:IsChecked()
end

function EzSocialBar:OnShowFriendsToggle( wndHandler, wndControl, eMouseButton )
	self.settings.noduleStates.Friends = wndControl:IsChecked()	
	self:Rebuild()
end
function EzSocialBar:OnShowGuildToggle( wndHandler, wndControl, eMouseButton )
	self.settings.noduleStates.Guild = wndControl:IsChecked()
	self:Rebuild()
end
function EzSocialBar:OnShowCirclesToggle( wndHandler, wndControl, eMouseButton )
	self.settings.noduleStates.Circles = wndControl:IsChecked()
	self:Rebuild()
end

function EzSocialBar:OnOptionsClose( wndHandler, wndControl, eMouseButton )
	self.optionsWindow:Show(false)
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar Instance
-----------------------------------------------------------------------------------------------
local EzSocialBarInst = EzSocialBar:new()
EzSocialBarInst:Init()
