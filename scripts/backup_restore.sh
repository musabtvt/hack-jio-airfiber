#!/bin/sh
# ==============================================================================
# Jio AirFiber 5G OpenWrt - Safety Backup & Instant Rollback Utility
# ==============================================================================

BACKUP_DIR="/etc/jio-5g/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

usage() {
    echo "Usage: $0 [--backup | --restore [FILE] | --list]"
    echo "  --backup         Create a snapshot of current network, firewall, and wireless configs"
    echo "  --restore [FILE] Restore configurations from latest snapshot or specified tar.gz"
    echo "  --list           List all existing backup snapshots"
    exit 1
}

case "$1" in
    --backup)
        mkdir -p "$BACKUP_DIR"
        TARGET="$BACKUP_DIR/backup_${TIMESTAMP}.tar.gz"
        echo "[*] Creating backup at $TARGET..."
        tar -czf "$TARGET" /etc/config/network /etc/config/firewall /etc/config/wireless 2>/dev/null
        echo "[SUCCESS] Configuration backed up to $TARGET"
        ;;

    --restore)
        if [ -n "$2" ] && [ -f "$2" ]; then
            TARGET="$2"
        else
            TARGET=$(ls -t "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null | head -n 1)
        fi

        if [ -z "$TARGET" ] || [ ! -f "$TARGET" ]; then
            echo "[-] Error: No backup archive found in $BACKUP_DIR."
            exit 1
        fi

        echo "[*] Restoring configurations from $TARGET..."
        tar -xzf "$TARGET" -C /
        echo "[*] Reloading network, firewall, and wireless..."
        /etc/init.d/network reload
        /etc/init.d/firewall reload
        command -v wifi >/dev/null 2>&1 && wifi reload 2>/dev/null || true
        echo "[SUCCESS] System restored to previous state."
        ;;

    --list)
        echo "Available snapshots in $BACKUP_DIR:"
        ls -lh "$BACKUP_DIR"/backup_*.tar.gz 2>/dev/null || echo "No backups found."
        ;;

    *)
        usage
        ;;
esac
