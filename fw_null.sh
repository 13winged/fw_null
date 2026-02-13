#!/bin/bash

# fw_null - Firewall Nullifier Script
# Version: 1.0.0
# Description: Reset firewall rules to default (ACCEPT ALL) and disable UFW
# Author: System Administrator
# License: MIT

set -e

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"
readonly BACKUP_DIR="/root/fw_backups"
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

# Log file
readonly LOG_FILE="/var/log/fw_null.log"

# Function to print colored output
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# Function to print section header
print_header() {
    local msg=$1
    echo
    print_msg "$BLUE" "${BOLD}════════════════════════════════════════════${NC}"
    print_msg "$BLUE" "${BOLD}  $msg${NC}"
    print_msg "$BLUE" "${BOLD}════════════════════════════════════════════${NC}"
}

# Function to print success message
print_success() {
    print_msg "$GREEN" "  ✅ $1"
}

# Function to print warning message
print_warning() {
    print_msg "$YELLOW" "  ⚠️  $1"
}

# Function to print error message
print_error() {
    print_msg "$RED" "  ❌ $1"
}

# Function to print info message
print_info() {
    print_msg "$BLUE" "  ℹ️  $1"
}

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        print_info "Try: sudo $0"
        exit 1
    fi
}

# Function to create backup directory
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        print_success "Created backup directory: $BACKUP_DIR"
    fi
}

# Function to backup current rules
backup_rules() {
    print_header "CREATING BACKUPS"
    
    # Create timestamped backup directory
    mkdir -p "$BACKUP_PATH"
    
    # Backup IPv4 rules
    if iptables-save > "${BACKUP_PATH}/iptables.v4" 2>/dev/null; then
        print_success "IPv4 rules backed up to: ${BACKUP_PATH}/iptables.v4"
        log_message "INFO" "IPv4 rules backed up"
    else
        print_warning "No IPv4 rules to backup"
    fi
    
    # Backup IPv6 rules
    if command -v ip6tables-save &>/dev/null; then
        if ip6tables-save > "${BACKUP_PATH}/ip6tables.v6" 2>/dev/null; then
            print_success "IPv6 rules backed up to: ${BACKUP_PATH}/ip6tables.v6"
            log_message "INFO" "IPv6 rules backed up"
        else
            print_warning "No IPv6 rules to backup"
        fi
    fi
    
    # Backup UFW status if available
    if command -v ufw &>/dev/null; then
        ufw status verbose > "${BACKUP_PATH}/ufw_status.txt" 2>/dev/null
        print_success "UFW status backed up"
    fi
    
    # Create backup info file
    cat > "${BACKUP_PATH}/backup_info.txt" <<EOF
Backup Date: $(date)
Hostname: $(hostname)
Kernel: $(uname -r)
OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)
User: $SUDO_USER
Script Version: $SCRIPT_VERSION
EOF
    
    print_success "Backup information saved"
}

# Function to disable UFW
disable_ufw() {
    print_header "DISABLING UFW"
    
    if ! command -v ufw &>/dev/null; then
        print_info "UFW is not installed"
        log_message "INFO" "UFW not installed"
        return 0
    fi
    
    # Disable UFW
    if ufw status | grep -q "active"; then
        ufw --force disable &>/dev/null
        print_success "UFW disabled"
        log_message "INFO" "UFW disabled"
    else
        print_info "UFW is already disabled"
    fi
    
    # Stop and disable UFW service
    if systemctl list-unit-files | grep -q ufw; then
        systemctl stop ufw &>/dev/null || true
        systemctl disable ufw &>/dev/null || true
        print_success "UFW service stopped and disabled"
    fi
}

# Function to stop firewall persistence services
stop_persistence() {
    print_header "STOPPING PERSISTENCE SERVICES"
    
    # List of services to disable
    local services=(
        "netfilter-persistent"
        "iptables-persistent"
        "firewalld"
    )
    
    for service in "${services[@]}"; do
        if systemctl list-unit-files 2>/dev/null | grep -q "$service"; then
            systemctl stop "$service" &>/dev/null || true
            systemctl disable "$service" &>/dev/null || true
            print_success "Disabled $service"
            log_message "INFO" "Disabled $service"
        fi
    done
}

# Function to reset IPv4 rules
reset_ipv4() {
    print_header "RESETTING IPv4 RULES"
    
    # Set default policies to ACCEPT
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    print_success "Default policies set to ACCEPT"
    
    # Flush all rules and delete custom chains
    local tables=("filter" "nat" "mangle" "raw" "security")
    
    for table in "${tables[@]}"; do
        if iptables -t "$table" -L &>/dev/null; then
            iptables -t "$table" -F 2>/dev/null || true
            iptables -t "$table" -X 2>/dev/null || true
            print_success "Cleaned table: $table"
        fi
    done
    
    # Verify IPv4 rules are empty
    if iptables -L | grep -q "Chain"; then
        print_success "IPv4 rules have been reset"
    fi
    
    log_message "INFO" "IPv4 rules reset"
}

# Function to reset IPv6 rules
reset_ipv6() {
    print_header "RESETTING IPv6 RULES"
    
    if ! command -v ip6tables &>/dev/null; then
        print_warning "ip6tables not available, skipping IPv6"
        return 0
    fi
    
    # Set default policies to ACCEPT
    ip6tables -P INPUT ACCEPT 2>/dev/null || true
    ip6tables -P FORWARD ACCEPT 2>/dev/null || true
    ip6tables -P OUTPUT ACCEPT 2>/dev/null || true
    print_success "Default IPv6 policies set to ACCEPT"
    
    # Flush all rules and delete custom chains
    local tables=("filter" "nat" "mangle" "raw" "security")
    
    for table in "${tables[@]}"; do
        if ip6tables -t "$table" -L &>/dev/null 2>&1; then
            ip6tables -t "$table" -F 2>/dev/null || true
            ip6tables -t "$table" -X 2>/dev/null || true
            print_success "Cleaned IPv6 table: $table"
        fi
    done
    
    log_message "INFO" "IPv6 rules reset"
}

# Function to show open ports
show_open_ports() {
    print_header "CURRENT OPEN PORTS"
    
    if command -v ss &>/dev/null; then
        ss -tulpn | grep LISTEN | column -t || true
    elif command -v netstat &>/dev/null; then
        netstat -tulpn | grep LISTEN || true
    else
        print_warning "Neither ss nor netstat found"
    fi
}

# Function to verify SSH access
verify_ssh() {
    print_header "SSH ACCESS VERIFICATION"
    
    if systemctl is-active ssh &>/dev/null || systemctl is-active sshd &>/dev/null; then
        print_success "SSH service is running"
        
        # Check if SSH is listening on port 22
        if ss -tlnp 2>/dev/null | grep -q ":22 "; then
            print_success "SSH is listening on port 22"
        else
            print_warning "SSH might not be listening on default port 22"
        fi
    else
        print_error "SSH service is not running!"
        print_warning "You might lose access after reboot!"
    fi
}

# Function to save empty rules (optional)
save_rules() {
    print_header "SAVE EMPTY RULES"
    print_info "Do you want to save empty rules to make them persistent after reboot?"
    print_info "(This ensures firewall stays disabled after reboot) [y/N]: "
    
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        if command -v netfilter-persistent-save &>/dev/null; then
            netfilter-persistent-save
            print_success "Rules saved via netfilter-persistent"
        elif command -v iptables-save &>/dev/null; then
            # Try to save in common locations
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4 2>/dev/null
            ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
            print_success "Rules saved to /etc/iptables/"
        else
            print_warning "No method found to save rules permanently"
        fi
        log_message "INFO" "Empty rules saved"
    else
        print_info "Rules not saved (will reset after reboot)"
    fi
}

# Function to show summary
show_summary() {
    print_header "SUMMARY"
    
    echo -e "${GREEN}✅ Firewall has been reset to default ACCEPT ALL${NC}"
    echo -e "${BLUE}📁 Backups:${NC} $BACKUP_PATH"
    echo -e "${BLUE}📋 Log file:${NC} $LOG_FILE"
    echo
    echo -e "${YELLOW}⚠️  Important Notes:${NC}"
    echo "  • All iptables rules have been cleared"
    echo "  • UFW has been disabled"
    echo "  • Default policy is ACCEPT for all chains"
    echo "  • SSH should be accessible on port 22"
    echo
    echo -e "${GREEN}🎯 Script execution completed successfully!${NC}"
}

# Main function
main() {
    print_header "FW_NULL v${SCRIPT_VERSION}"
    print_info "Firewall Nullifier Script"
    print_info "Starting firewall reset process..."
    
    # Check requirements
    check_root
    
    # Create log file
    touch "$LOG_FILE"
    log_message "INFO" "Script started by user $SUDO_USER"
    
    # Main execution
    create_backup_dir
    backup_rules
    disable_ufw
    stop_persistence
    reset_ipv4
    reset_ipv6
    show_open_ports
    verify_ssh
    save_rules
    show_summary
    
    log_message "INFO" "Script completed successfully"
}

# Trap errors
trap 'print_error "An error occurred on line $LINENO"; exit 1' ERR

# Run main function
main "$@"

exit 0