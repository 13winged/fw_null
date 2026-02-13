# FW_NULL - Firewall Nullifier Script

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/yourusername/firewall-scripts)
[![Bash](https://img.shields.io/badge/bash-4.0%2B-green.svg)](https://www.gnu.org/software/bash/)

## 📋 Description

**FW_NULL** is a bash script designed for emergency reset of firewall settings (iptables/UFW) to default ACCEPT ALL values. Created specifically for situations when an administrator accidentally blocks their own access to the server (for example, closing port 22) and loses SSH connectivity.

The script completely flushes all iptables rules, disables UFW and other firewall management services, restoring access to the server.

## 🎯 Use Cases

- **Emergency access recovery** - if you accidentally blocked SSH (port 22)
- **Reset broken rules** - when firewall configuration is incorrect
- **Server reconfiguration** - need to start from a clean slate
- **Server migration** - moving configurations to new hardware

## ✨ Features

- ✅ **Automatic backups** - all current rules are saved before reset
- ✅ **Complete UFW disable** - service stopped and removed from startup
- ✅ **Persistence services stop** - netfilter-persistent, iptables-persistent, firewalld
- ✅ **IPv4 rules reset** - flushes all tables (filter, nat, mangle, raw, security)
- ✅ **IPv6 rules reset** - if IPv6 is enabled
- ✅ **ACCEPT policies** - INPUT, FORWARD, OUTPUT = ACCEPT
- ✅ **SSH availability check** - verifies SSH is working after reset
- ✅ **Open ports display** - shows which services are accessible
- ✅ **Colored output** - easy navigation through execution steps
- ✅ **Detailed logging** - all actions recorded in `/var/log/fw_null.log`
- ✅ **Optional persistence** - can save empty rules for after reboot

## 🚀 Quick Start

### Installation

```bash
# Clone repository
git clone https://github.com/13winged/fw_null.git
cd fw_null

# Make script executable
chmod +x fw_null

# Run
sudo ./fw_null
```

### Or download directly

```bash
wget https://raw.githubusercontent.com/13winged/fw_null/main/fw_null
chmod +x fw_null
sudo ./fw_null
```

### System-wide installation

```bash
sudo cp fw_null /usr/local/bin/
sudo fw_null
```

## 📖 Usage

### Basic execution

```bash
sudo ./fw_null
```

The script performs the following steps:
1. Checks root privileges
2. Creates backup directory
3. Saves current rules
4. Disables UFW
5. Stops persistence services
6. Resets all IPv4 rules
7. Resets all IPv6 rules
8. Shows open ports
9. Verifies SSH accessibility
10. Asks about saving empty rules

### Example output

```
════════════════════════════════════════════
  FW_NULL v1.0.1
════════════════════════════════════════════
  ℹ️  Firewall Nullifier Script
  ℹ️  Starting firewall reset process...

════════════════════════════════════════════
  CREATING BACKUPS
════════════════════════════════════════════
  ✅ IPv4 rules backed up to: /root/fw_backups/20240213_143022/iptables.v4
  ✅ UFW status backed up
  ✅ Backup information saved

════════════════════════════════════════════
  DISABLING UFW
════════════════════════════════════════════
  ✅ UFW disabled
  ✅ UFW service stopped and disabled

... and so on ...
```

## 🔧 System Requirements

- **OS**: Linux (Ubuntu, Debian, CentOS, RHEL, and others)
- **Privileges**: root or sudo access
- **Bash**: version 4.0 or higher
- **Commands**: iptables, ip6tables (optional)

## 📂 Backup Structure

```
/root/fw_backups/
├── 20260213_143022/
│   ├── iptables.v4
│   ├── ip6tables.v6
│   ├── ufw_status.txt
│   └── backup_info.txt
├── 20260213_152037/
│   └── ...
└── ...
```

## ⚠️ Important Notes

1. **Script must be run with sudo** - won't work without root privileges
2. **Backups are automatic** - you can restore if something goes wrong
3. **All ports are open after reset** - server becomes vulnerable, reconfigure firewall
4. **SSH must be configured** - script checks if SSH is working after reset
5. **Settings aren't auto-saved** - you'll be asked if you want to save empty rules

## 🔄 Restoring from Backup

If you need to restore old rules:

```bash
# List available backups
ls -la /root/fw_backups/

# Restore IPv4 rules
sudo iptables-restore < /root/fw_backups/20240213_143022/iptables.v4

# Restore IPv6 rules
sudo ip6tables-restore < /root/fw_backups/20240213_143022/ip6tables.v6

# Re-enable UFW (if previously used)
sudo ufw enable
```

## 🐛 Troubleshooting

### "Port 22 is still not accessible"
```bash
# Check SSH status
systemctl status sshd

# Check if SSH is listening on port 22
ss -tlnp | grep 22

# Restart SSH
systemctl restart sshd
```

### "Cannot save rules"
```bash
# Install netfilter-persistent
apt-get install iptables-persistent netfilter-persistent
# or
yum install iptables-services

# Save manually
iptables-save > /etc/iptables/rules.v4
```
---

## 🎉 Conclusion

**FW_NULL** is your lifeline when the firewall slams the door in your face. Remember: with great power comes great responsibility. Use this script to recover access, but don't forget to properly configure your server's security afterward!

**Happy firewalling!** 🔥