# PS Fuel 3.2.1 — Production Release

This is the Fuel Network separated from `ps-tablet`. It does not require the tablet and includes its own FuelOS station-management and fuel-selection NUI.

## Features

- Physical petrol, diesel and premium nozzles
- Rope hoses and configurable maximum hose distance
- Custom electric chargers and charging connectors
- Standard and fast EV charging modes
- In-game persistent vehicle fuel/EV configuration by model
- Floating refuel/charge progress above the vehicle without a boxed UI
- No pickup or refuelling animation by default
- 27 configured fuel stations with map blips
- Four player-ownable stations and 23 public stations by default
- Cash or bank payments
- Dynamic prices, global tax and emergency-service discounts
- Vehicle fuel persistence and leak damage
- Fuel station ownership, stock, transactions and withdrawals
- Tanker delivery jobs, automatic restocking and robberies
- Emergency fuel cans
- `ps-fuel` GetFuel/SetFuel compatibility exports
- `cdn-fuel` and `LegacyFuel` compatibility providers
- Startup configuration validation for duplicate stations and invalid charger links
- Authorised mechanic/admin fuel-leak repair command
- Server-authorised robbery sessions, vehicle persistence and delivery validation
- Atomic station withdrawals and database audit logging
- Included petrol and EV sound assets (no missing NUI audio files)

## Required resources

```cfg
ensure ox_lib
ensure oxmysql
ensure qbx_core
ensure ox_target
ensure ps-fuel
```

OneSync is required and declared in the manifest.

Do not start the donor `cdn-fuel` or another `ps-fuel` at the same time.

## Database

The resource automatically creates and upgrades its `ps_fuel_*` tables, including `ps_fuel_vehicle_profiles`. Existing data from the tablet-integrated version is reused. No manual SQL import is required. A manual SQL file remains available at `install/ps-fuel.sql`.

## Commands

```text
/fuel                  Show the current vehicle fuel level
/fuelstation           Open the nearby public/owner station terminal
/fueladmin             Open fuel administration (ACE restricted)
/fuelvehicleconfig     Configure the nearest vehicle model as petrol, diesel or electric
/setfuel 100           Set the nearest/current vehicle fuel
/repairfuelleak        Repair the current/nearest vehicle fuel leak
/closefuel             Force-close the FuelOS NUI
```

Authorised administrators also receive **Configure vehicle fuel type** when third-eyeing a vehicle. The choice applies to every vehicle using that model and saves immediately without a restart.

Electric models can be configured with or without fast-charge support. Choosing **Automatic detection** removes the database override and returns the model to the rules in `config.lua`.

## ACE permission

```cfg
add_ace group.admin ps-fuel.admin allow
add_ace group.owner ps-fuel.admin allow

# Allow mechanics to use /repairfuelleak through ACE if desired.
add_ace group.mechanic ps-fuel.repair allow
```

`/repairfuelleak` also accepts framework jobs and minimum grades configured in
`PSFuelConfig.Leaks.RepairJobs`.

The same permission controls `/fueladmin`, `/fuelvehicleconfig`, and the vehicle configuration third-eye option unless `PSFuelConfig.VehicleConfiguration.AdminAce` is changed.

## Charging modes

Standard charging uses:

```lua
PSFuelConfig.Electric.ChargeSpeed
PSFuelConfig.Electric.PricePerFuel
```

Fast charging uses:

```lua
PSFuelConfig.Electric.FastCharge.ChargeSpeed
PSFuelConfig.Electric.FastCharge.PriceMultiplier
```

Fast charge only appears when:

1. The vehicle model is configured as electric and supports fast charging.
2. `PSFuelConfig.Electric.FastCharge.Enabled` is enabled.
3. The selected charger supports fast charging.

Every charger supports it by default. Set `fastCharge = false` on an individual charger entry to disable it there.

## Refuelling display and controls

After the nozzle is inserted and a fuel/charge mode is selected, live percentage, selected type and amount paid render as plain world text above the vehicle. No boxed process UI or stop-control hint is shown.

The configured cancel key remains available as an emergency control but is intentionally not displayed:

```lua
PSFuelConfig.CancelRefuelKey = 73 -- X
```

No animations play while taking or using the nozzle because:

```lua
PSFuelConfig.Nozzles.Animation.Enabled = false
```

## Compatibility exports

```lua
local fuel = exports['ps-fuel']:GetFuel(vehicle)
exports['ps-fuel']:SetFuel(vehicle, 100.0)

local holdingEVNozzle = exports['cdn-fuel']:IsHoldingElectricNozzle()
exports['cdn-fuel']:SetElectricNozzle('pickup')
exports['cdn-fuel']:SetElectricNozzle('putback')
```

## Configuration

Edit `config.lua` to change station positions, ownership, prices, tax, fuel types, static diesel/electric models, charge speeds, fast-charge pricing, EV chargers, nozzles, world-display height, hose behaviour, emergency discounts, deliveries, robberies and blips.

The imported donor assets and behaviours retain their GPL notices at `https://github.com/codinedev/cdn-fuel?tab=GPL-3.0-1-ov-file and https://github.com/Project-Sloth/ps-fuel?tab=GPL-3.0-1-ov-file`.


## Public-release notes

- Keep the resource folder named `ps-fuel`.
- Do not run another resource providing `ps-fuel`, `cdn-fuel` or `LegacyFuel`.
- The entire combined resource is distributed under GPL-3.0 because it incorporates GPL-licensed donor code and assets. If you sell it, buyers must receive the complete corresponding source and GPL rights, including the right to redistribute original or modified copies.
- Run the checklist in `TESTING.md` on a staging server before deploying updates.
