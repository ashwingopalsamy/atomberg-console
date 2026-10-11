# The 100-call budget

Atomberg's developer API allows **100 calls a day** and 5 a second on the free plan. The count includes failed
calls, and resets at 00:00 UTC. Atomberg Console spends as few as it can.

| Action | Calls |
|---|---|
| Refresh all devices | 1 (`device_id=all` reads every device in one call) |
| Command to a fan heard on your Wi‑Fi | 0 |
| Command to a fan through the cloud | 1 |
| Command to a purifier | 1 |
| Usage figures (kWh, hours) | at most once a day, only when you open a detail screen |
| Access token | about one a day |

## What it does to stay under

- A refresh is a single call for every device.
- The popover refreshes only if its data is over two hours old (six hours when every device is a fan heard
  locally). Settings → Refresh does it on demand.
- Background reads stop when only 20 calls are left, which keeps them for your own commands.
- A slow reply to a command is not followed by a second call to check it.

## See what it spent

Every cloud request is one line in `~/Library/Application Support/ATOMBERG/calls.log`: time, method, path,
purpose, status. Headers, bodies and tokens are never written. Settings shows how many calls are left today.
