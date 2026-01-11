#!/bin/bash

# ============================================================
# UBUNTU SERVER AUTOMATION SCRIPT
# Features: Interactive Checklist, Idempotency Check, Dynamic Swap
# Language: English
# ============================================================

# 1. Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root (sudo)." 
   exit 1
fi

# 2. Check for 'whiptail' dependency
if ! command -v whiptail &> /dev/null; then
    echo "Whiptail is not installed. Installing..."
    apt-get update && apt-get install whiptail -y
fi

LOG_FILE="/var/log/vps_setup.log"

# --- UTILITY FUNCTIONS ---
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- STATUS CHECK FUNCTIONS (INITIAL DETECTION) ---

check_update() {
    # Check last update timestamp (less than 24 hours is considered ON)
    if [ -f /var/lib/apt/periodic/update-success-stamp ]; then
        if find /var/lib/apt/periodic/update-success-stamp -mtime -1 | grep -q .; then
            echo "ON"; return
        fi
    fi
    echo "OFF"
}

check_user() {
    # Check if a regular user (UID >= 1000) exists
    if awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | grep -q .; then
        echo "ON"
    else
        echo "OFF"
    fi
}

check_ssh() {
    # Check if PasswordAuthentication is set to NO
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
        echo "ON"
    else
        echo "OFF"
    fi
}

check_firewall() {
    # Check UFW status
    if ufw status | grep -q "Status: active"; then
        echo "ON"
    else
        echo "OFF"
    fi
}

check_fail2ban() {
    # Check fail2ban service status
    if systemctl is-active --quiet fail2ban; then
        echo "ON"
    else
        echo "OFF"
    fi
}

check_timezone() {
    # Check if timezone is Asia/Jakarta
    if timedatectl | grep -q "Asia/Jakarta"; then
        echo "ON"
    else
        echo "OFF"
    fi
}

check_swap() {
    # Check if any swap file/partition is active
    if swapon --show --noheadings | grep -q "."; then
        echo "ON"
    else
        echo "OFF"
    fi
}

# --- MAIN EXECUTION FUNCTIONS ---

run_update() {
    log "START: System Update & Upgrade"
    apt-get update && apt-get upgrade -y
    apt-get autoremove -y
    # Create manual stamp if system doesn't create one
    touch /var/lib/apt/periodic/update-success-stamp
    log "END: System Update Completed."
    whiptail --msgbox "System Update Completed." 8 45
}

run_user() {
    NEW_USER=$(whiptail --inputbox "Enter New Username (NOT root):" 8 45 --title "Create User" 3>&1 1>&2 2>&3)
    
    if [ -z "$NEW_USER" ]; then return; fi
    
    if id "$NEW_USER" &>/dev/null; then
        whiptail --msgbox "User $NEW_USER already exists!" 8 45
    else
        adduser --gecos "" "$NEW_USER"
        usermod -aG sudo "$NEW_USER"
        
        # Setup SSH Directory
        mkdir -p /home/$NEW_USER/.ssh
        chmod 700 /home/$NEW_USER/.ssh
        
        # Input SSH Key
        PUB_KEY=$(whiptail --inputbox "Enter SSH Public Key (Paste here):" 15 70 --title "SSH Key Setup" 3>&1 1>&2 2>&3)
        if [ ! -z "$PUB_KEY" ]; then
            echo "$PUB_KEY" >> /home/$NEW_USER/.ssh/authorized_keys
            chmod 600 /home/$NEW_USER/.ssh/authorized_keys
            chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
            log "SSH Key added to user $NEW_USER"
        fi
        
        log "User $NEW_USER created."
        whiptail --msgbox "User $NEW_USER successfully created." 8 45
    fi
}

run_ssh_harden() {
    log "START: SSH Hardening"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    # Disable Root Login
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    
    # Disable Password Auth
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    
    systemctl restart ssh
    log "END: SSH Hardening completed."
    whiptail --msgbox "SSH Configured. Root Login & Password Auth disabled." 8 60
}

run_firewall() {
    log "START: Firewall Setup"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    
    echo "y" | ufw enable
    log "END: UFW Firewall active."
}

run_fail2ban() {
    log "START: Install Fail2Ban"
    apt-get install fail2ban -y
    
    # Copy default config to local to prevent overwrite during updates
    if [ ! -f /etc/fail2ban/jail.local ]; then
        cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    fi
    
    systemctl enable fail2ban
    systemctl start fail2ban
    log "END: Fail2Ban active."
}

run_timezone() {
    timedatectl set-timezone Asia/Jakarta
    log "Timezone set to Asia/Jakarta."
}

run_swap() {
    # Check double execution
    if swapon --show | grep -q "file"; then
        whiptail --msgbox "Swap file already exists. Skipping." 8 45
        return
    fi
    
    log "START: Setup Dynamic Swap"
    
    # 1. Calculate RAM (MB) & Target Swap (2x RAM)
    TOTAL_RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
    SWAP_SIZE_MB=$((TOTAL_RAM_MB * 2))
    
    whiptail --msgbox "Detected RAM: ${TOTAL_RAM_MB} MB\nTarget Swap: ${SWAP_SIZE_MB} MB (2x RAM)\n\nClick OK to proceed..." 12 50
    
    # 2. Create File
    # Try fallocate first (faster), if fails use dd
    if ! fallocate -l "${SWAP_SIZE_MB}M" /swapfile; then
        log "Fallocate failed, using DD..."
        dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress
    fi
    
    # 3. Secure & Activate
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # 4. Add to fstab (Permanent)
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
    fi
    
    log "END: Swap ${SWAP_SIZE_MB}MB created."
    whiptail --msgbox "Swap file ${SWAP_SIZE_MB}MB successfully created!" 8 45
}

# --- MAIN MENU LOOP ---

while true; do
    # Update status indicators
    S_UPDATE=$(check_update)
    S_USER=$(check_user)
    S_SSH=$(check_ssh)
    S_UFW=$(check_firewall)
    S_F2B=$(check_fail2ban)
    S_TZ=$(check_timezone)
    S_SWAP=$(check_swap)

    CHOICES=$(whiptail --title "VPS Setup Automation" --checklist \
    "Navigation: [↑/↓] Move, [Space] Select, [Enter] Confirm" 20 78 10 \
    "1" "Update & Upgrade OS" "$S_UPDATE" \
    "2" "Create Sudo User & Key" "$S_USER" \
    "3" "Harden SSH (No Root/Pass)" "$S_SSH" \
    "4" "Setup Firewall (UFW)" "$S_UFW" \
    "5" "Install Fail2Ban" "$S_F2B" \
    "6" "Set Timezone (Asia/Jakarta)" "$S_TZ" \
    "7" "Auto Swap (2x RAM)" "$S_SWAP" 3>&1 1>&2 2>&3)

    exitstatus=$?
    if [ $exitstatus = 0 ]; then
        # Process user choices
        for CHOICE in $CHOICES; do
            case "$CHOICE" in
                "\"1\"") run_update ;;
                "\"2\"") run_user ;;
                "\"3\"") run_ssh_harden ;;
                "\"4\"") run_firewall ;;
                "\"5\"") run_fail2ban ;;
                "\"6\"") run_timezone ;;
                "\"7\"") run_swap ;;
            esac
        done
        whiptail --msgbox "All selected tasks completed!" 8 45
        break
    else
        echo "Setup cancelled."
        break
    fi
done
