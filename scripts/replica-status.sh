#!/bin/bash
# Check dfx replica status and output JSON
# Output: {"running": true/false, "pid": number|null, "uptime_seconds": number|null}

set -euo pipefail

# Check if dfx is installed
if ! command -v dfx &>/dev/null; then
    echo '{"running": false, "pid": null, "uptime_seconds": null, "error": "dfx not installed"}'
    exit 1
fi

# Check if replica is responding
if dfx ping &>/dev/null; then
    # Find replica process
    PID=$(pgrep -f "replica" 2>/dev/null | head -1 || echo "")

    if [ -n "$PID" ]; then
        # Get process start time and calculate uptime (macOS compatible)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS: use ps to get elapsed time in seconds
            ELAPSED=$(ps -p "$PID" -o etime= 2>/dev/null | awk '{
                # Parse [[dd-]hh:]mm:ss format
                n = split($1, a, ":");
                if (n == 2) {
                    # mm:ss
                    print a[1]*60 + a[2];
                } else if (n == 3) {
                    # hh:mm:ss or dd-hh:mm:ss
                    if (index(a[1], "-") > 0) {
                        split(a[1], b, "-");
                        print b[1]*86400 + b[2]*3600 + a[2]*60 + a[3];
                    } else {
                        print a[1]*3600 + a[2]*60 + a[3];
                    }
                }
            }')
            UPTIME=${ELAPSED:-0}
        else
            # Linux: use /proc filesystem
            START_TIME=$(stat -c %Y /proc/"$PID" 2>/dev/null || echo "0")
            NOW=$(date +%s)
            UPTIME=$((NOW - START_TIME))
        fi

        echo "{\"running\": true, \"pid\": $PID, \"uptime_seconds\": $UPTIME}"
    else
        # Replica responding but can't find PID (maybe using different process name)
        echo '{"running": true, "pid": null, "uptime_seconds": null}'
    fi
else
    echo '{"running": false, "pid": null, "uptime_seconds": null}'
fi
