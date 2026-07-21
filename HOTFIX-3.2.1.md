# ps-fuel 3.2.1 hotfix

This hotfix resolves:

`server.lua:106: attempt to call a nil value (global 'GetVehicleClass')`

`GetVehicleClass` is a client-only native in this resource's runtime. The client now sends the current vehicle class with the fuel purchase request. The server continues to resolve the network entity, validate that it is a vehicle, validate the model, check distance, stock, payment, and fuel compatibility.

Replace the complete `ps-fuel` folder and restart the resource:

```cfg
restart ps-fuel
```
