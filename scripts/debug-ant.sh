#!/bin/bash
# ANT+ Debug Script for PedalHUD
# Monitors USB stick detection, ANT+ protocol messages, and HR sensor discovery
# Run: ./scripts/debug-ant.sh

set -euo pipefail

PEDALHUD_APP="/Applications/PedalHUD.app"

echo "=========================================="
echo "  PedalHUD ANT+ Debug Tool"
echo "=========================================="
echo ""

# Step 1: Check USB stick
echo "--- Step 1: USB Stick Detection ---"
ANT_USB=$(ioreg -p IOUSB -w0 | grep -i "ant\|0fcf" || true)
if [ -z "$ANT_USB" ]; then
    echo "❌ No ANT+ USB stick found in IOKit registry"
    echo "   → Plug in Garmin ANT+ USB stick"
    exit 1
else
    echo "✅ ANT+ USB stick found:"
    echo "   $ANT_USB"
fi
echo ""

# Step 2: Kill existing and restart
echo "--- Step 2: Restart PedalHUD ---"
pkill -f "PedalHUD.app" 2>/dev/null || true
sleep 2

# Start via 'open' to get proper bundle/entitlements
open "$PEDALHUD_APP"
sleep 2
PEDALHUD_PID=$(ps aux | grep "[/]Applications/PedalHUD" | awk '{print $2}' | head -1)

if [ -z "$PEDALHUD_PID" ]; then
    echo "❌ PedalHUD failed to start"
    echo "   Check: ~/Library/Logs/DiagnosticReports/PedalHUD*"
    exit 1
fi
echo "✅ PedalHUD running (PID: $PEDALHUD_PID)"
echo ""

# Step 3: Monitor unified log for ANT+ activity
echo "--- Step 3: Monitoring ANT+ activity (20 seconds) ---"
echo "   Watching unified log for PID $PEDALHUD_PID"
echo ""

# Capture baseline timestamp
START_TIME=$(date "+%Y-%m-%d %H:%M:%S")
sleep 18

# Step 4: Collect and analyze logs
echo ""
echo "--- Step 4: Analysis ---"
echo ""

# Get all USBDevice category logs
USB_LOGS=$(/usr/bin/log show --predicate "processIdentifier == $PEDALHUD_PID AND category == 'USBDevice'" --start "$START_TIME" 2>&1 || true)
ANT_LOGS=$(/usr/bin/log show --predicate "processIdentifier == $PEDALHUD_PID AND category == 'ANTPlus'" --start "$START_TIME" 2>&1 || true)
ALL_LOGS=$(/usr/bin/log show --predicate "processIdentifier == $PEDALHUD_PID AND eventMessage CONTAINS 'ANT'" --start "$START_TIME" 2>&1 || true)

# USB Device Open
if echo "$USB_LOGS" | grep -q "opened\|Endpoint\|pipe"; then
    echo "✅ USB device opened successfully"
    echo "$USB_LOGS" | grep "opened\|Endpoint\|pipe" | head -5
else
    echo "❌ USB device NOT opened (no USBDevice logs)"
fi
echo ""

# Writes
WRITE_COUNT=$(echo "$USB_LOGS" | grep -c "Wrote" || echo "0")
if [ "$WRITE_COUNT" -gt 0 ]; then
    echo "✅ ANT+ messages sent: $WRITE_COUNT"
    echo "$USB_LOGS" | grep "Wrote" | head -6
else
    echo "❌ No ANT+ messages sent"
fi
echo ""

# Channel responses
if echo "$ANT_LOGS" | grep -q "channel response\|startup"; then
    echo "✅ ANT+ responses received"
    echo "$ANT_LOGS" | grep "channel response\|startup" | head -5
fi
echo ""

# HR sensor
if echo "$ANT_LOGS" | grep -q "HR sensor\|heart rate\|Discovered"; then
    echo "✅ HR sensor detected!"
    echo "$ANT_LOGS" | grep "HR sensor\|heart rate\|Discovered" | head -5
else
    echo "⚠️  No HR sensor found yet"
    echo "   Is chest strap active (wet + worn)?"
fi
echo ""

# Any errors
ERRORS=$(echo "$USB_LOGS" "$ANT_LOGS" | grep -i "error\|fail" || true)
if [ -n "$ERRORS" ]; then
    echo "⚠️  Errors found:"
    echo "$ERRORS" | head -5
fi
echo ""

echo "--- Done ---"
echo "PedalHUD PID: $PEDALHUD_PID"
echo ""
echo "Live monitor: /usr/bin/log stream --predicate 'processIdentifier == $PEDALHUD_PID AND (category == \"USBDevice\" OR category == \"ANTPlus\")'"
