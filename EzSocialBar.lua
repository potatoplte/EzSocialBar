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
	}
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function EzSocialBar:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 
	self.IsBarLoaded = false -- indicated if BuildSocialBar has been called, prevents StackOverflow
	self.AreSettingsLoaded = false --are settings loaded, prevents the race condition from Restore and Loaded

    -- varaibles holding display data
	self.settings = nil			
	self.data = {
		onlineFriendsCount = 0,
		accountOnlineFriendsCount = 0,
		onlineGuildCount = 0,
		hasGuild = false,
		circleMemberStatuses =  { false, false, false, false, false},
		circleMembers =  { 0, 0, 0, 0, 0 },	
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
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then return end
	
	if self.settings == nil then self.settings = DefaultSettings end
	
	for Dkey, Dvalue in pairs(self.settings) do
		if tData[Dkey] ~= nil then
			self.settings[Dkey] = tData[Dkey]
		end
	end 
	
	-- we have loaded data, stop the timer for race condition
	Apollo.StopTimer("EzLoaderTimer")	
	self.AreSettingsLoaded = true	
	self:ApplySettings()
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar ApplySettings
-----------------------------------------------------------------------------------------------
function EzSocialBar:ApplySettings()
	-- if settings have not been loaded, dont do a thing
	if not self.AreSettingsLoaded then return end
	
	-- foce an update on self.data
	self:OnEzTimerTick()
	
	-- if the bar has not been built, then load it.	
	if not self.IsBarLoaded then	
		self:BuildSocialBar()
	end

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
			
	--set the position of the window
	self.mainContainer:FindChild("EzSocialBar"):SetAnchorPoints(0, 0, 1, .5)
	self.mainContainer:SetAnchorOffsets(
		self.settings.position.left,
	 	self.settings.position.top,
		self.settings.position.right,
	 	self.settings.position.bottom)

end

-----------------------------------------------------------------------------------------------
-- EzSocialBar OnDocLoaded
-----------------------------------------------------------------------------------------------
function EzSocialBar:OnDocLoaded()
	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.mainContainer = Apollo.LoadForm(self.xmlDoc, "EzSocialBarForm", nil, self)				
	    self.mainContainer:Show(true)
	
		self.background = self.mainContainer:FindChild("Background")
		self.mailControl = self.mainContainer:FindChild("MailNodule")
		self.notificationsWindow = self.mainContainer:FindChild("EzSocialNotification")
		self.optionsWindow = Apollo.LoadForm(self.xmlDoc, "EzSocialSettingsForm", nil, self)
		self.optionsWindow:Show(false)
		self.notificationsWindow:Show(false)		
		self:SetMailIcon(0)
			
		if not self.AreSettingsLoaded then
			--settings have not been loaded.
			-- we should start a 5s timer, in this time settings are either going to be loaded or not.
			Apollo.CreateTimer("EzLoaderTimer", 5, false)
			Apollo.RegisterTimerHandler("EzLoaderTimer", "OnEzLoaderTimerExpire", self)		
		end		
				
		--timer handlers		
		Apollo.CreateTimer("EzUpdateTimer", 1, true)
		Apollo.CreateTimer("NotificationTimer", 10.0, false)		
		Apollo.RegisterTimerHandler("NotificationTimer", "OnNotificationTimerTick", self)
		Apollo.RegisterTimerHandler("EzUpdateTimer", "OnEzTimerTick", self)		
		Apollo.StopTimer("NotificationTimer")
		Apollo.StopTimer("EzUpdateTimer")

		-- Register for some Events
		Apollo.RegisterEventHandler("FriendshipUpdateOnline", "OnFriendshipUpdateOnline", self)	
		Apollo.RegisterEventHandler("FriendshipInvitesRecieved", "OnFriendshipRequest", self)		
		Apollo.RegisterEventHandler("FriendshipAccountInvitesRecieved", "OnFriendshipAccountInvitesRecieved", self)
		
	end
end

function EzSocialBar:OnEzLoaderTimerExpire()
	if self.AreSettingsLoaded then
		-- all is ok!
		Apollo.StopTimer("EzLoaderTimer")
		return
	end
	
	-- no settings have been loaded
	-- start the main timing loop	, apply default settings and go
	Apollo.StartTimer("EzUpdateTimer")
	self.settings = DefaultSettings
	self:ApplySettings()	
end

function EzSocialBar:BuildSocialBar()
	-- Builds the acctual social bar			
	local currentWidth = 0	
	local container = self.mainContainer:FindChild("EzSocialBar")
	container:DestroyChildren() -- remove all components ?is there a perf issue here??
	local ctrl, w	
	
	-- Build Friends Bar
	if self.settings.noduleStates.Friends then	 
		ctrl, w = self:BuildItem("FriendsNodule", "FriendsView", container)
		ctrl:SetAnchorPoints(0, 0, 0, 1)
		ctrl:SetAnchorOffsets(currentWidth, 0, currentWidth + w, 0)
		currentWidth = currentWidth + w		
		--assign to the windows
	end
	
	-- Build Guilds Bar
	if self.settings.noduleStates.Guild then
		ctrl, w = self:BuildItem("GuildsNodule", "GuildsView", container)
		ctrl:SetAnchorPoints(0, 0, 0, 1)
		ctrl:SetAnchorOffsets(currentWidth, 0, currentWidth + w, 0)
		currentWidth = currentWidth + w		
		--assign to the windows
	end
	
	if self.settings.noduleStates.Circles then
		CPrint("Building Circle Windows")
		local circlesCount = 0
	 	for i = 1, 5 do
			CPrint("" .. i)
			if self.data.circleMemberStatuses[i] then
				ctrl, w = self:BuildItem("CircleNodule", "Circle_" .. i, container)
				CPrint("" .. i)				
				ctrl:SetAnchorPoints(0, 0, 0, 1)
				ctrl:SetAnchorOffsets(currentWidth, 0, currentWidth + w, 0)	
				currentWidth = currentWidth + w	
				circlesCount = circlesCount + 1		
			end
		end	
	end	
	
	-- Now we know how long to container is, we can adjust the poisition of the acctual mainContainer
	--   according to the users settins, position should not be lost	
	self.IsBarLoaded = true --
	self.settings.position.right = self.settings.position.left + currentWidth + 40, -- 40 for mail container? 
	self:ApplySettings()
end 

function EzSocialBar:BuildItem(type, name, parent)
	local newItem = Apollo.LoadForm(self.xmlDoc, type, parent, self)
	
	if newItem == nil then
		CPrint("Failed to create" .. name)
	else
		CPrint("Created " .. name)			
	end
	
	newItem:SetName(name)
	return newItem, newItem:GetWidth()
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar EzSlashCommand
-----------------------------------------------------------------------------------------------
function EzSocialBar:EzSlashCommand(sCmd, sInput) 
	local s = string.lower(sInput)
	
	if s == nil or s == "" then
		CPrint("EzSocial Addon")
		CPrint("do /ezs options for options menu")
		
	-- Options
	elseif s == "reset" then
		self.settings = DefaultSettings
		self.IsBarLoaded = false
		self:ApplySettings()
		
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
	-- First Friends, only bother to update if we are showing the values	
	if self.settings.noduleStates.Friends then	
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
			
		--Update Friends interface
		local totalFriends = self.data.onlineFriendsCount + self.data.accountOnlineFriendsCount	
		if totalFriends > 0 then
			self.mainContainer:FindChild("FriendsView"):FindChild("Text"):SetText(string.format("Friends: %u", totalFriends))
		else
			self.windows.Friends:FindChild("FriendsView"):FindChild("Text"):SetText("Friends: --")
		end			
	end

	-- Next Guilds
	if self.settings.noduleStates.Guild or self.noduleStates.Circles then
		local guild = nil
		local circle = 1
		
		--init circles
		for i = 1, 5 do
			self.data.circleMemberStatuses[i] = false
			self.data.circleMembers[i] = 0
		end
		
		--data
		for idx, guildCurr in pairs(GuildLib.GetGuilds()) do
			if guildCurr:GetType() == GuildLib.GuildType_Guild then
				guild = guildCurr
			elseif guildCurr:GetType() == GuildLib.GuildType_Circle then
				self.data.circleMemberStatuses[circle] = true
				self.data.circleMembers[circle] = guildCurr:GetOnlineMemberCount()
				circle = circle  + 1
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
			for i = 1, 5 do
				if self.data.circleMemberStatuses[i] then
					local wnd = self.mainContainer:FindChild("Circle_"..i)
					if wnd == nil then
						CPrint("Error Circle_" .. i .. " was not found on window")
					else
						wnd:SetText(string.format("%u", self.data.circleMembers[i]))	
					end
				end
			end
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
		
		--Mail
		self:SetMailIcon(self.data.UnreadMessages)			
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
	Event_FireGenericEvent("GenericEvent_OpenCirclesPanel") --TODO: can this be fixed?
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

function EzSocialBar:OnOptionsClose( wndHandler, wndControl, eMouseButton )
	self.optionsWindow:Show(false)
end

function EzSocialBar:OnShowFriendsToggle( wndHandler, wndControl, eMouseButton )
	self.settings.noduleStates.Friends = wndControl:IsChecked()
	self.IsBarLoaded = false
	self:ApplySettings()
end
function EzSocialBar:OnShowGuildToggle( wndHandler, wndControl, eMouseButton )
	self.settings.noduleStates.Guild = wndControl:IsChecked()
	self.IsBarLoaded = false
	self:ApplySettings()
end
function EzSocialBar:OnShowCirclesToggle( wndHandler, wndControl, eMouseButton )
	self.settings.noduleStates.Circles = wndControl:IsChecked()
	self.IsBarLoaded = false
	self:ApplySettings()
end

-----------------------------------------------------------------------------------------------
-- EzSocialBar Instance
-----------------------------------------------------------------------------------------------
local EzSocialBarInst = EzSocialBar:new()
EzSocialBarInst:Init()
