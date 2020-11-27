--[[
This code is inspired by:
https://github.com/GuillaumeWaignier/fibaro/tree/master/quickApp/NestThermostat
https://github.com/GuillaumeWaignier/fibaro/blob/master/quickApp/NestThermostat/quickApp.lua

%% properties
%% events
%% globals
--]]

if (fibaro:countScenes() > 1) then
	fibaro:debug("Scene already active! Aborting this new instance !!");
	fibaro:abort();
end

--------------------- USER SETTINGS --------------------------------
--------------------- SET THESE BEFORE FIRST RUN -------------------

local projectId = "";
local clientId = "";
local clientSecret = "";
local authorizationCode = "";
-- TODO this should be a global variable?
-- FIXME why can't refresh token be empty on the first run??
-- Could it be that once you've generated the refresh token via the 
-- command line via CURL you can't invoke the "grant_type=authorization_code"
-- command again as it will return the "invalid_grant" error?
-- So once the refresh token has been provided for a specific
-- authorizationCode you can't ask for the refresh token ever again?
local refreshToken = ""

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
--------------------- AUTHENTICATION -------------------------------

-- Send a mail to request a new a new Refresh Token
function sendMailForRefreshToken()
    if authorizationCode ~= nil or refreshToken ~= "" then
        return
    end

    Error("Need to refresh Nest Authorization Code")
   
    local url = "https://nestservices.google.com/partnerconnections/" .. projectId .. "/auth?redirect_uri=https://www.google.com&access_type=offline&prompt=consent&client_id=" .. clientId .. "&response_type=code&scope=https://www.googleapis.com/auth/sdm.service"

		-- FIXME mail isn't sent somehow
    fibaro:call (2, "sendEmail", "Fibaro request link to google Nest", url)

  	Error("[Authorization Code] Open this link to generate a new code: " .. url)
end

function getRefreshToken()
    if authorizationCode == nil or refreshToken ~= "" then
      return
    end

    Debug("[getRefreshToken()] Get Google refresh token")

    local HC2 = net.HTTPClient( { timeout = 3000 })
    local url = "https://www.googleapis.com/oauth2/v4/token?client_id=" .. clientId .. "&client_secret=" .. clientSecret .. "&code=" .. authorizationCode .. "&grant_type=authorization_code&redirect_uri=https://www.google.com"
    
    Debug("[Refresh Token] " .. url)
  
  	HC2:request(url, {
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
                refreshToken = body['refresh_token']
                Debug("getRefreshToken() succeed")
                Debug(accessToken .. "   " ..  refreshToken)
            else
              Error("getRefreshToken() failed: " .. response.status .. "  " .. json.encode(response.data))
              -- FIXME turned this off as getting the refresh token isn't working yet
              -- authorizationCode = nil
            end
        end,
        error = function(error)
            Error("getRefreshToken() failed: " .. json.encode(error))
            -- FIXME turned this off as getting the refresh token isn't working yet
            -- authorizationCode = nil
        end
    })
end

function getAccessToken()
    if refreshToken == "" or accessToken ~= nil then
      return
    end

    local HC2 = net.HTTPClient({ timeout = 3000 })
    local url = "https://www.googleapis.com/oauth2/v4/token?client_id=" .. clientId .. "&client_secret=" .. clientSecret .. "&refresh_token=" .. refreshToken .. "&grant_type=refresh_token"
    Trace("[Access Token] " .. url)
    
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
                Debug("getAccessToken() succeed")
                Trace(accessToken)
            else
                Error("getAccessToken() failed: " .. json.encode(response.data))
                refreshToken = ""
            end
        end,
        error = function(error)
            Error("getAccessToken() failed: " .. json.encode(error))
            refreshToken = ""
        end
    })
end

-------------------------------------------------------------------- 
--------------------- API CALLS ------------------------------------

-- Updates the property in the specified virtual device
function updateProperty(deviceId, label, value) 
  fibaro:call(deviceId, "setProperty", label, value)
  Trace("[Update device " .. deviceId .. " " .. label ..  " ] " .. value)  
end

-- https://developers.google.com/nest/device-access/api/thermostat#change_the_temperature_setpoints
function updateHeatingThermostatSetpoint(device)
  if (accessToken == nil or thermostatId == "") then
    Error("Can't update thermostat setpoint.")
    return
  end
  
  -- When you update the setpoint using an external way like the official Nest app you
  -- don't want that the desired setpoint in fibraro to override that.
  -- The nestSetpoint will be different from desiredSetpointValue due to external factors
  
  local nestSetpoint = device['traits']['sdm.devices.traits.ThermostatTemperatureSetpoint']['heatCelsius'] .. " °C"
  local desiredSetpoint = fibaro:getValue(thermostatVirtualDeviceId, "ui.setpoint.value")
  Trace("Setpoints " .. "[P:" .. previousSetpoint .. " D:" .. desiredSetpoint .. " C:" .. nestSetpoint .. "]")
  
  if (previousSetpoint ~= "") then
    -- on the first run previousSetpoint isn't yet initialized
          
    if (desiredSetpoint ~= nestSetpoint) then
      -- Setpoint has change. Who has done it?
      Trace("Setpoints changed [" .. nestSetpoint .. ">" .. desiredSetpoint .. "]")

      if (desiredSetpoint ~= previousSetpoint) then
        -- we've changed the setpoint in fibaro
        -- update the nest setpoint
        desiredSetpoint = desiredSetpoint:gsub(" °C", "");
        desiredSetpoint = tonumber(desiredSetpoint)
      
        local HC2 = net.HTTPClient( { timeout = 3000 })
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
                    Error("setHeatingThermostatSetpoint() failed: " .. response.status)
                    Error("setHeatingThermostatSetpoint() failed: " .. json.encode(response.data))
                end
            end,
            error = function(error)
                Error("setHeatingThermostatSetpoint() failed: " .. json.encode(error))
            end
        })
      else
        -- the setpoint has been changed by an external app
        -- update the desired setpoint to match it set by the external app
        nestSetpoint = nestSetpoint:gsub(" °C", "")
        nestSetpoint = string.format("%.1f", nestSetpoint) -- round to 1 digit precision
        nestSetpoint = nestSetpoint .. " °C"
        updateProperty(thermostatVirtualDeviceId, "ui.setpoint.value", nestSetpoint)
        previousSetpoint = nestSetpoint
        Debug("Temperature setpoint updated by an [external app] to [" .. nestSetpoint .. "]")
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
    
    
    local HC2 = net.HTTPClient( { timeout = 3000 })
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
              Error("setThermostatMode() failed: " .. json.encode(response.data))
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
        Error("[updateMode() failed] Unknown mode " .. thermostatMode .. " / " .. thermostatModeEco)
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
            updateProperty(thermostatVirtualDeviceId, "ui.mode.value", nestMode)
            previousMode = nestMode
            Trace("Nest mode updated by an [external app] to [" .. nestMode .. "]")
        end
      end
    else
        updateProperty(thermostatVirtualDeviceId, "ui.mode.value", nestMode)
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
	    Error("Can't update thermostat. Access Token is empty.")
      return
    end
    
    local HC2 = net.HTTPClient({ timeout = 3000 })
    local url = "https://smartdevicemanagement.googleapis.com/v1/enterprises/" .. projectId .. "/devices"
    Trace("[updateThermostatInfo] " .. url)
    
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
                Error("updateThermostatInfo() failed: " .. json.encode(response.data))
                accessToken = nil
            end
        end,
        error = function(error)
            Error("updateThermostatInfo() failed: " .. json.encode(error))
            accessToken = nil
        end
    })
end


function mainLoop()

  --login
  sendMailForRefreshToken()
  getRefreshToken()
  
  -- FIXME getAccessToken() will return before the HTTP call has finished
  -- meaning that on the first run the access token won't be set yet
  -- not a deal breaker but would be nice to fix
  getAccessToken()
  
  --get thermostat
  updateThermostatInfo()
    
  setTimeout(mainLoop, 1 * updateFrequency * 1000) 
end

mainLoop()