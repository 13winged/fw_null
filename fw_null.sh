#!/bin/bash
set -euo pipefail

# fw_null - One-Click Firewall Nullifier Script
# Version: 2.0.0
# Description: Automatically resets firewall rules to default (ACCEPT ALL) and disables UFW
# Author: System Administrator
# License: MIT

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.0.0"

# Configuration defaults
DEFAULT_BACKUP_DIR="/root/fw_backups"
DEFAULT_LOG_FILE="/var/log/fw_null.log"
readonly TMP_DIR="/tmp/fw_null_$$"

# Trap to clean up temporary files
trap 'rm -rf "$TMP_DIR" 2>/dev/null' EXIT

# Function to write to log file (single logging path for all print_* helpers)
log_message() {
    local level=$1
    local msg=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $msg" >> "${LOG_FILE:-$DEFAULT_LOG_FILE}" 2>/dev/null || true
}

# Function to print colored output
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# Function to print section header
print_header() {
    local msg=$1
    echo -e "\n${BOLD}${BLUE}=== $msg ===${NC}"
}

# Function to print error message
print_error() {
    local msg=$1
    echo -e "${RED}ERROR: ${msg}${NC}"
    log_message "ERROR" "$msg"
}

# Function to print success message
print_success() {
    local msg=$1
    echo -e "${GREEN}SUCCESS: ${msg}${NC}"
    log_message "SUCCESS" "$msg"
}

# Function to print warning message
print_warning() {
    local msg=$1
    echo -e "${YELLOW}WARNING: ${msg}${NC}"
    log_message "WARNING" "$msg"
}

# Function to print info message
print_info() {
    local msg=$1
    echo -e "${BLUE}INFO: ${msg}${NC}"
    log_message "INFO" "$msg"
}

# Default runtime values (overridable via CLI)
BACKUP_DIR="$DEFAULT_BACKUP_DIR"
LOG_FILE="$DEFAULT_LOG_FILE"
FORCE=false
DRY_RUN=false
SAVE_EMPTY=false

# Usage text
usage() {
    cat <<USAGE
$SCRIPT_NAME v$SCRIPT_VERSION - emergency firewall reset (iptables/UFW/nftables -> ACCEPT ALL)

Usage: sudo ./$SCRIPT_NAME [OPTIONS]

Options:
  -b, --backup-dir DIR   backup directory (default: $DEFAULT_BACKUP_DIR)
  -l, --log-file FILE    log file (default: $DEFAULT_LOG_FILE)
  -y, --force, --yes     skip confirmation prompt (required in non-interactive mode)
      --dry-run          print what would be done and exit
      --save-empty       persist empty rules via netfilter-persistent (if available)
  -h, --help             show this help and exit

Without --force the script asks for confirmation. In non-interactive mode
(no TTY) --force is mandatory. Backups are always created before any change.
USAGE
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--backup-dir) BACKUP_DIR="${2:?missing value for $1}"; shift 2;;
            -l|--log-file) LOG_FILE="${2:?missing value for $1}"; shift 2;;
            -y|--force|--yes) FORCE=true; shift;;
            --dry-run) DRY_RUN=true; shift;;
            --save-empty) SAVE_EMPTY=true; shift;;
            -h|--help) usage; exit 0;;
            *) print_error "Unknown option: $1"; usage; exit 1;;
        esac
    done
}

# Function to validate directories
validate_directories() {
    # Create backup directory with proper permissions
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR" || { print_error "Failed to create backup directory"; exit 1; }
        chown root:root "$BACKUP_DIR" || { print_error "Failed to set proper ownership for backup directory"; exit 1; }
    fi

    # Create log directory if needed
    local log_dir="${LOG_FILE%/*}"
    if [[ "$log_dir" != /* ]] || [[ ! -d "$log_dir" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")" || { print_error "Failed to create log directory"; exit 1; }
        chown root:root "$(dirname "$LOG_FILE")" || { print_error "Failed to set proper ownership for log directory"; exit 1; }
    fi

    # Check log file permissions
    if ! touch "$LOG_FILE" 2>/dev/null || ! chmod 600 "$LOG_FILE" 2>/dev/null; then
        print_error "No write access to log file"
        exit 1
    fi
}

# Function to check root access
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        print_info "Try: sudo $0"
        exit 1
    fi
}

# Function to check system services
check_system_services() {
    print_header "Checking firewall management tools"
    
    # Check for nftables
    if command -v nft &>/dev/null; then
        print_warning "nftables is active. This script will reset nftables."
        if nft list ruleset 2>/dev/null | grep -q "table"; then
            print_info "nftables ruleset is present and active."
        fi
    fi
    
    # Check for firewalld
    if command -v systemctl &>/dev/null && systemctl is-active --quiet firewalld; then
        print_warning "firewalld is active. This script will focus on iptables/ufw, but nftables may conflict."
    fi
}

# Backup functions
backup_rules() {
    local backup_date
    
    # Create timestamped backup directory
    backup_date=$(date +%Y-%m-%d_%H-%M-%S)
    BACKUP_DIR="$BACKUP_DIR/${SCRIPT_NAME%.sh}_${backup_date}"
    mkdir -p "$BACKUP_DIR" || { print_error "Failed to create backup directory"; exit 1; }
    
    export BACKUP_PATH="$BACKUP_DIR"

    # Backup IPv4 rules
    if command -v iptables &>/dev/null; then
        if iptables-save > "${BACKUP_PATH}/iptables.v4" 2>/dev/null; then
            print_success "IPv4 rules backed up"
            log_message "ACTION" "IPv4 rules backed up"
        else
            print_error "Failed to backup IPv4 rules"
        fi
    else
        print_info "iptables not available, skipping IPv4 backup"
    fi

    # Backup IPv6 rules
    if command -v ip6tables &>/dev/null; then
        if ip6tables-save > "${BACKUP_PATH}/iptables.v6" 2>/dev/null; then
            print_success "IPv6 rules backed up"
            log_message "ACTION" "IPv6 rules backed up"
        else
            print_error "Failed to backup IPv6 rules"
        fi
    else
        print_info "ip6tables not available, skipping IPv6 backup"
    fi

    # Backup nftables rules if available
    if command -v nft &>/dev/null; then
        if nft list ruleset > "${BACKUP_PATH}/nftables.rules" 2>/dev/null; then
            print_success "nftables rules backed up"
            log_message "ACTION" "nftables rules backed up"
        else
            print_error "Failed to backup nftables rules"
        fi
    else
        print_info "nftables not available, skipping backup"
    fi

    # Backup UFW status if available
    if command -v ufw &>/dev/null; then
        if ufw status verbose > "${BACKUP_PATH}/ufw_status.txt" 2>/dev/null; then
            print_success "UFW status backed up"
            log_message "ACTION" "UFW status backed up"
        else
            print_error "Failed to backup UFW status"
        fi
    else
        print_info "UFW not available, skipping status backup"
    fi

    # Create backup info file
    cat > "${BACKUP_PATH}/backup_info.txt" <<EOF
Backup Date: $(date)
Hostname: $(hostname)
Kernel: $(uname -r)
OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")
User: ${SUDO_USER:-$(whoami)}
Script Version: $SCRIPT_VERSION
EOF

    print_success "Backup information saved"
}

# Function to disable UFW
disable_ufw() {
    if command -v ufw &>/dev/null; then
        print_header "Disabling UFW"
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            ufw disable 2>/dev/null || { print_error "Failed to disable UFW"; return 1; }
            log_message "ACTION" "UFW disabled"
        else
            print_info "UFW is not active"
        fi
        if command -v systemctl &>/dev/null; then
            systemctl disable ufw >/dev/null 2>&1 || true
        fi
    else
        print_info "UFW not found, skipping"
    fi
}

# Function to stop persistence services (firewall-related only)
stop_persistence() {
    print_header "Stopping persistence services"

    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet netfilter-persistent; then
            systemctl stop netfilter-persistent.service || { print_error "Failed to stop netfilter-persistent"; return 1; }
            systemctl disable netfilter-persistent.service >/dev/null 2>&1 || true
            log_message "ACTION" "netfilter-persistent stopped and disabled"
        else
            print_info "netfilter-persistent not active"
        fi

        if systemctl is-active --quiet firewalld; then
            systemctl stop firewalld.service || { print_error "Failed to stop firewalld"; return 1; }
            systemctl disable firewalld.service >/dev/null 2>&1 || true
            log_message "ACTION" "firewalld stopped and disabled"
        else
            print_info "firewalld not active"
        fi
    else
        print_info "systemctl not available, skipping service checks"
    fi
}

# Flush all chains and delete user-defined chains for one iptables variant
# Args: iptables|ip6tables ; returns 0 on success
flush_all_tables() {
    local ipt=$1
    local t
    for t in filter nat mangle raw security; do
        # Some tables (e.g. nat on old kernels for IPv6) may not exist - never fatal
        $ipt -t "$t" -F >/dev/null 2>&1 || true
        $ipt -t "$t" -X >/dev/null 2>&1 || true
    done
}

# Function to reset firewall rules
reset_firewall_rules() {
    print_header "Resetting firewall rules"

    # Check for iptables
    if command -v iptables &>/dev/null; then
        # Policies FIRST: with a DROP policy, flushing alone keeps you locked out
        iptables -P INPUT ACCEPT 2>/dev/null || { print_error "Failed to set iptables INPUT policy"; return 1; }
        iptables -P FORWARD ACCEPT 2>/dev/null || { print_error "Failed to set iptables FORWARD policy"; return 1; }
        iptables -P OUTPUT ACCEPT 2>/dev/null || { print_error "Failed to set iptables OUTPUT policy"; return 1; }

        flush_all_tables iptables

        log_message "ACTION" "iptables policies set to ACCEPT, all tables flushed"
        print_success "iptables rules reset to default (ACCEPT ALL)"
    else
        print_info "iptables not available, skipping reset"
    fi

    # Check for ip6tables
    if command -v ip6tables &>/dev/null; then
        ip6tables -P INPUT ACCEPT 2>/dev/null || { print_error "Failed to set ip6tables INPUT policy"; return 1; }
        ip6tables -P FORWARD ACCEPT 2>/dev/null || { print_error "Failed to set ip6tables FORWARD policy"; return 1; }
        ip6tables -P OUTPUT ACCEPT 2>/dev/null || { print_error "Failed to set ip6tables OUTPUT policy"; return 1; }

        flush_all_tables ip6tables

        log_message "ACTION" "ip6tables policies set to ACCEPT, all tables flushed"
        print_success "ip6tables rules reset to default (ACCEPT ALL)"
    else
        print_info "ip6tables not available, skipping reset"
    fi

    # Check for nftables
    if command -v nft &>/dev/null; then
        print_header "Resetting nftables rules"
        nft flush ruleset 2>/dev/null || { print_error "Failed to reset nftables rules"; return 1; }
        log_message "ACTION" "nftables rules reset to default"
        print_success "nftables rules reset to default"
    else
        print_info "nftables not available, skipping reset"
    fi

    # Docker recreates its chains on restart; without it containers stay offline
    if command -v systemctl &>/dev/null && command -v docker &>/dev/null && systemctl is-active --quiet docker; then
        systemctl restart docker >/dev/null 2>&1 || print_warning "Docker restart failed, container networking may need manual restart"
        log_message "ACTION" "docker restarted to restore its chains"
    fi
}

# Function to show open ports
show_open_ports() {
    print_header "Showing open ports"

    # Local listeners first: fast and always relevant
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null || { print_error "ss failed to list ports"; return 1; }
    elif command -v netstat &>/dev/null; then
        netstat -tulnp 2>/dev/null || { print_error "netstat failed to list ports"; return 1; }
    elif command -v nmap &>/dev/null; then
        nmap -F 127.0.0.1 2>/dev/null || { print_error "nmap scan failed"; return 1; }
    else
        print_info "No port listing tool available (ss/netstat/nmap)"
    fi

    log_message "INFO" "Open ports shown"
}

# Function to verify SSH is reachable after reset
check_ssh() {
    print_header "Verifying SSH accessibility"

    local ssh_ok=false
    if command -v ss &>/dev/null && ss -tln 2>/dev/null | grep -qE ':(22|2222)\s'; then
        ssh_ok=true
    fi
    if command -v systemctl &>/dev/null && (systemctl is-active --quiet sshd || systemctl is-active --quiet ssh); then
        ssh_ok=true
    fi

    if [[ "$ssh_ok" == true ]]; then
        print_success "SSH appears to be listening and running"
        log_message "ACTION" "SSH check passed"
    else
        print_warning "SSH does not look active (no listener on :22 and no sshd service). Start it manually if needed."
        log_message "WARNING" "SSH check did not confirm sshd"
    fi
}

# Function to save configuration
save_configuration() {
    print_header "Saving configuration"
    
    if [[ -f "$LOG_FILE" ]]; then
        chown root:root "$LOG_FILE" || { print_error "Failed to set proper ownership for log file"; return 1; }
        print_info "Log file saved: $LOG_FILE"
    else
        print_error "No log file to save"
    fi
    
    if [[ -d "$BACKUP_DIR" ]]; then
        chown root:root "$BACKUP_DIR" || { print_error "Failed to set proper ownership for backup directory"; return 1; }
        print_info "Backup directory saved: $BACKUP_DIR"
    else
        print_error "No backup directory"
    fi
    
    log_message "INFO" "Configuration saved"
}

# Function to persist the (now empty) ruleset across reboots
save_empty_rules() {
    print_header "Saving empty ruleset"
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save 2>/dev/null || { print_error "Failed to save rules via netfilter-persistent"; return 1; }
        log_message "ACTION" "Empty rules saved via netfilter-persistent"
        print_success "Empty rules will survive reboot"
    else
        print_warning "netfilter-persistent not installed, empty rules NOT saved (reboot restores old saved rules)."
        print_info "Install it to persist: apt-get install -y iptables-persistent"
    fi
}

# Main function
main() {
    parse_args "$@"
    check_root

    if [[ "$DRY_RUN" == true ]]; then
        print_header "DRY RUN - no changes will be made"
        print_info "Backup dir : $BACKUP_DIR"
        print_info "Log file   : $LOG_FILE"
        print_info "Plan       : backup rules -> disable UFW -> stop netfilter-persistent/firewalld ->"
        print_info "             set ACCEPT policies -> flush filter,nat,mangle,raw,security (v4+v6) ->"
        print_info "             flush nftables -> restart docker (if active) -> show ports -> check SSH"
        exit 0
    fi

    if [[ "$FORCE" != true ]]; then
        if [[ -t 0 ]]; then
            print_warning "This will WIPE ALL firewall rules and DISABLE the firewall (ACCEPT ALL)."
            read -rp "Continue? [y/N] " answer
            [[ "$answer" =~ ^[Yy]$ ]] || { print_info "Aborted by user."; exit 0; }
        else
            print_error "Refusing to run without --force in non-interactive mode."
            exit 1
        fi
    fi

    validate_directories
    check_system_services

    # Create temporary directory
    mkdir -p "$TMP_DIR" || { print_error "Failed to create temporary directory"; exit 1; }

    # Initialize log file
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
        print_info "Log file created: $LOG_FILE"
    fi

    # Backup current rules
    backup_rules

    # Disable UFW if present
    disable_ufw

    # Stop persistence services
    stop_persistence

    # Reset firewall rules
    reset_firewall_rules

    # Optionally persist the empty ruleset
    if [[ "$SAVE_EMPTY" == true ]]; then
        save_empty_rules
    fi

    # Show open ports
    show_open_ports

    # Verify SSH is still reachable
    check_ssh

    # Save configuration
    save_configuration

    print_success "Firewall reset completed successfully"
    echo -e "${BOLD}${BLUE}--- SUMMARY ---${NC}"
    print_info "Backup directory: $BACKUP_DIR"
    print_info "Log file: $LOG_FILE"
    if [[ "$SAVE_EMPTY" != true ]]; then
        print_warning "Empty rules were NOT persisted: a reboot may restore previously saved rules."
    fi
}

# Execute main function
main "$@"