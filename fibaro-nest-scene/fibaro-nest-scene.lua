--[[
WARNING
This scene is highly experimental and comes without any warranty. 
Use it completely at your own risk! If your Nest gets stuck at 
28 degrees while you're on holiday it's your own responsibility.

TODO
* Allow the temperature to be set through changing it directly on the valve

%% autostart
%% properties
%% events
%% globals
--]]
if (fibaro:countScenes() > 1) then
	fibaro:debug("Scene already active! Aborting this new instance !!")
	fibaro:abort()
end

--------------------- USER SETTINGS --------------------------------
--------------------- SET THESE BEFORE FIRST RUN -------------------

local nestThermostat = 0 -- Virtual Device Id
local nestThermostatAmbientTemperatureSensor = 0 -- Virtual Device Id
local heatingPanels = { 0 } -- find your id via /api/panels/heating/

-------------------------------------------------------------------- 
--------------------- ADVANCED SETTINGS ----------------------------

local updateFrequency = 15 -- delay in second to refresh the values

local valveClosedSetpointValue = 8 -- temperature at which the valves are open 
local valveOpenSetpointValue = 28 -- temperature at which the valves are close 

local show_debug = true   -- Debug displayed in white 
local show_trace = false  -- Debug displayed in orange 
local show_error = true   -- Debug displayed in red

-------------------------------------------------------------------- 
--------------------- INTERNAL SETTINGS ----------------------------

local nestSetpointTemperature = 0
local nestAmbientTemperature = 0

local wasManualModeActiveInPreviousRun = false

-------------------------------------------------------------------- 

function CustomDebug(color, message) 
  fibaro:debug(string.format('<%s style="color:%s;">%s</%s>', "span", color, os.date("%a %d/%m", os.time()).." "..message, "span")); 
end 

function Debug(debugMessage)
  if ( show_debug ) then
    CustomDebug( "white", debugMessage);
  end
end

function Trace(debugMessage)
	if ( show_trace ) then
		CustomDebug( "orange", debugMessage);
	end
end

function Error(debugMessage)
	if ( show_error ) then
		CustomDebug( "red", debugMessage);
	end
end

-------------------------------------------------------------------- 

local function setNestSetpoint(setpoint)
    fibaro:call(nestThermostat, "setProperty", "ui.setpoint.value", setpoint .. " °C")
    Trace("Update Nest setpoint to [" .. setpoint .. "]")
end

local function setNestMode(mode)
    if(string.upper(mode) == "HEAT" or string.upper(mode) == "ECO") then        
        fibaro:call(nestThermostat, "setProperty", "ui.mode.value", mode)
        Trace("Update Nest mode to [" .. mode .. "]")
    else
        Error("Incorrect Nest mode specified [" .. mode .. "]")
    end
end

local function setValveSetpoint(valveId, setpoint)
    local currentValveSetpoint = tonumber(fibaro:getValue(valveId, "value"))
    if(currentValveSetpoint ~= setpoint) then
        fibaro:call(valveId, "setTargetLevel", setpoint)
        Debug("Set valve [" .. valveId .. "] to [" .. setpoint .. "] - Nest [" .. nestAmbientTemperature .. ":" .. nestSetpointTemperature .. "]")
    end
end

local function hasValue (table, val)
    for index, value in ipairs(table) do
        if value == val then
            return true
        end
    end

    return false
end

-- https://manuals.fibaro.com/knowledge-base-browse/rest-api/
function updateValvesInRooms(rooms, setpointValue)
    -- iterate over all devices
    -- if their room id matches any of the rooms
    -- and they are of the type com.fibaro.setPoint
    -- set their targetLevel to setpointValue
    local response, status, errorCode = api.get("/devices/")
    
    if (status == 200) then
        for i, device in ipairs(response) do
            local deviceType = device.type
        
            if(deviceType == "com.fibaro.setPoint") then            
                -- Is it in the right room?
                local deviceRoom = device.roomID        
                if(hasValue(rooms, deviceRoom)) then
                    local deviceId = device.id
                    setValveSetpoint(deviceId, setpointValue)
                end
            end
        end
    else
        Error("Failed to fetch devices")
    end    
end

local function updateValvesInHeatingZone(heatingZoneId, setpoint)
    local response, status, errorCode = api.get("/panels/heating/" .. heatingZoneId)
    
    if (status == 200) then 
        local rooms = response.properties.rooms
        updateValvesInRooms(rooms, setpoint)
    else
        Error("Failed to updateValvesInHeatingZone()")    
    end
end


function updateThermostat()
    nestAmbientTemperature = fibaro:getValue(nestThermostatAmbientTemperatureSensor, "ui.temp.value")
    nestAmbientTemperature = nestAmbientTemperature:gsub(" °C", "")
    nestAmbientTemperature = tonumber(nestAmbientTemperature)

    nestSetpointTemperature = fibaro:getValue(nestThermostat, "ui.setpoint.value")
    nestSetpointTemperature = nestSetpointTemperature:gsub(" °C", "")
    nestSetpointTemperature = tonumber(nestSetpointTemperature)
  
    Trace("Nest temperature Ambient:[" .. nestAmbientTemperature .. "] Setpoint:[" .. nestSetpointTemperature .. "]")
  
    local manualModeActive = false -- need to keep track of this to know if we need to turn on the heat in all zones
  
    for i, heatingPanelId in ipairs(heatingPanels) do
      local response, status, errorCode = api.get("/panels/heating/" .. heatingPanelId)
      
      if (status == 200) then 
          local heatingPanelName = response.name
          local heatingPanelManualModeTemperature = response.properties.handTemperature
          
          -- Check if we're in Manual Mode in this heating zone
          if (heatingPanelManualModeTemperature > 0) then
              manualModeActive = true
              wasManualModeActiveInPreviousRun = true

              local currentTime = tonumber(os.time())              
              local timeLeft = tonumber(response.properties.handTimestamp) - currentTime -- in seconds
              Debug("Manual mode is on in [" .. heatingPanelName .. "] with [" .. timeLeft .. "] seconds left. Temperature is set to [" .. heatingPanelManualModeTemperature .. "]")
              
              -- if the heating zone temp is higher than nest setpoint update nest
              -- and open the valves to max (or leave them at the temperature of the heating zone)?
              if (heatingPanelManualModeTemperature > nestSetpointTemperature) then
                  setNestSetpoint(heatingPanelManualModeTemperature)
                  
                  setNestMode("Heat") -- make sure we're in heating mode and not Eco or Off
                  
                  -- 1. get room id from heating zone
                  local heatingPanelRooms = response.properties.rooms -- table
                  Trace("Rooms [" .. json.encode(heatingPanelRooms) .. "] in heating panel [" .. heatingPanelName .. "]")
                  
                  -- 2. update all the valves in the room(s) thare are in this heating zone
                  updateValvesInRooms(heatingPanelRooms, valveOpenSetpointValue)
                  
                  Debug("Updating current Nest setpoint [" .. nestSetpointTemperature ..  "] to match manual mode [" .. heatingPanelManualModeTemperature .. "] in heating zone [" .. heatingPanelName .. "]")
              end
          else
              local heatingPanelScheduleTemperature = response.properties.currentTemperature
              -- Debug("[" .. heatingPanelName .. "] is following regular heating schedule [" .. heatingPanelScheduleTemperature .. "]")
          end
      else
          Error("Failed to get data for heating panel [" .. heatingPanelId .. "]")
          Error("Error: " .. errorCode .. " Data: " .. json.encode(response))
      end
    end
    
    -- Check if manual mode has been turned of between this run
    -- and the previous one. It could have been because the timer
    -- ran out or because it was turned off manually.
    if (wasManualModeActiveInPreviousRun and manualModeActive == false) then
        Error("Manual mode has been disabled in all the heating zones!")
        
        -- let's lower the setpoint to just below current ambient temparture
        -- so that when it wakes up from Eco at a late moment the 
        -- temperature won't be too hight
        local ecoSetpoint = nestAmbientTemperature - 0.5 
        setNestSetpoint(ecoSetpoint)
                
        -- optional: set Nest to Eco mode
        -- setNestMode("Eco")
        
        -- Close all the valves in every heating zone
        -- This should have been done by fibaro already but just to be sure.
        for i,heatingPanelId in ipairs(heatingPanels) do
            local response, status, errorCode = api.get("/panels/heating/" .. heatingPanelId)
            if (status == 200) then 
                updateValvesInRooms(response.properties.rooms, valveClosedSetpointValue)                
            else
                Error("Failed to find the heating panel with id [" .. heatingPanelId .. "].")
            end
        end
        wasManualModeActiveInPreviousRun = manualModeActive
    -- Manual Mode wasn't running and still isn't but we need to check one more thing.
    elseif(manualModeActive == false) then
        local currentNestMode = string.upper(fibaro:getValue(nestThermostat, "ui.mode.value"))
        -- We only want to get a reading from Nest if it's not on Eco or Off
        if(currentNestMode == "HEAT") then
            -- Let's check if someone turned up the heat using the Nest directly
            if (nestSetpointTemperature >= nestAmbientTemperature) then
              Trace("Nest is set to heat the room [" .. nestSetpointTemperature .. ":" .. nestAmbientTemperature .. "]")

              -- open all the valves so that the entire room can heat up quickly
              for i,heatingPanelId in ipairs(heatingPanels) do
                  updateValvesInHeatingZone(heatingPanelId, valveOpenSetpointValue)
              end
            elseif (nestAmbientTemperature > (nestSetpointTemperature + 0.5)) then
                Trace("We're above the desired room temperature [" .. nestSetpointTemperature .. ":" .. nestAmbientTemperature .. "]")
                -- Only close the values when the ambient temperature is 0.5 degrees higher than setpoint
                -- This gives us a bit of wiggle room and make sure we don't close them too soon
                for i,heatingPanelId in ipairs(heatingPanels) do
                    updateValvesInHeatingZone(heatingPanelId, valveClosedSetpointValue)
                end
            end
        else
            Debug("Close the valves. Nest is in [" .. currentNestMode .. "] mode")
            for i,heatingPanelId in ipairs(heatingPanels) do
                updateValvesInHeatingZone(heatingPanelId, valveClosedSetpointValue)
            end
        end
    end
     
  -- TODO check if the temperate has been set manually on one of the valves
  -- if so match the nest setpoint to the value of the valve
end

function mainLoop()
  
  updateThermostat();
  
  setTimeout(mainLoop, updateFrequency * 1000) 
end

mainLoop()