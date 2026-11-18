#!/bin/sh
# ==============================================================================
# Jio JIDU6401 Tri-Color Status LED Monitor Driver
# Production driver for Sercomm JIDU6401 / MediaTek Filogic 830 (MT7986)
# https://github.com/musabtvt/jio-airfiber-openwrt-5g-wan
#
# Status Colors:
#   🟢 Solid Green:    Dual-stack IPv4 (CLAT) + IPv6 active (Optimal, <150ms)
#   🟡 Solid Yellow:   High latency (>150ms) / Degraded connection
#   🔵 Solid Blue:     Native IPv6 connected, CLAT pending
#   🔴 Solid Red:      No Internet connectivity
#   🔴 Blinking Red:   5G WAN link down (physical carrier lost)
#   🌙 Night Mode:     LEDs automatically disabled between 22:00 and 06:00
#   📶 Wi-Fi Alerts:   Blue flash on device join, Yellow flash on device leave
# ==============================================================================

trap 'turn_off_all; exit 0' TERM INT

RED_LED="/sys/class/leds/red:status"
GREEN_LED="/sys/class/leds/green:status"
BLUE_LED="/sys/class/leds/blue:status"

set_led() {
    echo none > "${1}/trigger" 2>/dev/null
    echo "$2" > "${1}/brightness" 2>/dev/null
}

blink_led() {
    echo timer > "${1}/trigger" 2>/dev/null
    echo "${2:-500}" > "${1}/delay_on" 2>/dev/null
    echo "${2:-500}" > "${1}/delay_off" 2>/dev/null
}

turn_off_all() {
    set_led "$RED_LED" 0
    set_led "$GREEN_LED" 0
    set_led "$BLUE_LED" 0
}

is_upgrading() {
    pgrep -f "sysupgrade" >/dev/null 2>&1 && return 0
    [ -e /tmp/sysupgrade ] && return 0
    [ -e /overlay/.sysupgrade ] && return 0
    [ -e /tmp/.failsafe ] && return 0
    [ -f /tmp/sysupgrade.always_force_backup ] && return 0
    ls /tmp/sysupgrade-* >/dev/null 2>&1 && return 0
    return 1
}

check_wan_link() {
    local wan_dev
    wan_dev=$(uci -q get network.wan6.device 2>/dev/null)
    [ -z "$wan_dev" ] && wan_dev="wan.1015"

    local operstate
    operstate=$(cat "/sys/class/net/${wan_dev}/operstate" 2>/dev/null)
    [ "$operstate" = "down" ] && return 1

    if ip -6 addr show dev "$wan_dev" 2>/dev/null | grep -q "inet6 2"; then
        return 0
    fi
    return 1
}

check_ipv4() {
    ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 && return 0
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && return 0
    return 1
}

check_ipv6() {
    ping -c 1 -W 2 2001:4860:4860::8888 >/dev/null 2>&1 && return 0
    ping -c 1 -W 2 2606:4700:4700::1111 >/dev/null 2>&1 && return 0
    return 1
}

check_high_latency() {
    local rtt
    rtt=$(ping -c 1 -W 2 1.1.1.1 2>/dev/null | grep -o 'time=[0-9]*' | cut -d= -f2)
    if [ -n "$rtt" ] && [ "$rtt" -gt 150 ]; then
        return 0
    fi
    return 1
}

get_active_clients() {
    (
        iwinfo phy0-ap0 assoclist 2>/dev/null | grep -E '^[0-9A-Fa-f]' | cut -d' ' -f1
        iwinfo phy1-ap0 assoclist 2>/dev/null | grep -E '^[0-9A-Fa-f]' | cut -d' ' -f1
    ) | tr 'a-z' 'A-Z' | sort -u
}

CURRENT_STATE=""

apply_state_force() {
    local state="$1"
    CURRENT_STATE="$state"

    case "$state" in
        "PERFECT")
            turn_off_all
            set_led "$GREEN_LED" 1
            ;;
        "DEGRADED")
            turn_off_all
            set_led "$RED_LED" 1
            set_led "$GREEN_LED" 1
            ;;
        "V6_ONLY")
            turn_off_all
            set_led "$BLUE_LED" 1
            ;;
        "NO_INTERNET")
            turn_off_all
            set_led "$RED_LED" 1
            ;;
        "WAN_DOWN")
            turn_off_all
            blink_led "$RED_LED" 500
            ;;
    esac
}

apply_state() {
    local new_state="$1"
    [ "$CURRENT_STATE" = "$new_state" ] && return
    apply_state_force "$new_state"
}

# Initial baseline
PREV_CLIENTS=$(get_active_clients)
INTERNET_CHECK_COUNTER=0

while true; do
    if is_upgrading; then
        turn_off_all
        exit 0
    fi

    # Override Check: If a demo or manual color is requested, yield control completely
    if [ -f /tmp/led_override ]; then
        sleep 1
        continue
    fi

    # Permanent Night Mode: 10:00 PM (22:00) to 6:00 AM (06:00)
    CURRENT_HOUR=$(date +%H)
    if [ "$CURRENT_HOUR" -ge 22 ] || [ "$CURRENT_HOUR" -lt 6 ]; then
        turn_off_all
        sleep 3
        continue
    fi

    # 1. Check for client connections/disconnections
    CURRENT_CLIENTS=$(get_active_clients)
    if [ -n "$PREV_CLIENTS" ] && [ -n "$CURRENT_CLIENTS" ]; then
        # Check if new device connected
        for c in $CURRENT_CLIENTS; do
            if ! echo "$PREV_CLIENTS" | grep -q "$c"; then
                # New client connected -> Continuous 3-second Blue blink
                turn_off_all
                blink_led "$BLUE_LED" 250
                sleep 3
                apply_state_force "$CURRENT_STATE"
                break
            fi
        done

        # Check if device disconnected
        for p in $PREV_CLIENTS; do
            if ! echo "$CURRENT_CLIENTS" | grep -q "$p"; then
                # Device disconnected -> Continuous rapid Amber/Yellow blink for 2 seconds
                turn_off_all
                blink_led "$RED_LED" 100
                blink_led "$GREEN_LED" 100
                sleep 2
                apply_state_force "$CURRENT_STATE"
                break
            fi
        done
    fi
    PREV_CLIENTS="$CURRENT_CLIENTS"

    # 2. Internet health check (every 10 seconds)
    if [ "$INTERNET_CHECK_COUNTER" -le 0 ]; then
        INTERNET_CHECK_COUNTER=10

        if ! check_wan_link; then
            apply_state "WAN_DOWN"
        else
            V4_OK=0
            V6_OK=0
            check_ipv4 && V4_OK=1
            check_ipv6 && V6_OK=1

            if [ "$V4_OK" = "1" ] && [ "$V6_OK" = "1" ]; then
                if check_high_latency; then
                    apply_state "DEGRADED"
                else
                    apply_state "PERFECT"
                fi
            elif [ "$V4_OK" = "0" ] && [ "$V6_OK" = "1" ]; then
                apply_state "V6_ONLY"
            elif [ "$V4_OK" = "1" ] && [ "$V6_OK" = "0" ]; then
                apply_state "PERFECT"
            else
                apply_state "NO_INTERNET"
            fi
        fi
    fi

    INTERNET_CHECK_COUNTER=$((INTERNET_CHECK_COUNTER - 1))
    sleep 1
done
