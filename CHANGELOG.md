# Changelog

## 3.2.0 — Production Release

- Added the missing petrol and EV sound files referenced by the NUI.
- Added server callback rate limiting and stronger random session tokens.
- Made vehicle-fuel persistence validate the networked vehicle and actual plate.
- Replaced the local `/setfuel` command with a server-authorised ACE command.
- Added robbery session tokens, elapsed-time validation, cancellation and atomic payouts.
- Made station withdrawals atomic and restore balances if bank payment fails.
- Added assigned truck/tanker validation to delivery loading and completion.
- Added delivery and robbery cleanup on disconnect/resource stop.
- Added database audit logs, useful indexes and configurable retention cleanup.
- Synchronised configured station labels/capacity into existing database records.
- Added `LegacyFuel` compatibility provider and explicit OneSync dependency.
- Added nozzle cleanup on death/logout and target cleanup on resource stop.
- Added fatal configuration validation for duplicate station/charger IDs and invalid station links.
- Added safe handling for missing/disabled Jerry Can configuration and optional dispatch events.
- Hardened dynamic pricing, automatic restocking and configurable reward ranges against invalid values.
- Restricted fuel-leak repairs to configured jobs or ACE permissions.
- Removed experimental OAL mode to maximise compatibility with third-party natives and resources.
- Updated documentation and public-release testing guidance.
