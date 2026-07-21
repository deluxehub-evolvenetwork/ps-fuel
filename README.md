# PLUUUX Solutions Fuel System 3.2.1

Advanced Qbox fuel system for FiveM with Renewed Banking-compatible player payments.

## 3.2.1 Hotfix

- Fixed the server crash caused by calling the client-only `GetVehicleClass` native.
- Vehicle class is now read on the client and passed to the server purchase callback.
- The server still validates the real networked vehicle entity and model before charging the player.

## Features

- Persistent fuel saved by vehicle plate
- Configurable consumption by RPM and vehicle class
- Paid refuelling through Qbox bank and cash balances
- Petrol, Premium and Diesel fuel support
- Configurable electric vehicle charging
- Fuel station ownership and purchasing
- Station income, withdrawals and price multipliers
- Fuel station stock and capacity
- Dynamic global and low-stock fuel pricing
- Player-owned station delivery jobs
- Automatic station restocking
- Fuel station robberies with police requirements and cooldowns
- Jerry can purchases
- Persistent crash-triggered fuel leaks
- Premium station management interface
- ACE-protected administration panel
- Transaction and sales tracking
- Fuel station map blips
- ox_lib notifications and callbacks
- State-bag synchronisation
- Exports for HUDs and other resources
- Built-in localisation support

## Requirements

- `qbx_core`
- `ox_lib`
- `oxmysql`
- `Renewed-Banking`

## Installation

1. Import `install.sql` into your Qbox database.
2. Place the resource inside your FiveM resources folder.
3. Make sure the resource folder is named:

```text
ps-fuel
