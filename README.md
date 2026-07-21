# Recoil Fuel 3.2.1

Advanced Qbox fuel system for FiveM with Renewed Banking-compatible player payments.


## 3.2.1 hotfix
- Fixed the server crash caused by calling the client-only `GetVehicleClass` native.
- Vehicle class is now read on the client and passed to the server purchase callback.
- The server still validates the real networked vehicle entity and model before charging the player.

## Features
- Persistent fuel saved by vehicle plate
- Configurable consumption by RPM and vehicle class
- Paid refuelling through Qbox bank/cash balances
- Fuel station ownership, income, withdrawals and price multipliers
- Jerry can purchases
- NUI station management panel
- ACE-protected admin statistics panel (`/fueladmin`)
- Transaction and sales tracking
- ox_lib notifications and callbacks
- State-bag synchronisation
- Exports for HUDs and other resources

## Requirements
- qbx_core
- ox_lib
- oxmysql
- Renewed-Banking

## Installation
1. Import `install.sql` into your Qbox database.
2. Place `ps-fuel` in your resources folder.
3. Start dependencies before the resource:
```cfg
ensure ox_lib
ensure oxmysql
ensure qbx_core
ensure Renewed-Banking
ensure ps-fuel
```
4. Remove or disable `ox_fuel`.
5. Add admin permissions:
```cfg
add_ace group.owner recoilfuel.admin allow
add_ace group.admin recoilfuel.admin allow
add_ace group.owner command.setfuel allow
add_ace group.admin command.setfuel allow
```

## Controls
- Hold `E` near a pump to refuel.
- Press `G` near a station to open the station panel.
- `/fuel` displays fuel.
- `/setfuel 100` is ACE-restricted.
- `/fueladmin` opens global statistics for authorised staff.

## Exports
```lua
local fuel = exports['ps-fuel']:GetFuel(vehicle)
exports['ps-fuel']:SetFuel(vehicle, 100.0)
```

## Notes
- Personal payments use Qbox money functions so Renewed Banking remains synchronised.
- Station profits are stored in `ps_fuel_stations.balance` and owners withdraw them to their bank.
- The jerry-can item name may need changing in `Config.JerryCan.Item` to match your TGIANN item list.


## 3.0 Premium features
- Dynamic global and low-stock fuel pricing
- Fuel station stock and capacity
- Delivery jobs that replenish station inventory
- Fuel station robberies with police count and cooldowns
- Electric vehicle charging configuration
- Persistent crash-triggered fuel leaks
- Built-in localization directory

## Upgrade
Re-import `install.sql`; the upgrade statements use `ADD COLUMN IF NOT EXISTS`.

Add:
```cfg
setr ox:locale en
add_ace group.owner command.repairfuelleak allow
add_ace group.admin command.repairfuelleak allow
```

The delivery callback returns configured truck/trailer models. Vehicle spawning is intentionally left compatible with your preferred Qbox keys/garage system.


## 3.0.3 Delivery and station update
- Starting a delivery teleports the player to the depot
- Spawns the configured truck and tanker
- Automatically seats the player in the truck
- Optionally attaches the tanker
- Sets the waypoint back to the selected station
- Deletes delivery vehicles after successful completion
- Adds fuel station blips to the map
- Automatically replenishes station stock on a configurable timer
- Supports automatic restocking for owned and unowned stations

Configure these sections:
- `Config.Deliveries`
- `Config.AutoRestock`
- `Config.Blips`


## 3.0.4 player-owned station delivery flow

The delivery job now works as follows:

1. The station owner opens their station menu.
2. They select **Start fuel delivery**.
3. They are teleported to the delivery depot.
4. The truck and tanker are spawned and attached.
5. They drive to the fuel loading terminal.
6. They press `E` and wait while the tanker is filled.
7. They return to the station where the job was started.
8. They press `E` and unload the tanker into that station.
9. The station stock is increased and the player is paid.

`Config.Deliveries.OwnerOnly` controls whether only station owners can start deliveries.


## 3.0.5 delivery spawn fix

- Delivery truck and tanker are now created server-side with OneSync.
- The client waits for both network entities to stream in.
- The trailer attachment is retried for five seconds.
- The player is placed into the delivery truck only after both entities exist.
- Delivery entities are cleaned up when the driver disconnects.


## 3.0.6 delivery completion fix

- Fixed `table index is nil` when completing a delivery.
- The Qbox citizen ID is now validated before applying the cooldown.
- Added station-capacity validation.
- Added safe delivery reward configuration and Qbox bank-payment validation.


## 3.0.7 payment and delivery fix
- Fixed `marketMultiplier` scope causing refuelling callbacks to fail.
- Qbox money removal now supports versions returning `nil` on success.
- New stations receive stock and capacity immediately.
- Delivery server radius now matches the configured delivery radius.
- Delivery stock updates are validated before completing the job.
- Full stations no longer erase the active delivery.


## 3.1.0 premium tablet interface
- Rebuilt the station and administration NUI as a physical landscape tablet.
- Added Overview, Operations and Ledger navigation views.
- Added live station stock percentage, reserve gauge and low-stock messaging.
- Added premium analytics cards, operation cards and a full transaction ledger.
- Added responsive scaling for common FiveM resolutions.
- Preserved every existing NUI callback and server-side economy check.

## React + TypeScript NUI
The physical fuel tablet is now implemented in `web/src/App.tsx` using shadcn/ui component source, Radix primitives, Tailwind CSS and Lucide icons. All existing NUI callback names are preserved.

To rebuild:
```bash
cd web
npm ci
npm run build
```
FiveM loads the production files in `web/dist`.

## 3.2.0 ownership and multi-fuel update

Station management access is owner-gated by default. Unowned stations must be purchased before their management tablet opens. The pump terminal supports Petrol, Premium and Diesel, with configurable pricing and vehicle compatibility in `config.lua`.
