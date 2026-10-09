# eco-power

Cut a Windows PC's idle power bill during hours nobody is using it, without
losing remote access (SSH / RustDesk / Parsec / RDP).

## Why not just sleep the machine?

Real sleep (S3) kills the network stack, so remote tools can't reach it
without Wake-on-LAN -- and WoL over the open internet is unreliable on most
home routers/ISPs. This script keeps Windows **awake** but throttled hard, so
remote access stays instant while power draw drops a lot:

- CPU capped low, turbo disabled
- Display and disk turned off after ~1 minute idle
- Sleep/hibernate explicitly disabled (never auto-sleeps)
- Network adapters kept powered (no silent link drop)

A Task Scheduler job flips between this "Eco" power plan and your normal one
on a daily schedule. Two generated `.bat` files let you override it manually
(e.g. you woke up early).

## Requirements

- Windows 10/11
- Admin PowerShell

## Usage

Edit the constants at the top of `setup-eco-power.ps1` for your own schedule
and hardware, then run elevated:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\path\to\setup-eco-power.ps1"
```

This creates:
- A duplicated "Eco (Unused Hours)" power scheme (your existing plans are untouched)
- 4 scheduled tasks: `EcoPower-Start/End-Weekday`, `EcoPower-Start/End-Weekend`
- `switch-to-eco.bat` / `switch-to-normal.bat` on your Desktop for manual override

Re-running the script creates a new duplicate scheme each time; delete old
ones with `powercfg /delete <GUID>` if you redo setup.

## Known limitation

`Set-NetAdapterPowerManagement` can't reliably toggle "allow the computer to
turn off this device to save power" on most drivers. If remote access drops
during Eco hours, disable that checkbox manually per adapter in Device
Manager > Network adapters > *adapter* > Properties > Power Management.

## License

MIT
