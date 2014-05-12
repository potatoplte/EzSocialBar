-----------------------------------------------------------------------------------------------
-- Client Lua Script for EzSocialBar
-- Copyright (c) NCsoft. All rights reserved
----------------------------------------------------------------------------------------------- 
require "Window"

-----------------------------------------------------------------------------------------------
-- EzSocialBar Module Definition
-----------------------------------------------------------------------------------------------
local EzSocialBar = {} 

local function CPrint(string)
	ChatSystemLib.PostOnChannel(ChatSystemLib.ChatChannel_Command, string, "")
end

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


local DefaultSettings =
{
	position = { 
		top = -3,
		left = -620,
		right = 2,
		bottom = 70,
		},
	
	displayBackground = true,
	isLocked = true,
	playSound = false,
	notificationDuration = 5,
	updateFreq = 5,
	enableNotifications = true,
	developerMode = false, -- !!!! Remember to change this !!!
	isResizeable = false,
}

 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function EzSocialBar:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here
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
			left = -620,
			right = 2,
			bottom = 70,
			},
		
		displayBackground = true,
		isLocked = true,
		playSound = false,
		notificationDuration = 5,
		updateFreq = 5,
		enableNotifications = true,
		developerMode = false, -- !!!! Remember to change this !!!
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
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return nil
	else
		return self.settings
	end		
end

function EzSocialBar:OnRestore(eType, tData)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then return end
	
	for Dkey, Dvalue in pairs(self.settings) do
		if tData[Dkey] ~= nil then
			self.settings[Dkey] = tData[Dkey]
		end
	end 
		
	--self:ApplySettings()
end


function EzSocialBar:ApplySettings()		
		--set the position of the window
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
		self.notificationWindow = self.wndMain:FindChild("EzSocialNotification")
		self.notificationWindow:Show(false)
		self.notification = self.notificationWindow:FindChild("NotificationText")
		
		self.friendsControl = self.wndMain:FindChild("friendsIco")
		self:SetFriendsPending(0)
		
		self.mailControl = self.wndMain:FindChild("mailControl")
		self:SetMailIcon(0)	
		
		self.optionsWindow = Apollo.LoadForm(self.xmlDoc, "EzSocialSettings", nil, self)
		self.optionsWindow:Show(false)
		
		--timer handlers		
		self.updateTimer = Apollo.CreateTimer("EzUpdateTimer", 1, true)
		self.notifcationTimer = Apollo.CreateTimer("NotificationTimer", 10.0, false)
		
		Apollo.RegisterTimerHandler("NotificationTimer", "OnNotificationTimerTick", self)
		Apollo.RegisterTimerHandler("EzUpdateTimer", "OnEzTimerTick", self)
		
		Apollo.StartTimer("EzUpdateTimer")
		Apollo.StopTimer("NotificationTimer")

		-- register for some apollo events
		Apollo.RegisterEventHandler("FriendshipUpdateOnline", "OnFriendshipUpdateOnline", self)	

		Apollo.RegisterEventHandler("FriendshipInvitesRecieved", "OnFriendshipRequest", self)		
		Apollo.RegisterEventHandler("FriendshipAccountInvitesRecieved", "OnFriendshipAccountInvitesRecieved", self)
				
		-- Setup the Interface initally & create the Timer
		if self.settings == nil then
			self.settings = DefaultSettings
		else
			self:ApplySettings()
		end
		
		self:UpdateValues()
		self:UpdateInterface()
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
		CPrint("do /ezs options for options menu")
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
		if self.settings.playSound then
			CPrint("Sounds Enabled")
		else
			CPrint("Sounds Disabled")		
		end
	-- Notifications toggle 
	elseif s == "notifications" then
		self.settings.enableNotifications = not self.settings.enableNotifications
	
	-- Options
	elseif s == "options" then
		self:ShowOptions()	

	-- Notify [DEV]
	elseif s == "notify" and self.settings.developerMode then
		self:CalcFriendInvites(2) -- delta testing

	-- Resizing [DEV]
	elseif s == "resize" and self.settings.developerMode then		
		self.settings.isResizeable = not self.settings.isResizeable --toggle
		self:ApplySettings()
		
	elseif s == "derp" and self.settings.developerMode then		
		CPrint(table.tostring(FriendshipLib.GetAccountInviteList()))				
	end
end

-- SetNotification(text, duration)
--  Shows a notification for a short duration
function EzSocialBar:SetNotification(text)	
	-- is settings enabled
	if not self.settings.enableNotifications then
		return
	end
	
	if text == nil or text == "" then		
		self.notificationWindow:Show(false)
		return
	end
	
	-- show a notification
	self.notificationWindow:Show(true)
	self.notification:SetText(text)
	Apollo.StartTimer("NotificationTimer")
	
	if self.settings.playSound then 
		Sound.Play(Sound.PlayUISocialFriendAlert)
	end
end

-- OnNotificationTimerTick(
--  Handles the closing down of the Notification
function EzSocialBar:OnNotificationTimerTick()
	-- stop the timer, turn off the notification
	Apollo.StopTimer("NotificationTimer")
	self:SetNotification("")	
end


-- UpdateValues
--  Handles the getting of data to display
function EzSocialBar:UpdateValues()
	self.onlineFriends = { }	

	-- Account freinds also appear in Friends
	self.onlineFriendsCount = 0
	self.accountOnlineFriendsCount = 0;
	
	for key, tFriend in pairs(FriendshipLib.GetList()) do
		if tFriend.fLastOnline == 0 then
			self.onlineFriendsCount = self.onlineFriendsCount + 1
		end
	end
	
	--Account Friends	
	for key, tAccFriend in pairs(FriendshipLib.GetAccountList()) do
		if tAccFriend.arCharacters then -- changed from fLastOnline == 0, i assume arCharacter is a list of character which is nil if they are offline?
			self.accountOnlineFriendsCount = self.accountOnlineFriendsCount + 1
		end
	end		
	
	
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
	self:SetMailIcon(self.UnreadMessages)
	self:CalcFriendInvites(0)
end

function EzSocialBar:SetMailIcon(nMail)
	if nMail == 0 then
		self.mailControl:Show(false)
		return
	end	
	
	self.mailControl:FindChild("mailText"):SetText("" .. nMail)
	self.mailControl:Show(true)	
end

function EzSocialBar:SetFriendsPending(nFriends)
	local friendsRotateyThingy = self.friendsControl:FindChild("invites")
	local friendsPendingCtrl = self.friendsControl:FindChild("friendsPending")
	
	if nFriends == 0 then
		friendsRotateyThingy:Show(false)
		friendsPendingCtrl:Show(false)
	else
		friendsRotateyThingy:Show(true)
		friendsPendingCtrl:Show(true)
		friendsPendingCtrl:SetText(nFriends .. "")
	end	
end

function EzSocialBar:CalcFriendInvites(nDelta)
	--nDelta is a testin value
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
	-- use the ID to get the friends name from Friendship lib	
	--  show notifcation displaying Player has come online
	local tFriend = FriendshipLib.GetById(nFriendId)
	--CPrint("OnFriendshipUpdateOnline nFriendId=" .. nFriendID)
	--If he is not our friend?
	--   honestly, idk, i found this in FriendsList - wut do
	if not tFriend.bFriend then
		return
	end
	
	--self:CalcFriendInvites(0)	
	if tFriend.fLastOnline == 0 then --just come online
		self:SetNotification(string.format("%s has come Online", tFriend.strCharacterName))
	else
		self:SetNotification(string.format("%s has gone Offline", tFriend.strCharacterName))
	end
	
end

function EzSocialBar:OnFriendshipRequest(tRequest)	
	--Friend has been Requested	
	--self:SetNotification(string.format("New friendship request from %s", tRequest.strCharacterName))
	self:CalcFriendInvites(0)
end

function EzSocialBar:OnFriendshipAccountInvitesRecieved(tInviteList)			
	self:CalcFriendInvites(0)
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
	self:SetNotification("")
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
		
	self.optionsWindow:FindChild("toggleLock"):SetCheck(self.settings.isLocked)
	self.optionsWindow:FindChild("toggleBackground"):SetCheck(self.settings.displayBackground)
	self.optionsWindow:FindChild("toggleSounds"):SetCheck(self.settings.playSound)
	self.optionsWindow:FindChild("toggleNotifications"):SetCheck(self.settings.enableNotifications)
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
function EzSocialBar:OnOptionsClose( wndHandler, wndControl, eMouseButton )
	self.optionsWindow:Show(false)
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar Instance
-----------------------------------------------------------------------------------------------
local EzSocialBarInst = EzSocialBar:new()
EzSocialBarInst:Init()
