# 📐 Hardware Reference: Jio AirFiber Indoor Unit (JIDU6401)

Technical hardware documentation for the MediaTek Filogic 830 (MT7986) based Jio AirFiber router.

---

## 🛠️ System Specifications

- **Device Series**: JioRouter AX6000 (Sercomm JIDU6401 / JIDU6201 / JIDU6601 / JIDU6701)
- **SoC**: MediaTek Filogic 830 (`MT7986A` / `MT7986B`)
- **CPU**: Quad-core ARM Cortex-A53 @ 2.0 GHz (64-bit `aarch64`)
- **System Memory**: 512 MB or 1 GB DDR4 RAM
- **Flash Storage**: 128 MB or 256 MB SPI-NAND Flash
- **Wi-Fi Chipset**: MediaTek MT7975N (2.4GHz 4x4) + MT7975P (5GHz 4x4)
- **Wi-Fi Standards**: Wi-Fi 6 (802.11ax), HE80/HE160 channel bandwidth, 4096-QAM / 1024-QAM, OFDMA, MU-MIMO
- **Ethernet Interfaces**:
  - `eth1` / `wan`: 2.5 Gigabit Ethernet (2.5GbE) PoE Port (connects to Outdoor 5G Unit)
  - `eth0` / `lan`: 1 Gigabit Ethernet LAN Switch (Gigabit LAN Ports 1, 2, 3)
- **Target OpenWrt Profile**: `mediatek/filogic` (Subtarget `filogic`)

---

## 🎖️ Upstream OpenWrt Community Credits

Initial upstream board support for the MediaTek MT7986 JioRouter series was contributed by **Sheikh Faisal ([@sh3ikh-faisal](https://github.com/sh3ikh-faisal))** in OpenWrt PR **#23510**, merged into master commit `0a2eb2d` (*"mediatek: add support for JioRouter AX6000 series"*).

---

## 🔌 UART Serial Pinout (3.3V TTL)

To access the U-Boot serial console on the JIDU6401 PCB:
- **Baud Rate**: `115200`
- **Data Bits**: `8`
- **Parity**: `None`
- **Stop Bits**: `1`
- **Flow Control**: `None`

The 4-pin UART header is located near the MediaTek SoC heatsink:
1. **Pin 1**: `VCC 3.3V` (Do NOT connect to USB-UART adapter!)
2. **Pin 2**: `TX` (Connect to RX on USB-UART adapter)
3. **Pin 3**: `RX` (Connect to TX on USB-UART adapter)
4. **Pin 4**: `GND` (Connect to GND on USB-UART adapter)

---

## 💡 Tri-Color Status LED sysfs Mapping

The front multi-color indicator on the JIDU6401 is mapped to three sysfs LED channels:
- `/sys/class/leds/red:status`
- `/sys/class/leds/green:status`
- `/sys/class/leds/blue:status`

Our provided `scripts/wan-led-monitor.sh` dynamically drives these LEDs based on the active connection state:
- 🟢 **Solid Green**: Dual-stack online (464XLAT IPv4 + native IPv6 active).
- 🔵 **Solid Blue**: Native IPv6 connected, CLAT translation pending.
- 🔴 **Solid Red**: No WAN link or upstream default route.

---

## 🔒 SSH Management Port Note

On many customized OpenWrt builds (including Dave's Guitar snapshot), Dropbear SSH is configured to listen on **Port 2222** rather than default Port 22 to prevent brute-force attacks from WAN:
```bash
ssh -p 2222 root@192.168.1.1
```

---

## 💾 MTD Partition Layout (SPI-NAND)

| Partition Name | Typical Size | Purpose |
| :--- | :--- | :--- |
| `bl2` | 1 MB | MediaTek BootROM Second Stage Bootloader |
| `fip` / `u-boot` | 2 MB | TF-A (BL31) and U-Boot binary |
| `factory` / `mfg` | 2 MB | Wi-Fi EEPROM calibration & MAC addresses |
| `ubi` / `firmware` | Remainder (~120 MB) | Linux kernel (`fitImage`) and rootfs (SquashFS / UBIFS) |

> [!IMPORTANT]
> Always dump the `factory` / `mfg` partition before modifying flash memory. The Wi-Fi radio calibration data is unique to each unit.
