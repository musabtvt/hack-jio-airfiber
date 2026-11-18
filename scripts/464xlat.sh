#!/bin/sh
# ==============================================================================
# OpenWrt netifd 464xlat Protocol Handler
# Production-tested on MediaTek Filogic 830 (MT7986 / JIDU6401)
# Manages /sbin/464xlatcfg, kernel nat46 control, and table 128 routing
# ==============================================================================

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /lib/functions/network.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_464xlat_setup() {
	local cfg="$1"
	local iface="$2"
	local link="464-$cfg"

	local ip6addr ip6prefix tunlink zone
	json_get_vars ip6addr ip6prefix tunlink zone

	[ "$zone" = "-" ] && zone=""

	( proto_add_host_dependency "$cfg" "::" "$tunlink" )

	if [ -z "$tunlink" ] && ! network_find_wan6 tunlink; then
		proto_notify_error "$cfg" "NO_WAN_LINK"
		return
	fi
	network_get_device tundev "$tunlink"

	[ -z "$ip6prefix" ] && ip6prefix="64:ff9b::/96"

	# Execute 464xlatcfg binary to configure Linux kernel nat46 translator
	ip6addr=$(464xlatcfg "$link" "$tundev" "$ip6prefix" 192.0.0.1)
	if [ -z "$ip6addr" ]; then
		proto_notify_error "$cfg" "CLAT_CONFIG_FAILED"
		return
	fi

	# Configure IPv6 routing policies and anycast address
	ip -6 rule del from all lookup local 2>/dev/null
	ip -6 rule add from all lookup local pref 1 2>/dev/null
	ip -6 rule add to "$ip6addr" lookup prelocal pref 0 2>/dev/null
	echo "$ip6addr" > "/tmp/464-$cfg-anycast"

	# Ensure device has valid MTU and IPv6 link-local address so kernel accepts table 128 route
	ip link set dev "$link" mtu 1500 2>/dev/null
	ip link set dev "$link" up 2>/dev/null
	ip -6 addr add fe80::1/64 dev "$link" 2>/dev/null
	ip -6 route replace "$ip6addr/128" dev "$link" table 128 2>/dev/null

	proto_init_update "$link" 1
	proto_add_ipv4_route "0.0.0.0" 0 "" "" 2048
	proto_add_ipv6_route "$ip6addr" 128 "" "" "" "" 128

	proto_add_data
	[ -n "$zone" ] && json_add_string zone "$zone"

	json_add_array firewall
		[ -z "$zone" ] && zone="wan"

		json_add_object ""
			json_add_string type nat
			json_add_string target SNAT
			json_add_string family inet
			json_add_string snat_ip 192.0.0.1
		json_close_object
		[ -n "$zone" ] && {
			json_add_object ""
				json_add_string type rule
				json_add_string family inet6
				json_add_string proto all
				json_add_string direction in
				json_add_string dest "$zone"
				json_add_string src "$zone"
				json_add_string src_ip "$ip6addr"
				json_add_string target ACCEPT
			json_close_object
		}
	json_close_array
	proto_close_data

	proto_send_update "$cfg"
}

proto_464xlat_teardown() {
	local cfg="$1"
	local link="464-$cfg"

	[ -f "/tmp/464-$cfg-anycast" ] || return
	local ip6addr
	ip6addr=$(cat "/tmp/464-$cfg-anycast")

	# Teardown kernel nat46 tunnel
	464xlatcfg "$link"

	rm -f "/tmp/464-$cfg-anycast"
	if [ -n "$ip6addr" ]; then
		ip -6 rule del to "$ip6addr" lookup prelocal 2>/dev/null
		ip -6 route del "$ip6addr/128" dev "$link" table 128 2>/dev/null
	fi

	if [ -z "$(ls /tmp/464-*-anycast 2>/dev/null)" ]; then
		ip -6 rule del from all lookup local 2>/dev/null
		ip -6 rule add from all lookup local pref 0 2>/dev/null
	fi

	# Kill conntracks SNATed to 192.0.0.1
	echo 192.0.0.1 > /proc/net/nf_conntrack 2>/dev/null || true
}

proto_464xlat_init_config() {
	no_device=1
	available=1

	proto_config_add_string "ip6prefix"
	proto_config_add_string "ip6addr"
	proto_config_add_string "tunlink"
	proto_config_add_string "zone"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol 464xlat
}
