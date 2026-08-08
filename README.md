# Bluetooth-Pair-Key-Share

Share the Bluetooth pair keys between Linux and Windows in a dual-boot setup, so you don't have to re-pair your devices every time you switch operating systems.

## How it works

1. On **Linux**, export the stored Bluetooth link keys (`/var/lib/bluetooth`) to a JSON file with `bt-export.sh`.
2. Transfer the JSON file to your Windows partition.
3. On **Windows**, import those keys into the Bluetooth registry with `bt-import.ps1` (run as Administrator).
4. Reboot — your devices stay paired across both OSes.

## Files

| File | Purpose |
|------|---------|
| `bt-export.sh` | Exports Bluetooth link keys from Linux to a JSON file |
| `bt-import.ps1` | Imports the JSON file into the Windows Bluetooth registry |

## Usage

### Export (Linux)

```bash
sudo ./bt-export.sh [output-file.json]
```

Defaults to `bt-keys-export.json`. Requires `python3`. Run with `sudo` because the Bluetooth keys live under `/var/lib/bluetooth`.

### Import (Windows)

Open PowerShell as **Administrator** and run:

```powershell
.\bt-import.ps1 [-InputFile bt-keys-export.json]
```

The script takes ownership of the Bluetooth keys registry key, grants Administrators full control, and writes each device's link key. **Reboot** after importing for the changes to take effect.

## Requirements

- **Linux**: `python3`, `sudo`, and a systemd/bluetoothd that stores keys under `/var/lib/bluetooth`
- **Windows**: PowerShell with Administrator privileges

## Notes

- Only devices with a `Key` entry in their `info` file are exported.
- Keys are sensitive credentials — don't share the exported JSON file publicly.
