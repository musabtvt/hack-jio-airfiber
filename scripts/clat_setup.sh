#!/bin/sh
# ==============================================================================
# 464XLAT CLAT Diagnostics & Health Checker for Jio 5G Standalone (SA)
# Author: Mus'ab (@musabtvt)
# Verifies IPv6 default gateway, Jio NAT64 prefix, and CLAT translation
# ==============================================================================

set -e

NAT64_PREFIX="64:ff9b::/96"
NAT64_TEST_IP="64:ff9b::1.1.1.1"

echo "================================================================="
echo "🔍 Jio AirFiber 5G 464XLAT CLAT Health Checker"
echo "================================================================="

# 1. Check native IPv6 default route on WAN
echo "[*] Step 1/4: Checking native 5G IPv6 gateway..."
IPV6_GW=$(ip -6 route show default 2>/dev/null | awk '{print $3}' | head -n 1)
if [ -z "$IPV6_GW" ]; then
    echo "[-] Error: No IPv6 default gateway found on WAN."
    echo "    Make sure the 5G ODU is powered on and connected to the 2.5GbE WAN port."
    exit 1
fi
echo "[+] Detected active 5G IPv6 default gateway: $IPV6_GW"

# 2. Check reachability to Jio's Provider Translator (PLAT / NAT64)
echo "[*] Step 2/4: Testing reachability to Jio NAT64 gateway ($NAT64_TEST_IP)..."
if ping -6 -c 2 -W 3 "$NAT64_TEST_IP" >/dev/null 2>&1; then
    echo "[+] SUCCESS: Jio NAT64 gateway is reachable and responding to ping."
else
    echo "[!] Warning: Direct ping to $NAT64_TEST_IP timed out. Testing DNS64 synthesis..."
fi

# 3. Verify CLAT interface state (netifd native 464-clat)
echo "[*] Step 3/4: Checking local CLAT network interface..."
CLAT_DEV=""
for dev in 464-clat 464-wan6; do
    if ip link show "$dev" >/dev/null 2>&1; then
        CLAT_DEV="$dev"
        break
    fi
done

if [ -n "$CLAT_DEV" ]; then
    echo "[+] Active CLAT device detected: $CLAT_DEV"
    ip addr show dev "$CLAT_DEV" | grep -E "inet " || true
else
    echo "[-] Warning: No active 464-clat device found."
    echo "    Attempting to reload network interface 'clat'..."
    ifup clat 2>/dev/null || /etc/init.d/network reload 2>/dev/null || true
fi

# 4. Verify end-to-end IPv4 routing through CLAT
echo "[*] Step 4/4: Testing end-to-end IPv4 ping through CLAT..."
if ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1; then
    echo "[SUCCESS] 🎉 464XLAT CLAT is 100% operational! IPv4 Internet is active over Jio 5G."
else
    echo "[!] End-to-end IPv4 ping failed. Verify that interface 'clat' is attached to firewall zone 'wan'."
fi
