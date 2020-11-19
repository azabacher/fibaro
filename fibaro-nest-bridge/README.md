This code is based on the work done by [Guillaume Waignier](https://github.com/GuillaumeWaignier/fibaro/tree/master/quickApp/NestThermostat). He did most of the heavy lifting. Thanks!

## What does this do?
Allows you to control your Nest Thermostat from within your Home Center.

You'll be able to display the 1) temperature setpoint, 2) ambient temperature and 3) humidity percentage.

## Installation
### Step 1 - get your credentials

! To get this working you'll need to create a google nest developer account. This has a one time $5 setup fee.

* Follow the steps as [described here](https://github.com/GuillaumeWaignier/fibaro/tree/master/quickApp/NestThermostat)

Make note of the following values as you'll need them in the next step.

1. projectId
1. clientId
1. clientSecret
1. authorizationCode
1. refreshToken

### Step 2 - setup virtual devices
* Create the 3 required virtual devices: [thermostat](https://github.com/marcfon/fibaro-nest-bridge/blob/main/Nest_-_Thermostat.vfib), [temperature sensor](https://github.com/marcfon/fibaro-nest-bridge/blob/main/Nest_-_Temperature.vfib), [humidity sensor](https://github.com/marcfon/fibaro-nest-bridge/blob/main/Nest_-_Humidity.vfib)
* Make a note of the ID of the 3 virtual devices. You'll need them in the next step.

### Step 3 - create and configure the main scene

Create a new scene based on [this code](https://github.com/marcfon/fibaro-nest-bridge/blob/main/fibaro-nest-bridge.lua) and configure it using the values from step 1 and 2.

### Step 4 - run the scene
If you're lucky everything works on the first try. If not start debugging.

It's normal to get a message in the vert first run that the thermostat couldn't be updated as the access token hasn't been set yet. Wait one more update cycle and see if it works.

### Step 5 - test the virual device
Change the temperature setpoint using the virual device and see if the change is reflected on your nest.

## TODO
* ~~Implement SetMode (including ECO)~~
* Add checks around the required parameters (would be nice to have an onInit() method in a scene)
* Implement [SetCool](https://developers.google.com/nest/device-access/traits/device/thermostat-temperature-setpoint#setcool), [SetRange](https://developers.google.com/nest/device-access/traits/device/thermostat-temperature-setpoint#setrange), [SetTimer](https://developers.google.com/nest/device-access/api/thermostat#turn_the_fan_on_or_off) (someday...)
* Change the icons in the virual devices to something that reflects the state of the thermostat
* If you want to expand the functionality check the [official Nest Api](https://developers.google.com/nest/device-access/api/thermostat)

## Known issues

* Email with authentication link isn't sent when authorizationCode is not set (could be a local issue?)
* Can't fetch refresh token from within the code. Returns a 400 error. So we need to set it upfront.
* HTTP calls are async so execution flow is unpredictable.
* Probably doesn't work when you have multiple Nest thermostats
* I'm sure there are other issues as well