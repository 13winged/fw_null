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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $msg" >> "${DEFAULT_LOG_FILE}" 2>/dev/null
}

# Function to print success message
print_success() {
    local msg=$1
    echo -e "${GREEN}SUCCESS: ${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $msg" >> "${DEFAULT_LOG_FILE}" 2>/dev/null
}

# Function to print warning message
print_warning() {
    local msg=$1
    echo -e "${YELLOW}WARNING: ${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $msg" >> "${DEFAULT_LOG_FILE}" 2>/dev/null
}

# Function to print info message
print_info() {
    local msg=$1
    echo -e "${BLUE}INFO: ${msg}${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $msg" >> "${DEFAULT_LOG_FILE}" 2>/dev/null
}

# Function to parse command line arguments
parse_args() {
    while getopts ":b:l:" opt; do
        case "$opt" in
            b) BACKUP_DIR="${OPTARG:-$DEFAULT_BACKUP_DIR}";;
            l) LOG_FILE="${OPTARG:-$DEFAULT_LOG_FILE}";;
            \?) print_error "Invalid option: -$OPTARG"; exit 1;;
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
    }
}

# Function to check system services
check_system_services() {
    # Check for nftables
    if command -v nft &>/dev/null; then
        print_header "Checking nftables"
        if nft list ruleset 2>/dev/null | grep -q "table"; then
            print_warning "nftables is active. Consider disabling it for consistency."
        fi
    fi

    # Check for firewalld
    if command -v systemctl &>/dev/null && systemctl is-active --quiet firewalld; then
        print_header "Checking firewalld"
        print_warning "firewalld is active. This script focuses on iptables/ufw."
    fi
}

# Backup functions
backup_rules() {
    local backup_date
    
    # Create timestamped backup directory
    backup_date=$(date +%Y-%m-%d_%H-%M-%S)
    BACKUP_DIR="$BACKUP_DIR/${SCRIPT_NAME}_${backup_date}"
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

    # Create backup info file
    cat > "${BACKUP_PATH}/backup_info.txt" <<EOF
Backup Date: $(date)
Hostname: $(hostname)
Kernel: $(uname -r)
OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo "Unknown")
User: $SUDO_USER
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
    else
        print_info "UFW not found, skipping"
    fi
}

# Function to stop persistence services
stop_persistence() {
    print_header "Stopping persistence services"
    
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet netfilter-persistent; then
            systemctl stop netfilter-persistent.service || { print_error "Failed to stop netfilter-persistent"; return 1; }
            log_message "ACTION" "netfilter-persistent stopped"
        else
            print_info "netfilter-persistent not active"
        fi
        
        if systemctl is-active --quiet systemd-resolved; then
            systemctl stop systemd-resolved.service || { print_error "Failed to stop systemd-resolved"; return 1; }
            log_message "ACTION" "systemd-resolved stopped"
        else
            print_info "systemd-resolved not active"
        fi
    else
        print_info "systemctl not available, skipping service checks"
    fi
}

# Function to reset firewall rules
reset_firewall_rules() {
    print_header "Resetting firewall rules"
    
    # Check for iptables
    if command -v iptables &>/dev/null; then
        # Flush all chains
        iptables -F 2>/dev/null || { print_error "Failed to flush iptables rules"; return 1; }
        iptables -t nat -F 2>/dev/null || { print_error "Failed to flush iptables nat rules"; return 1; }
        iptables -t mangle -F 2>/dev/null || { print_error "Failed to flush iptables mangle rules"; return 1; }
        iptables -t filter -F 2>/dev/null || { print_error "Failed to flush iptables filter rules"; return 1; }
        
        # Delete all user-defined chains
        for chain in $(iptables -S 2>/dev/null | awk '/^-A [^-]/ {print $3}' | uniq); do
            iptables -X "$chain" 2>/dev/null || true
        done
        
        log_message "ACTION" "iptables rules flushed"
        print_success "iptables rules reset to default"
    else
        print_info "iptables not available, skipping reset"
    fi

    # Check for ip6tables
    if command -v ip6tables &>/dev/null; then
        # Flush all chains
        ip6tables -F 2>/dev/null || { print_error "Failed to flush ip6tables rules"; return 1; }
        ip6tables -t nat -F 2>/dev/null || { print_error "Failed to flush ip6tables nat rules"; return 1; }
        ip6tables -t mangle -F 2>/dev/null || { print_error "Failed to flush ip6tables mangle rules"; return 1; }
        ip6tables -t filter -F 2>/dev/null || { print_error "Failed to flush ip6="tables filter rules"; return 1; }
        
        # Delete all user-defined chains
        for chain in $(ip6tables -S 2>/dev/null | awk '/^-A [^-]/ {print $3}' | uniq); do
            ip6tables -X "$chain" 2>/dev/null || true
        done
        
        log_message "ACTION" "ip6tables rules flushed"
        print_success "ip6tables rules reset to default"
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
}

# Function to show open ports
show_open_ports() {
    print_header "Showing open ports"
    
    # List active ports
    if command -v nmap &>/dev/null; then
        nmap -pT -sS -O -T4 -A -v 2>/dev/null || { print_error "nmap not available for port scanning"; return 1; }
    elif command -v ss &>/dev/null; then
        ss -a 2>/dev/null || { print_error "ss not available for port listing"; return 1; }
    elif command -v netstat &>/dev/null; then
        netstat -tulnp 2>/dev/null || { print_error "netstat not available for port listing"; return 1; }
    else
        print_info "No port listing tool available"
    fi
    
    log_message "INFO" "Open ports shown"
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

# Main function
main() {
    parse_args "$@"
    validate_directories
    check_root
    
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
    
    # Show open ports
    show_open_ports
    
    # Save configuration
    save_configuration
    
    print_success "Firewall reset completed successfully"
    print_info "Backup directory: $BACKUP_DIR"
    print_info "Log file: $LOG_FILE"
}

# Execute main function
main "$@"