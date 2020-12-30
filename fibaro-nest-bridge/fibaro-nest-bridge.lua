--[[
This code is inspired by:
https://github.com/GuillaumeWaignier/fibaro/tree/master/quickApp/NestThermostat
https://github.com/GuillaumeWaignier/fibaro/blob/master/quickApp/NestThermostat/quickApp.lua

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

local projectId = ""
local clientId = ""
local clientSecret = ""
local refreshToken = ""
-- Make sure you capture the refresh token on your first run!
-- If you don't and try to get it again you'll get a 400 error.
-- https://stackoverflow.com/questions/10576386/invalid-grant-trying-to-get-oauth-token-from-google#comment114665251_10576386

local ambientTemperatureSensorVirtualDeviceId = 0
local humiditySensorVirtualDeviceId = 0
local thermostatVirtualDeviceId = 0

-------------------------------------------------------------------- 
--------------------- ADVANCED SETTINGS ----------------------------

local updateFrequency = 30 -- delay in second to refresh the value

local show_debug = true   -- Debug displayed in white 
local show_trace = false  -- Debug displayed in orange 
local show_error = true   -- Debug displayed in red

-------------------------------------------------------------------- 
--------------------- INTERNAL SETTINGS ----------------------------

local accessToken = nil
local thermostatId = ""

-- needed to know if the setpoint and mode has been changed by us or externally
local previousSetpoint = "" 
local previousMode = ""

-------------------------------------------------------------------- 

function CustomDebug(color, message) 
  fibaro:debug(string.format('<%s style="color:%s;">%s</%s>', "span", color, os.date("%a %d/%m", os.time()).." "..message, "span")); 
end 

function Debug(debugMessage)
  if (show_debug) then
    CustomDebug("white", debugMessage);
  end
end

function Trace(debugMessage)
	if (show_trace) then
		CustomDebug("orange", debugMessage);
	end
end

function Error(debugMessage)
	if (show_error) then
		CustomDebug("red", debugMessage);
	end
end

-------------------------------------------------------------------- 
--------------------- HELPER FUNCTIONS -----------------------------

function convertLabelToTemperature(label)  
  if (label) then
    temp, count = label:gsub(" °C", "")
    
    if (count > 0) then
      if(tonumber(temp)) then
          return(tonumber(temp))
       else
          Error("Label is not a number {" .. temp .. "}!")
          return nil
       end
    else
      Error("Label doesn't contain °C sign {" .. temp .. "}!")
      return nil
    end
  else
    Error("Label is {nil}!")
    return nil
  end
end

function updateVirtualDeviceNestMode(deviceId, mode)
  if(tonumber(deviceId) ~= nil and mode ~= nill and
     (string.upper(mode) == "HEAT" or string.upper(mode) == "ECO" or string.upper(mode) == "OFF")) then
    updateProperty(deviceId, "ui.mode.value", mode)
  else
    Error("Can't update device mode. Invalid argument(s) supplied. {" .. (deviceId and deviceId or "nil") .. "} {" .. (mode and mode or "nil") .. "}")
  end
end

-- Updates the property in the specified virtual device
function updateProperty(deviceId, label, value)
    if (tonumber(deviceId) ~= nil and label ~= nil and value ~= nil) then
      fibaro:call(deviceId, "setProperty", label, value)
      Trace("[Update device " .. deviceId .. " " .. label ..  " ] " .. value)
    else
      Error("Can't update device. Invalid argument(s) supplied. {" .. (deviceId and deviceId or "nil") .. "} {" .. label .. "} {" .. value .. "}")
    end
end

-- https://cloud.google.com/apis/design/errors
function handleApiError(response)  
  if response.status == 401 then
    -- UNAUTHENTICATED
    Error("Nest API Error: " .. response.status .. " : UNAUTHENTICATED")    
  elseif response.status == 500 then
    -- DATA_LOSS, UNKNOWN, INTERNAL
    Error("Nest API Error: " .. response.status .. " : UNAUTHENTICATED")    
  else
    Error("Nest API Error: " .. response.status .. " : UNDEFINED")    
  end
  Error("  error message: " .. json.encode(response.data))
end

-------------------------------------------------------------------- 
--------------------- AUTHENTICATION -------------------------------

function getAccessToken()
    if accessToken ~= nil then
      return
    end

    local HC2 = net.HTTPClient({ timeout = 5000 })
    local url = "https://www.googleapis.com/oauth2/v4/token?client_id=" .. clientId .. "&client_secret=" .. clientSecret .. "&refresh_token=" .. refreshToken .. "&grant_type=refresh_token"
    Trace("Getting a fresh Access Token via: " .. url)
    
  	HC2:request(url , {
        options = {
            checkCertificate = true,
            method = 'POST',
            headers = {},
            data = nil
        },
        success = function(response)
            if response.status == 200 then
                body = json.decode(response.data)
                accessToken = "Bearer " .. body['access_token']
                Debug("getAccessToken(): Succes!")
                Trace("New Access Token {" .. accessToken .. "}")
            else
              Error("getAccessToken() failed")
              handleApiError(response)
                -- FIXME Report the error message via email?
                -- We want to know if the refresh token is still valid.
                -- If it we can't do any future API calls and need to manually fix things.
            end
        end,
        error = function(error)
            Error("getAccessToken() failed: " .. json.encode(error))
            -- FIXME Send email with error message?
        end
    })
end

-------------------------------------------------------------------- 
--------------------- API CALLS ------------------------------------

-- https://developers.google.com/nest/device-access/api/thermostat#change_the_temperature_setpoints
function updateHeatingThermostatSetpoint(device)
  if (accessToken == nil or thermostatId == "") then
    Error("Can't update thermostat setpoint. Access Token {" .. (accessToken and accessToken or "nil") .. "} - ThermostatId {" .. thermostatId .. "}")
    return
  end
  
  -- When you update the setpoint using an external way like the official Nest app you
  -- don't want that the desired setpoint in fibraro to override that.
  -- The nestSetpoint will be different from desiredSetpointValue due to external factors
  
  local nestSetpoint = device['traits']['sdm.devices.traits.ThermostatTemperatureSetpoint']['heatCelsius'] .. " °C"
  local desiredSetpoint = fibaro:getValue(thermostatVirtualDeviceId, "ui.setpoint.value")
  Trace("Setpoints " .. "[P:" .. (previousSetpoint and previousSetpoint or "nil") .. " D:" .. (desiredSetpoint and desiredSetpoint or "nil") .. " C:" .. (nestSetpoint and nestSetpoint or "nil")   .. "]")
  
  if (previousSetpoint ~= "") then
    -- on the first run previousSetpoint isn't yet initialized
          
    if (desiredSetpoint ~= nestSetpoint) then
      -- Setpoint has change. Who has done it?
      Trace("Setpoints changed [" .. nestSetpoint .. ">" .. desiredSetpoint .. "]")

      if (desiredSetpoint ~= previousSetpoint) then
        -- we've changed the setpoint in fibaro
        -- update the nest setpoint
        desiredSetpoint = convertLabelToTemperature(desiredSetpoint)        
        
        if (desiredSetpoint) then      
          local HC2 = net.HTTPClient( { timeout = 5000 })
          local url = "https://smartdevicemanagement.googleapis.com/v1/" .. thermostatId .. ":executeCommand"

          HC2:request(url, {
              options = {
                  checkCertificate = true,
                  method = 'POST',
                  headers = {
                       ['Content-Type'] = "application/json; charset=utf-8",
                       ['Authorization'] = accessToken
                  },
                  data = json.encode({
                          ['command'] = "sdm.devices.commands.ThermostatTemperatureSetpoint.SetHeat",
                          ['params'] = {['heatCelsius'] = desiredSetpoint }
                      })
              },
              success = function(response)
                  if response.status == 200 then
                      Trace("setHeatingThermostatSetpoint() succeed" .. json.encode(response.data))
                      previousSetpoint = desiredSetpoint .. " °C"
                      updateProperty(thermostatVirtualDeviceId, "ui.setpoint.value", previousSetpoint)
                      Debug("Updated temperature setpoint to [" .. previousSetpoint .. "]")
                  else
                    Error("setHeatingThermostatSetpoint() failed")
                    handleApiError(response)
                  end
              end,
              error = function(error)
                  Error("setHeatingThermostatSetpoint() failed: " .. json.encode(error))
              end
          })
        else
          Error("Can't update the thermostat. Invalid desired setpoint.")
        end
      else
        -- the setpoint has been changed by an external app
        -- update the desired setpoint to match it set by the external app
        nestSetpoint = nestSetpoint:gsub(" °C", "")
        nestSetpoint = string.format("%.1f", nestSetpoint) -- round to 1 digit precision
        nestSetpoint = nestSetpoint .. " °C"
        if (nestSetpoint ~= previousSetpoint) then
            updateProperty(thermostatVirtualDeviceId, "ui.setpoint.value", nestSetpoint)
            previousSetpoint = nestSetpoint
            Debug("Temperature setpoint updated by an [external app] to [" .. nestSetpoint .. "]")
        end
      end
    end
  else
    nestSetpoint = nestSetpoint:gsub(" °C", "")
    nestSetpoint = string.format("%.1f", nestSetpoint) -- round to 1 digit precision
    nestSetpoint = nestSetpoint .. " °C"
    updateProperty(thermostatVirtualDeviceId, "ui.setpoint.value", nestSetpoint)
    previousSetpoint = nestSetpoint
    Trace("Initialized previousSetpoint " .. nestSetpoint)
  end
end

function setThermostatMode(mode) 
    local nestMode = string.upper(mode)
    local nestCommand = ""
    
    if nestMode == 'ECO' then
        -- https://developers.google.com/nest/device-access/api/thermostat#eco_mode        
        nestCommand = "sdm.devices.commands.ThermostatEco.SetMode"
        nestMode = "MANUAL_ECO"
    else
        -- https://developers.google.com/nest/device-access/api/thermostat#standard_modes
        nestCommand = "sdm.devices.commands.ThermostatMode.SetMode"
    end    
    
    local HC2 = net.HTTPClient( { timeout = 5000 })
    local url = "https://smartdevicemanagement.googleapis.com/v1/" .. thermostatId .. ":executeCommand"
    
    HC2:request(url , {
      options = {
          checkCertificate = true,
          method = 'POST',
          headers = {
               ['Content-Type'] = "application/json; charset=utf-8",
               ['Authorization'] = accessToken
          },
          data = json.encode({
                  ['command'] = nestCommand,
                  ['params'] = {['mode'] = nestMode}
              })
      },
      success = function(response)
          if response.status == 200 then
              previousMode = mode
              Trace("setThermostatMode() succeed: " .. json.encode(response.data))
          else
              Error("setThermostatMode() failed")
              handleApiError(response)            
          end
      end,
      error = function(error)
          Error("setThermostatMode() failed: " .. json.encode(error))
      end
    })      
end

function findNestMode(device)
    thermostatMode = device['traits']['sdm.devices.traits.ThermostatMode']['mode']
    thermostatModeEco = device['traits']['sdm.devices.traits.ThermostatEco']['mode']

    if thermostatModeEco == 'MANUAL_ECO' then
        return "Eco"
    elseif thermostatMode == "HEAT" then
        return "Heat"
    elseif thermostatMode == "COOL" then
        return "Cool"
    elseif thermostatMode == "HEATCOOL" then
        return "HeatCool"
    elseif thermostatMode == "OFF" then
        return "Off"
    else
        Error("Nest is an unknown mode " .. thermostatMode .. " / " .. thermostatModeEco)
        return "Unknown"
    end
end

function findThermostat(body)
  devices = body['devices']

  for i, device in ipairs(devices) do
    if device['type'] == 'sdm.devices.types.THERMOSTAT' then
       thermostatId = device['name']
       
       -- Update the thermostat mode if needed
       updateThermostatMode(device)
       
       -- Update the ambient temperature and humidity sensors
       updateSensors(device)

       -- Update the temperature setpoint if needed
       if (previousMode ~= "Eco" and previousMode ~= "Off") then
         updateHeatingThermostatSetpoint(device)
       end
              
       Trace("findThermostat() success: " .. thermostatId)
    end
  end
end

-- https://developers.google.com/nest/device-access/api/thermostat#change_the_mode
function updateThermostatMode(device)
    local nestMode = findNestMode(device)
    local desiredMode = fibaro:getValue(thermostatVirtualDeviceId, "ui.mode.value")    

    Trace("Nest Modes " .. "[P:" .. previousMode .. " D:" .. desiredMode .. " C:" .. nestMode .. "]")
    
    if (previousMode ~= "" and nestMode ~= "Unknown") then
      -- on the first run previousMode isn't yet initialized
      if (desiredMode ~= nestMode) then
        -- Mode has change. Who has done it?

        if (desiredMode ~= previousMode) then
          Debug("Nest Mode changed [" .. nestMode .. ">" .. desiredMode .. "]")
            -- We've changed the mode in fibaro push it to Nest
            setThermostatMode(desiredMode)
        else
            -- the mode has been changed by an external app
            -- update the desired mode to match it set by the external app
            Debug("Nest Mode changed [" .. previousMode .. ">" .. nestMode .. "]")
            updateVirtualDeviceNestMode(thermostatVirtualDeviceId, nestMode)
            previousMode = nestMode
            Trace("Nest mode updated by an [external app] to [" .. nestMode .. "]")
        end
      end
    else
        updateVirtualDeviceNestMode(thermostatVirtualDeviceId, nestMode)
        previousMode = nestMode
        Trace("Initialized previousMode " .. nestMode)
    end
end

function updateSensors(device)
  local ambientTemperature = device['traits']['sdm.devices.traits.Temperature']['ambientTemperatureCelsius']
  ambientTemperature = string.format("%.1f", ambientTemperature)
  updateProperty(ambientTemperatureSensorVirtualDeviceId, "ui.temp.value", ambientTemperature .. " °C")

  updateProperty(humiditySensorVirtualDeviceId, "ui.humidity.value", device['traits']['sdm.devices.traits.Humidity']['ambientHumidityPercent'] .. " %")
end

function updateThermostatInfo()
    if accessToken == nil then
	    Error("updateThermostatInfo(): Can't update thermostat. Access Token is empty.")
      return
    end
    
    local HC2 = net.HTTPClient({ timeout = 5000 })
    local url = "https://smartdevicemanagement.googleapis.com/v1/enterprises/" .. projectId .. "/devices"
    Trace("updateThermostatInfo(): " .. url)
    
    HC2:request(url, { 
        options = {
            checkCertificate = true,
            method = 'GET',
            headers = {
                 ['Content-Type'] = "application/json; charset=utf-8",
                 ['Authorization'] = accessToken
            },
            data = nil
        },
        success = function(response)
            if response.status == 200 then
                body = json.decode(response.data)
                findThermostat(body)
                Trace("updateThermostatInfo() succeed: " .. json.encode(response.data))
            else
                Error("updateThermostatInfo() failed")
                handleApiError(response)            
                accessToken = nil
            end
        end,
        error = function(error)
            Error("updateThermostatInfo() failed")
            Error("  HTTP error: " .. error)
            accessToken = nil
        end
    })
end


function mainLoop()

  if (clientId ~= "" and clientSecret ~= "" and refreshToken ~= "" and projectId ~= "") then
    -- get a valid access token
    getAccessToken()

    --get thermostat
    updateThermostatInfo()
  else
    Error("Can't proceed: Invalid credentials! ClientId {" .. clientId .. "} ClientSecret {" .. clientSecret .. "} Refresh Token {" .. refreshToken .. "} Project Id {" .. projectId.. "}")    
  end
    
  setTimeout(mainLoop, updateFrequency * 1000) 
end

mainLoop()