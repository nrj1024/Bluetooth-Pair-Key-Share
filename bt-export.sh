#!/bin/bash
set -e

OUTPUT="${1:-bt-keys-export.json}"
BT_DIR="/var/lib/bluetooth"

if [ "$EUID" -ne 0 ]; then
    echo "Usage: sudo $0 [output-file]" >&2
    exit 1
fi

python3 -c "
import json, os, sys

bt_dir = '${BT_DIR}'
result = []

for adapter in sorted(os.listdir(bt_dir)):
    adapter_path = os.path.join(bt_dir, adapter)
    if not os.path.isdir(adapter_path):
        continue
    devices = []
    for device in sorted(os.listdir(adapter_path)):
        device_path = os.path.join(adapter_path, device)
        info_file = os.path.join(device_path, 'info')
        if not os.path.isdir(device_path) or not os.path.isfile(info_file):
            continue
        info = {}
        with open(info_file) as f:
            for line in f:
                line = line.strip()
                if '=' in line:
                    k, v = line.split('=', 1)
                    info[k] = v
        if 'Key' in info:
            devices.append({
                'mac': device,
                'name': info.get('Name', 'Unknown'),
                'key': info['Key']
            })
    if devices:
        result.append({'mac': adapter, 'devices': devices})

with open('${OUTPUT}', 'w') as f:
    json.dump(result, f, indent=2)
print(f'Exported {sum(len(a[\"devices\"]) for a in result)} key(s) to {os.path.abspath(\"${OUTPUT}\")}')
" || {
    echo "Failed: python3 is required" >&2
    exit 1
}
