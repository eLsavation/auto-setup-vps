#!/bin/bash

# ==========================================================
# SERVER AUTOMATION WIZARD (V6 - DETAILED & CUSTOMIZABLE)
# Features: Change Hostname, Custom Ports, Detailed Logs
# ==========================================================

# --- 1. ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
   echo -e "\n\e[31m[ERROR] Please run this script as ROOT (sudo).\e[0m\n"
   exit 1
fi

# --- 2. AESTHETICS & COLORS ---
BOLD="\e[1m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
MAGENTA="\e[35m"
WHITE="\e[97m"
RESET="\e[0m"

# Symbols
CHECK_MARK="${GREEN} [OK]      ${RESET}"
CROSS_MARK="${RED} [PENDING] ${RESET}"

# --- 3. STATUS CHECKS ---
is_hostname_set() { [ "$(hostname)" != "ubuntu" ] && [ "$(hostname)" != "localhost" ]; } # Simple check
is_updated() { [ -f /var/lib/apt/periodic/update-success-stamp ] && find /var/lib/apt/periodic/update-success-stamp -mtime -1 2>/dev/null | grep -q .; }
is_user_ok() { awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null | grep -q .; }
is_ssh_ok()  { [ -f /etc/ssh/sshd_config ] && grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; }
is_fw_ok()   { command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; }
is_f2b_ok()  { systemctl is-active --quiet fail2ban 2>/dev/null; }
is_tz_ok()   { timedatectl 2>/dev/null | grep -q "Asia/Jakarta"; }
is_swap_ok() { swapon --show --noheadings 2>/dev/null | grep -q "."; }

get_status() {
    if $1; then echo -e "$CHECK_MARK"; else echo -e "$CROSS_MARK"; fi
}

# --- 4. MAIN LOOP ---

while true; do
    clear
    # --- HEADER DASHBOARD ---
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║            SERVER AUTOMATION WIZARD v6.0 (PRO)               ║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    
    # System Info
    MY_IP=$(hostname -I | cut -d' ' -f1)
    MY_HOST=$(hostname)
    echo -e " ${BOLD}Host:${RESET} $MY_HOST  |  ${BOLD}IP:${RESET} $MY_IP"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${RESET}"
    
    # --- MENU LIST ---
    echo -e " ${BOLD}NO   STATUS       TASK DESCRIPTION${RESET}"
    echo -e " ${BLUE}──   ──────       ────────────────${RESET}"
    echo -e " ${BOLD}1.${RESET}  $(get_status is_hostname_set)   Change Hostname (Current: $MY_HOST)"
    echo -e " ${BOLD}2.${RESET}  $(get_status is_updated)   System Update & Upgrade"
    echo -e " ${BOLD}3.${RESET}  $(get_status is_user_ok)   Create Sudo User & Key"
    echo -e " ${BOLD}4.${RESET}  $(get_status is_ssh_ok)   Harden SSH (Custom Port & Security)"
    echo -e " ${BOLD}5.${RESET}  $(get_status is_fw_ok)   Setup Firewall (Auto-detect SSH Port)"
    echo -e " ${BOLD}6.${RESET}  $(get_status is_f2b_ok)   Install Fail2Ban Protection"
    echo -e " ${BOLD}7.${RESET}  $(get_status is_tz_ok)   Set Timezone (Asia/Jakarta)"
    echo -e " ${BOLD}8.${RESET}  $(get_status is_swap_ok)   Auto Swap File (2x RAM)"
    echo -e " ${BOLD}0.${RESET}  ${WHITE}[ EXIT ]     Close Wizard${RESET}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${RESET}"
    echo -e "${MAGENTA}Tip: Type numbers (e.g., '1 4 5') then Enter.${RESET}"
    
    # --- INPUT ---
    echo ""
    read -p " ➤ Select Tasks: " SELECTION

    if [[ "$SELECTION" == "0" || "$SELECTION" == "q" ]]; then
        echo -e "\n${GREEN}Goodbye!${RESET}\n"; break
    fi

    if [[ "$SELECTION" == "a" || "$SELECTION" == "A" ]]; then
        SELECTION="1 2 3 4 5 6 7 8"
    fi

    echo ""
    
    # --- EXECUTION LOOP ---
    for TASK in $SELECTION; do
        case "$TASK" in
            1)
                echo -e "${YELLOW}>> [1/8] Changing Hostname...${RESET}"
                read -p "   Enter New Hostname: " NEW_HOST
                if [ -z "$NEW_HOST" ]; then
                    echo -e "${RED}   ! Name cannot be empty.${RESET}"
                else
                    hostnamectl set-hostname "$NEW_HOST"
                    # Update /etc/hosts to prevent sudo warnings
                    sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOST/g" /etc/hosts
                    echo -e "${GREEN}   ✓ Hostname changed to: ${BOLD}$NEW_HOST${RESET}"
                    echo -e "     (Note: Re-login to see changes in terminal prompt)"
                fi
                ;;
            2)
                echo -e "${YELLOW}>> [2/8] Updating System Repositories...${RESET}"
                apt-get update -y > /dev/null 2>&1
                apt-get upgrade -y > /dev/null 2>&1
                apt-get autoremove -y > /dev/null 2>&1
                touch /var/lib/apt/periodic/update-success-stamp
                echo -e "${GREEN}   ✓ System Updated Successfully.${RESET}"
                ;;
            3)
                echo -e "${YELLOW}>> [3/8] Creating New User...${RESET}"
                read -p "   Enter New Username: " NEW_USER
                if id "$NEW_USER" &>/dev/null; then
                    echo -e "${RED}   ! User $NEW_USER already exists.${RESET}"
                else
                    adduser --gecos "" "$NEW_USER" > /dev/null 2>&1
                    usermod -aG sudo "$NEW_USER"
                    mkdir -p /home/$NEW_USER/.ssh
                    
                    echo -e "${CYAN}   Paste SSH Public Key (Press Enter to skip):${RESET}"
                    read -r PUB_KEY
                    if [ ! -z "$PUB_KEY" ]; then
                        echo "$PUB_KEY" >> /home/$NEW_USER/.ssh/authorized_keys
                        chmod 700 /home/$NEW_USER/.ssh
                        chmod 600 /home/$NEW_USER/.ssh/authorized_keys
                        chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
                        echo -e "${GREEN}   ✓ SSH Key Added.${RESET}"
                    fi
                    echo -e "${GREEN}   ✓ User $NEW_USER Created.${RESET}"
                fi
                ;;
            4)
                echo -e "${YELLOW}>> [4/8] Hardening SSH Security...${RESET}"
                
                # 1. Install if missing
                if [ ! -f /etc/ssh/sshd_config ]; then
                    echo "   Installing OpenSSH Server..."
                    apt-get install openssh-server -y > /dev/null 2>&1
                fi
                
                # 2. Backup
                cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null
                
                # 3. Custom Port Input
                read -p "   Change SSH Port? (Default: 22) [Enter for 22]: " SSH_PORT
                SSH_PORT=${SSH_PORT:-22} # Default to 22 if empty
                
                # 4. Applying Config
                # Regex to replace Port 22 or #Port 22 with new port
                sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
                
                # Security settings
                sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                
                # 5. Restart
                systemctl restart ssh > /dev/null 2>&1
                
                echo -e "${GREEN}   ✓ Root Login : DISABLED${RESET}"
                echo -e "${GREEN}   ✓ Password Auth : DISABLED${RESET}"
                echo -e "${GREEN}   ✓ SSH Port : ${BOLD}$SSH_PORT${RESET}"
                ;;
            5)
                echo -e "${YELLOW}>> [5/8] Configuring Firewall (UFW)...${RESET}"
                if ! command -v ufw &> /dev/null; then
                    apt-get install ufw -y > /dev/null 2>&1
                fi
                
                # Detect current SSH Port from config
                CURRENT_SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
                CURRENT_SSH_PORT=${CURRENT_SSH_PORT:-22} # Fallback to 22
                
                ufw default deny incoming > /dev/null 2>&1
                ufw default allow outgoing > /dev/null 2>&1
                
                # Allow Dynamic SSH Port
                ufw allow $CURRENT_SSH_PORT/tcp > /dev/null 2>&1
                ufw allow 80/tcp > /dev/null 2>&1
                ufw allow 443/tcp > /dev/null 2>&1
                
                echo "y" | ufw enable > /dev/null 2>&1
                
                echo -e "${GREEN}   ✓ Firewall Active.${RESET}"
                echo -e "${GREEN}   ✓ Allowed Ports: 80, 443, and SSH ($CURRENT_SSH_PORT)${RESET}"
                ;;
            6)
                echo -e "${YELLOW}>> [6/8] Installing Fail2Ban...${RESET}"
                apt-get install fail2ban -y > /dev/null 2>&1
                cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local 2>/dev/null
                systemctl enable fail2ban --now > /dev/null 2>&1
                echo -e "${GREEN}   ✓ Fail2Ban Installed & Running.${RESET}"
                ;;
            7)
                echo -e "${YELLOW}>> [7/8] Setting Timezone...${RESET}"
                timedatectl set-timezone Asia/Jakarta 2>/dev/null
                echo -e "${GREEN}   ✓ Timezone set to Asia/Jakarta.${RESET}"
                ;;
            8)
                echo -e "${YELLOW}>> [8/8] Managing Swap File...${RESET}"
                if swapon --show | grep -q "file"; then
                    echo -e "${GREEN}   ✓ Swap file already exists.${RESET}"
                else
                    RAM=$(free -m | awk '/Mem:/ {print $2}')
                    SWAP=$((RAM * 2))
                    echo "   Creating Swap Size: ${SWAP}MB..."
                    fallocate -l "${SWAP}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=$SWAP status=none
                    chmod 600 /swapfile
                    mkswap /swapfile > /dev/null 2>&1
                    swapon /swapfile > /dev/null 2>&1
                    if ! grep -q "/swapfile" /etc/fstab; then echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
                    echo -e "${GREEN}   ✓ Swap Created & Activated.${RESET}"
                fi
                ;;
        esac
    done
    
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${RESET}"
    read -n 1 -s -r -p "Press any key to return to menu..."
done
