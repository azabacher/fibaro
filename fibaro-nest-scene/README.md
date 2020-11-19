This scene is designed to be used together with the [Fibaro Nest Bridge](https://github.com/marcfon/fibaro/tree/main/fibaro-nest-bridge). If you don't have that running set it up first.

## What does this scene do?

This scene allows you to control the temperature in one or more fibaro heating zones using your Nest thermostat.

### 1. Control the temperature through Nest

When you turn the temperature up directly on your Nest (or using the app) the thermostat valves in the specified heating zones will fully open. Allowing the zone to heat up.

When the ambient temperature reaches the desired temperature Nest will turn off your heating and this scene will close all the valves.

### 2. Control the temperature through Heating Zones

When you use the manual mode to heat up a zone this scene will set your Nest to the temperature you've specified and open the valves in that zone. When the manual modes it will lower the temperature on your Nest to just below the ambient temperature and close the valves in the heating zone.

## Getting started

1. Make sure you have the [Fibaro Nest Bridge](https://github.com/marcfon/fibaro/tree/main/fibaro-nest-bridge) up and running before moving on
2. Create a zone in your fibaro heating panel that you want to control with your Nest
3. Set the temperature **must to be 8 degrees** at all times in that zone. 
4. Find the ID of your zone(s) by going to https://your_hc2_ip/api/panels/heating/

## Installation

1. Create a new LUA scene 
2. Add the code to the scene
3. Specify these things the scene
   1. `nestThermostat` -- The id of the Nest thermostat virual device (from your [Fibaro Nest Bridge](https://github.com/marcfon/fibaro/tree/main/fibaro-nest-bridge) )
   2. `nestThermostatAmbientTemperatureSensor` -- The id of the Nest ambient temperature sensor
   3. `heatingPanels` -- Table of IDs of the heating zones you want to control
4. Enable the scene to run when Fibaro starts.

## Limitations

* This scene was only tested using a gen 2 Nest thermostat and the Eurotronic Sprit valves.