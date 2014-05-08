-----------------------------------------------------------------------------------------------
-- Client Lua Script for EzSocialBar
-- Copyright (c) NCsoft. All rights reserved
----------------------------------------------------------------------------------------------- 
require "Window"

-- todo
-- ShowNotification isnt working, possibly need another way of showing these
--  See if Guild invite is acctually needed, if i am invited to a circle do i get a notification about it?
--  Any way to tell when a guild member has come/gone on/offline?
--  Friends - Account vs Friends can we check the two for cross overs? e.g. done see Dark 2x if i have his acc and main character
 
-----------------------------------------------------------------------------------------------
-- EzSocialBar Module Definition
-----------------------------------------------------------------------------------------------
local EzSocialBar = {} 

local function CPrint(string)
	ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Command, string, "")
end
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function EzSocialBar:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
	self.TimerName = "EzSocialUpdateTimer"
	self.onlineFriendsCount = 0
	self.accountOnlineFriendsCount = 0
	self.onlineGuildCount = 0
	self.hasGuild = false
	self.circleMemberStatuses =  { false, false, false, false, false}	
	self.circleMembers =  { 0, 0, 0, 0, 0 }	
	self.UnreadMessages = 0
	
	self.settings = {
		position = { 
			top = -3,
			left = -600,
			right = 2,
			bottom = 70,
 		},
		
		displayBackground = true,
		isLocked = true,
		playSound = false,
		notificationDuration = 5,
		updateFreq = 5,
		enableNotifications = true,
		developerMode = true, -- !!!! Remember to change this !!!
		isResizeable = false,
	}
	
    return o
end

function EzSocialBar:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- EzSocialBar Loads and save Methods
-----------------------------------------------------------------------------------------------
function EzSocialBar:OnLoad()
	Apollo.RegisterSlashCommand("ezs", "EzSlashCommand", self)
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("EzSocialBar.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

function EzSocialBar:OnSave(eType)
	--CPrint("saving state::")
	if etype ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return nil
	else
		return self.settings
	end		
end

function EzSocialBar:OnRestore(eType, tData)
	--CPrint("Restoring saved state::")	
	for Dkey, Dvalue in pairs(defaultSettings) do
		if tData[Dkey] ~= nil then
			self.settings[Dkey] = tData[Dkey]
		end
	end 
	
	self:ApplySettings()
end


function EzSocialBar:ApplySettings()		
		--set the position of the window		
		--CPrint(string.format("Setting Pos: l:%i t:%i b:%i r:%i", self.settings.position.left, self.settings.position.top,
						 --self.settings.position.right, self.settings.position.bottom))			
						
		self.wndMain:SetAnchorOffsets(
			self.settings.position.left,
		 	self.settings.position.top,
			self.settings.position.right,
		 	self.settings.position.bottom)
		
		--movable
		if self.settings.isLocked then
			self.wndMain:RemoveStyle("Moveable")
		else
			self.wndMain:AddStyle("Moveable")
		end
		
		-- show background
		if self.settings.displayBackground then
			self.background:Show(true)
		else
			self.background:Show(false)
		end	
		
		--Resizeable
		if self.settings.isResizeable then

			self.wndMain:FindChild("resizeBackground"):Show(true)
			self.wndMain:AddStyle("Sizeable")
		else
			self.wndMain:FindChild("resizeBackground"):Show(false)
			self.wndMain:RemoveStyle("Sizeable")
		end	
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar OnDocLoaded
-----------------------------------------------------------------------------------------------
function EzSocialBar:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "EzSocialBarForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
			
		end
		
	    self.wndMain:Show(true)
				
		-- Register to listen into Events
		self.background = self.wndMain:FindChild("Background")
		self.friendList = self.wndMain:FindChild("btnFriendsDisplay")
		self.guildDisplay = self.wndMain:FindChild("btnDisplayGuild")
		self.circleDisplays = { }
		self.circleDisplays[1] = self.wndMain:FindChild("btnHoldC1")
		self.circleDisplays[2] = self.wndMain:FindChild("btnHoldC2")
		self.circleDisplays[3] = self.wndMain:FindChild("btnHoldC3")
		self.circleDisplays[4] = self.wndMain:FindChild("btnHoldC4")
		self.circleDisplays[5] = self.wndMain:FindChild("btnHoldC5")
		
		--The notification Window
		self.notificationTimerName = "EzSocialNotificationTimer"
		self.notifcationTimer = nil;
		self.notificationWindow = self.wndMain:FindChild("EzSocialNotification")
		self.notificationWindow:Show(false)
		self.notification = self.notificationWindow:FindChild("NotificationText")
		self.mailControl = self.wndMain:FindChild("mailControl")
		self:HideMailIcon()	
		
		--timer handlers
		Apollo.RegisterTimerHandler(self.notificationTimerName, "OnNotificationTimerTick", self)
		Apollo.RegisterTimerHandler(self.TimerName, "OnEzTimerTick", self)

		-- register for some apollo events
		Apollo.RegisterEventHandler("FriendshipUpdateOnline", "OnFriendshipUpdateOnline", self)		
		Apollo.RegisterEventHandler("FriendshipRequest", "OnFriendshipRequest", self)		
		Apollo.RegisterEventHandler("FriendshipAccountInvitesRecieved", "OnFriendshipAccountInvitesRecieved", self)
				
		-- Setup the Interface initally & create the Timer
		self:UpdateValues()
		self:UpdateInterface()
		self:CreateUpdateTimer()

	end
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar Functions
-----------------------------------------------------------------------------------------------
-- EzSlashCommand
--  Handles the /ezs command
function EzSocialBar:EzSlashCommand(sCmd, sInput) 
	local s = string.lower(sInput)
	
	if s == nil or s == "" then
		CPrint("EzSocial Addon")
		CPrint("do /ezs refresh")
	elseif s == "refresh" then
		self:UpdateValues()
		self:UpdateInterface()
	
	-- Lock / Unlock Commands
	elseif s == "lock" then
		self.settings.isLocked = true
		self:ApplySettings()		
	elseif s == "unlock" then
		self.settings.isLocked = false
		self:ApplySettings()
	
	-- Toggle background
	elseif s == "background" then
		self.settings.displayBackground = not self.settings.displayBackground
		self:ApplySettings()
	
	-- Toggle Sound
	elseif s == "sounds" then
		self.settings.playSound = not self.settings.playSound	
	
	-- Notifications toggle
	elseif s == "notifications" then
		self.settings.enableNotifications = not self.settings.enableNotifications

	--resizing
	elseif s == "resize" then
		self.settings.isResizeable = not self.settings.isResizeable --toggle
		self:ApplySettings()
	
	elseif s == "options" and self.settings.developerMode then
		self:ShowOptions()
	end		

end

-- CreateUpdateTimer
--  Creates a new updat Timer for the Social Panel
function EzSocialBar:CreateUpdateTimer()	
	if self.updateTimer ~= nil then
		Apollo.StopTimer(self.TimerName)
	end

	self.updateTimer = Apollo.CreateTimer(self.TimerName, self.settings.notificationDuration, true)	
end

-- ShowNotification(text, duration)
--  Shows a notification for a short duration
function EzSocialBar:HideNotification()
	Apollo.StopTimer(self.notificationTimerName)
	self.notificationWindow:Show(false)
end

function EzSocialBar:ShowNotification(text)
	-- if one is already shown, stop timer and restart with new text, duration
	if self.notificationTimer ~= nil then
		Apollo.StopTimer(self.notificationTimerName)
	end
	
	-- is settings enabled
	if not self.settings.enableNotifications then
		return
	end
	
	-- show a notification
	self.notificationWindow:Show(true)
	self.notification:SetText(text)
	self.notifcationTimer = Apollo.CreateTimer(self.notificationTimerName, self.settings.notificationDuration, true)	
	--Apollo.StartTimer(self.notificationTimerName)
end

-- OnNotificationTimerTick(
--  Handles the closing down of the Notification
function EzSocialBar:OnNotificationTimerTick()
	-- stop the timer, turn off the notification
	self:HideNotification()
end


-- UpdateValues
--  Handles the getting of data to display
function EzSocialBar:UpdateValues()
	self.onlineFriends = { }	

	-- Account freinds also appear in Friends
	self.onlineFriendsCount = 0
	self.accountOnlineFriendsCount = 0;
	
	--CPrint("Friends: " .. #FriendshipLib.GetList())
	for key, tFriend in pairs(FriendshipLib.GetList()) do
		if tFriend .fLastOnline == 0 then
			self.onlineFriendsCount = self.onlineFriendsCount + 1
		end
	end
	
	--Account Friends
	--CPrint("Acc Friends: " .. #FriendshipLib.GetAccountList())
	for key, tAccFriend in pairs(FriendshipLib.GetAccountList()) do
		if tAccFriend.fLastOnline == 0 then
			self.accountOnlineFriendsCount = self.accountOnlineFriendsCount + 1
		end
	end		
	
	-- Guild Member Count
	local guild = nil
	local circle = 1
		
	--init circles
	for i = 1, 5 do
		self.circleMemberStatuses[i] = false
		self.circleMembers[i] = 0
	end
	
	--data
	for idx, guildCurr in pairs(GuildLib.GetGuilds()) do
		if guildCurr:GetType() == GuildLib.GuildType_Guild then
			guild = guildCurr
		elseif guildCurr:GetType() == GuildLib.GuildType_Circle then
			self.circleMemberStatuses[circle] = true
			self.circleMembers[circle] = guildCurr:GetOnlineMemberCount()
			self.circleDisplays[circle]:SetData(guildCurr)
			self.circleDisplays[circle]:SetTooltip(guildCurr:GetName())
			circle  = circle  + 1
		end
	end
	
	-- assign guild numbers
	if guild == nil then
		self.hasGuild = false
		self.onlineGuildCount = 0
	else
		self.hasGuild = true
		self.onlineGuildCount = guild:GetOnlineMemberCount()
	end
	
	--Mail
	self.UnreadMessages = 0
	for idx, tMessage in pairs(MailSystemLib.GetInbox()) do
		local tMessageInfo = tMessage:GetMessageInfo()
		
		if tMessageInfo and not tMessageInfo.bIsRead then
			self.UnreadMessages = self.UnreadMessages + 1
		end
	end
	
end

--- UpdateInterface
--   Updates the interface to reflect values
function EzSocialBar:UpdateInterface()	

	-- Friends
	local totalFriends = self.onlineFriendsCount + self.accountOnlineFriendsCount;
	
	if totalFriends > 0 then
		self.friendList:SetText(string.format("Friends: %u", totalFriends ));
	else
		self.friendList:SetText("Friends: --");
	end
	
	-- Guild Count
	if self.hasGuild then
		self.guildDisplay:SetText(string.format("Guild: %u", self.onlineGuildCount));
	else
		self.guildDisplay:SetText("Guild: --");
	end
	
	-- Circles Count	
	for i = 1, 5 do
		if self.circleMemberStatuses[i] then
			self.circleDisplays[i]:SetText(string.format("%u", self.circleMembers[i]))
		else
			self.circleDisplays[i]:SetText("--")
		end	
	end
	
	--Mail
	self:ShowMailIcon(self.UnreadMessages)
end

function EzSocialBar:HideMailIcon()
	self.mailControl:Show(false)
end

function EzSocialBar:ShowMailIcon(nMail)
	if nMail == 0 then
		self:HideMailIcon()
		return
	end	
	
	self.mailControl:FindChild("mailText"):SetText("" .. nMail)
	self.mailControl:Show(true)	
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar Event Listeners
-----------------------------------------------------------------------------------------------
function EzSocialBar:OnFriendshipUpdateOnline(nFriendId)
	-- use the ID to get the friends name from Friendship lib	
	--  show notifcation displaying Player has come online
	local tFriend = FriendshipLib.GetById(nFriendId)
	
	--If he is not our friend?
	--   honestly, idk, i found this in FriendsList - wut do
	if not tFriend.bFriend then
		return
	end
	
	if tFriend.fLastOnline == 0 then --just come online
		self:ShowNotification(string.format("%s has come Online", tFriend.strCharacterName))
	else
		self:ShowNotification(string.format("%s has gone Offline", tFriend.strCharacterName))
	end
	
	--Play a sound ??
	if self.settings.playSound then 
		Sound.Play(Sound.PlayUISocialFriendAlert)
	end
end

function EzSocialBar:OnFriendshipRequest(tRequest)	
	--Friend has been Requested	
	self:ShowNotification(string.format("New friendship request from %s", tRequest.strCharacterName))	
	if self.settings.playSound then 
		Sound.Play(Sound.PlayUISocialFriendAlert)
	end		
end

function EzSocialBar:OnFriendshipAccountInvitesRecieved(tInviteList)
	if #tInviteList == 1 then
		self:ShowNotification(string.format("New account request from %s", tInviteList[1].strCharacterName))
	else
		self:ShowNotification("New account requests!")
	end
	
	if self.settings.playSound then 
		Sound.Play(Sound.PlayUISocialFriendAlert)
	end
end

-----------------------------------------------------------------------------------------------
-- EzSocialBarForm Functions
-----------------------------------------------------------------------------------------------
function EzSocialBar:OnEzTimerTick()
	self:UpdateValues()
	self:UpdateInterface()
end

function EzSocialBar:OnFriendsButtonDown( wndHandler, wndControl, eMouseButton )
	Event_FireGenericEvent("GenericEvent_OpenFriendsPanel")
end

function EzSocialBar:OnGuildButtonDown( wndHandler, wndControl, eMouseButton )	
	Event_FireGenericEvent("GenericEvent_OpenGuildPanel")
end

function EzSocialBar:OnCircleButtonDown( wndHandler, wndControl, eMouseButton )	
	Event_FireGenericEvent("GenericEvent_OpenCirclesPanel")
end

-- has clicked the notification, register as seen and hide
function EzSocialBar:OnNotificationClick( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY, bDoubleClick, bStopPropagation )
	self:HideNotification()
end

function EzSocialBar:OnMailIconClick( wndHandler, wndControl, eMouseButton, nLastRelativeMouseX, nLastRelativeMouseY, bDoubleClick, bStopPropagation )
	--CPrint("Mail Icon Clicked")
	Event_FireGenericEvent("GenericEvent_OpenMailPanel")

end

function EzSocialBar:OnFormMove( wndHandler, wndControl, nOldLeft, nOldTop, nOldRight, nOldBottom )
	local l,t,r,b = self.wndMain:GetAnchorOffsets()	
	self.settings.position.left = l
	self.settings.position.top = t
	self.settings.position.right = r
	self.settings.position.bottom = b	
end

-----------------------------------------------------------------------------------------------
-- EzSocial Options
-----------------------------------------------------------------------------------------------
function EzSocialBar:ShowOptions() 
	-- only developer options atm
	-- if you change to dev mode, strange things will happen
	if not self.settings.developerMode then
		return
	end

	self.optionsWindow = Apollo.LoadForm(self.xmlDoc, "EzSocialSettings", nil, self)	
	self.optionsWindow:Show(true)
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar Instance
-----------------------------------------------------------------------------------------------
local EzSocialBarInst = EzSocialBar:new()
EzSocialBarInst:Init()
