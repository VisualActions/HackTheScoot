# Performance Compatibility (policy)

This page explains what each scooter's hardware and factory software allow. It is **never** an unlock, and it is **always free**.

## Three numbers, always shown separately
| Label | Meaning | Source allowed |
|---|---|---|
| **Factory maximum** | The top speed the maker states for that exact model and region | Official manual or spec page, cited |
| **Regional software limit** | A cap the firmware applies for a market (e.g. 20 / 25 km/h EU, 30 km/h US) | Official docs, or a reading of the scooter's own read-only register |
| **Observed behavior** | What the scooter actually accepted when tested | Our own captures and tests, with the date. Example: J078 sport set to 32 → ack 31; Volpam 37.3 → stayed at 35 |

Rules:
- Never put motor wattage next to top speed. Watts don't predict a safe speed.
- Never claim a speed increase. A model can show "setting above X was refused" as a fact. It can never show "you can reach Y".
- Only show a value that is above factory if it meets all of these:
  1. independently confirmed on that exact hardware **and** firmware;
  2. inside documented safe operating limits;
  3. legal in the user's region.

  Today **no** entry meets this.
- Speed sliders cap at the factory/stock maximum (J078 sport 31 km/h, Volpam 35 km/h). The UI shows **requested** and **accepted** values side by side.

## What each model page answers
Each answer is Yes / No / Unknown, with evidence:
- Can factory riding modes be selected?
- Does the maker expose an adjustable speed limit, and in what range?
- Is there a documented sport mode?
- Does the scooter reject unsupported settings? Show the observed clamp.
- Do the motor controller and the dashboard have separate firmware? (For example, Ninebot's BLE/DRV/BMS split: [firmware repo folders](https://github.com/scooterhacking/firmware).)
- Are changes temporary (lost at power-off) or persistent? Unknown for the J078 and Volpam until tested.
- Does an official recovery procedure exist?

## Never in HackTheScoot
- Universal speed-bypass commands, firmware patches, custom firmware, or flashing.
- Writing unknown registers.
- Any paid entitlement tied to speed or performance.
- A paywalled answer on incompatible scooters. We explain why it can't work instead.

## Free forever
Factory controls, factory modes, speed-limit settings within factory range, fault and warning display, safety info, and the full compatibility checker.
