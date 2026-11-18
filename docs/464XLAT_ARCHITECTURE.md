# 🌐 464XLAT Architecture on Jio 5G Standalone (SA)

A technical overview of why 464XLAT is required on Reliance Jio 5G AirFiber networks and how OpenWrt handles packet translation.

---

## 🏗️ Background: Why Jio 5G is IPv6-Only

Reliance Jio's 5G Standalone (SA) core is architected as a pure IPv6 cellular network:
- No native public IPv4 addresses are assigned over the 5G NR bearer to the Outdoor Unit (ODU).
- The IDU router receives a `/64` or `/56` IPv6 prefix delegation via DHCPv6.
- While modern services (Google, YouTube, Netflix, Cloudflare) operate natively over IPv6, many critical platforms (gaming networks like PlayStation Network, Steam peer-to-peer, certain banking APIs, legacy VPNs) remain strictly IPv4.

---

## 🔄 The 464XLAT Solution (RFC 6877)

464XLAT provides double stateless/stateful translation:

```
  [LAN Client: IPv4]
         │ (192.168.1.50)
         ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                 CUSTOMER TRANSLATOR (CLAT)                  │
  │                 Running on OpenWrt Router                   │
  │                                                             │
  │   Translates local IPv4 packet into IPv6 destination:       │
  │   Format: [NAT64 Prefix: 64:ff9b::/96] + [IPv4 in Hex]      │
  │   Example: 1.1.1.1 -> 64:ff9b::0101:0101                    │
  └──────────────────────────────┬──────────────────────────────┘
                                 │ IPv6 Transport across 5G WAN
                                 ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                 PROVIDER TRANSLATOR (PLAT)                  │
  │                 Running in Jio 5G Core Network              │
  │                                                             │
  │   Statelessly decapsulates the IPv6 packet, performs CGNAT, │
  │   and forwards native IPv4 to the global Internet.          │
  └─────────────────────────────────────────────────────────────┘
```

---

## 🎮 Impact on Gaming & NAT Types

Using `clatd` with optimal kernel offload delivers:
- **NAT Type**: Translates to `Type 2 (Moderate)` on PlayStation/Xbox, which supports full online multiplayer and matchmaking.
- **Latency Overhead**: Because CLAT uses hardware-assisted checksum and header recalculation in modern OpenWrt kernels, the latency penalty is negligible (< 0.2 ms).
