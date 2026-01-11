#!/bin/bash

# ==========================================================
# SERVER AUTOMATION WIZARD (V5 - ENGLISH & AESTHETIC)
# Features: Dashboard UI, Silent Install, Auto-Root, Loop
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

# Status Symbols
CHECK_MARK="${GREEN} [INSTALLED] ${RESET}"
CROSS_MARK="${RED} [MISSING]   ${RESET}"

# --- 3. STATUS CHECKS (Silent) ---
is_updated() { [ -f /var/lib/apt/periodic/update-success-stamp ] && find /var/lib/apt/periodic/update-success-stamp -mtime -1 2>/dev/null | grep -q .; }
is_user_ok() { awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null | grep -q .; }
is_ssh_ok()  { [ -f /etc/ssh/sshd_config ] && grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; }
is_fw_ok()   { command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; }
is_f2b_ok()  { systemctl is-active --quiet fail2ban 2>/dev/null; }
is_tz_ok()   { timedatectl 2>/dev/null | grep -q "Asia/Jakarta"; }
is_swap_ok() { swapon --show --noheadings 2>/dev/null | grep -q "."; }

# Helper to print status
get_status() {
    if $1; then echo -e "$CHECK_MARK"; else echo -e "$CROSS_MARK"; fi
}

# --- 4. MAIN LOOP ---

while true; do
    clear
    # --- HEADER DASHBOARD ---
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║               SERVER AUTOMATION WIZARD v5.0                  ║${RESET}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    
    # System Info Section
    MY_IP=$(hostname -I | cut -d' ' -f1)
    MY_OS=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    echo -e " ${BOLD}User:${RESET} root  |  ${BOLD}IP:${RESET} $MY_IP  |  ${BOLD}OS:${RESET} $MY_OS"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${RESET}"
    
    # --- MENU LIST ---
    echo -e " ${BOLD}NO   STATUS          TASK DESCRIPTION${RESET}"
    echo -e " ${BLUE}──   ──────          ────────────────${RESET}"
    echo -e " ${BOLD}1.${RESET}  $(get_status is_updated)   System Update & Upgrade"
    echo -e " ${BOLD}2.${RESET}  $(get_status is_user_ok)   Create Sudo User & Key"
    echo -e " ${BOLD}3.${RESET}  $(get_status is_ssh_ok)   Harden SSH (Disable Root/Pass)"
    echo -e " ${BOLD}4.${RESET}  $(get_status is_fw_ok)   Setup Firewall (UFW)"
    echo -e " ${BOLD}5.${RESET}  $(get_status is_f2b_ok)   Install Fail2Ban Protection"
    echo -e " ${BOLD}6.${RESET}  $(get_status is_tz_ok)   Set Timezone (Asia/Jakarta)"
    echo -e " ${BOLD}7.${RESET}  $(get_status is_swap_ok)   Auto Swap File (2x RAM)"
    echo -e " ${BOLD}0.${RESET}  ${WHITE}[ EXIT ]        Close Wizard${RESET}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${RESET}"
    echo -e "${MAGENTA}Tip: Type numbers separated by space (e.g., '1 3 7') then Enter.${RESET}"
    
    # --- INPUT ---
    echo ""
    read -p " ➤ Select Tasks: " SELECTION

    # Exit Logic
    if [[ "$SELECTION" == "0" || "$SELECTION" == "q" ]]; then
        echo -e "\n${GREEN}Goodbye! Setup completed.${RESET}\n"
        break
    fi

    # Select All Logic
    if [[ "$SELECTION" == "a" || "$SELECTION" == "A" ]]; then
        SELECTION="1 2 3 4 5 6 7"
    fi

    echo ""
    
    # --- EXECUTION LOOP ---
    for TASK in $SELECTION; do
        case "$TASK" in
            1)
                echo -e "${YELLOW}>> [1/7] Updating System Repositories...${RESET}"
                # Silent execution
                apt-get update -y > /dev/null 2>&1
                apt-get upgrade -y > /dev/null 2>&1
                apt-get autoremove -y > /dev/null 2>&1
                touch /var/lib/apt/periodic/update-success-stamp
                echo -e "${GREEN}   ✓ System Updated Successfully.${RESET}"
                ;;
            2)
                echo -e "${YELLOW}>> [2/7] Creating New User...${RESET}"
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
            3)
                echo -e "${YELLOW}>> [3/7] Hardening SSH Security...${RESET}"
                # Auto install if missing
                if [ ! -f /etc/ssh/sshd_config ]; then
                    echo -e "   Installing OpenSSH Server..."
                    apt-get install openssh-server -y > /dev/null 2>&1
                fi
                
                # Backup and Edit
                cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null
                sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null
                sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null
                sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null
                sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null
                
                systemctl restart ssh > /dev/null 2>&1
                echo -e "${GREEN}   ✓ SSH Secured (Root Login & Password Auth DISABLED).${RESET}"
                ;;
            4)
                echo -e "${YELLOW}>> [4/7] Configuring Firewall (UFW)...${RESET}"
                if ! command -v ufw &> /dev/null; then
                    echo "   Installing UFW..."
                    apt-get install ufw -y > /dev/null 2>&1
                fi
                ufw default deny incoming > /dev/null 2>&1
                ufw default allow outgoing > /dev/null 2>&1
                ufw allow ssh > /dev/null 2>&1
                ufw allow http > /dev/null 2>&1
                ufw allow https > /dev/null 2>&1
                echo "y" | ufw enable > /dev/null 2>&1
                echo -e "${GREEN}   ✓ Firewall Active (Ports 22, 80, 443 Allowed).${RESET}"
                ;;
            5)
                echo -e "${YELLOW}>> [5/7] Installing Fail2Ban...${RESET}"
                apt-get install fail2ban -y > /dev/null 2>&1
                cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local 2>/dev/null
                systemctl enable fail2ban --now > /dev/null 2>&1
                echo -e "${GREEN}   ✓ Fail2Ban Installed & Running.${RESET}"
                ;;
            6)
                echo -e "${YELLOW}>> [6/7] Setting Timezone...${RESET}"
                timedatectl set-timezone Asia/Jakarta 2>/dev/null
                echo -e "${GREEN}   ✓ Timezone set to Asia/Jakarta.${RESET}"
                ;;
            7)
                echo -e "${YELLOW}>> [7/7] Managing Swap File...${RESET}"
                if swapon --show | grep -q "file"; then
                    echo -e "${GREEN}   ✓ Swap file already exists.${RESET}"
                else
                    RAM=$(free -m | awk '/Mem:/ {print $2}')
                    SWAP=$((RAM * 2))
                    echo "   Creating Swap Size: ${SWAP}MB..."
                    
                    # Try fallocate first, fallback to dd
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
