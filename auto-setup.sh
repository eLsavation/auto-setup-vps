#!/bin/bash

# ==========================================================
# SERVER AUTOMATION WIZARD (V7 - DASHBOARD UI)
# Features: Compact Tasks, Dynamic Config Columns, Silent Mode
# ==========================================================

# --- 1. ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
   echo -e "\n\e[31m[ERROR] Please run this script as ROOT (sudo).\e[0m\n"
   exit 1
fi

# --- 2. COLORS & VARS ---
BOLD="\e[1m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
GRAY="\e[90m"
WHITE="\e[97m"
RESET="\e[0m"

# Symbols
CHECK_MARK="${GREEN}✔${RESET}"
CROSS_MARK="${RED}✘${RESET}"

# --- 3. DATA RETRIEVAL FUNCTIONS (For Config Column) ---

get_hostname_val() {
    hostname
}

get_update_val() {
    if [ -f /var/lib/apt/periodic/update-success-stamp ]; then
        # Check if updated in last 24h
        if find /var/lib/apt/periodic/update-success-stamp -mtime -1 2>/dev/null | grep -q .; then
            echo -e "${GREEN}Up to Date${RESET}"
        else
            echo -e "${YELLOW}Update Needed${RESET}"
        fi
    else
        echo -e "${RED}Never Updated${RESET}"
    fi
}

get_user_val() {
    # Count users with UID >= 1000
    USER_COUNT=$(awk -F: '$3 >= 1000 && $1 != "nobody"' /etc/passwd | wc -l)
    if [ "$USER_COUNT" -gt 0 ]; then
        echo -e "${GREEN}${USER_COUNT} Sudo User(s)${RESET}"
    else
        echo -e "${RED}Root Only${RESET}"
    fi
}

get_ssh_val() {
    if [ ! -f /etc/ssh/sshd_config ]; then
        echo "Not Installed"
        return
    fi
    
    # Get Port
    PORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
    PORT=${PORT:-22} # Default 22 if not found
    
    # Get Root Login Status
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then
        ROOT_STAT="${GREEN}Root:OFF${RESET}"
    else
        ROOT_STAT="${RED}Root:ON${RESET}"
    fi
    
    echo -e "Port:${BOLD}${PORT}${RESET} | ${ROOT_STAT}"
}

get_fw_val() {
    if ! command -v ufw &> /dev/null; then
        echo "Not Installed"
    elif ufw status | grep -q "Status: active"; then
        echo -e "${GREEN}Active${RESET}"
    else
        echo -e "${RED}Inactive${RESET}"
    fi
}

get_f2b_val() {
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
         echo -e "${GREEN}Running${RESET}"
    else
         echo "Not Running"
    fi
}

get_tz_val() {
    timedatectl | grep "Time zone" | awk '{print $3}'
}

get_swap_val() {
    if swapon --show | grep -q "file"; then
        SIZE=$(free -m | awk '/Swap:/ {print $2}')
        echo -e "${GREEN}${SIZE} MB${RESET}"
    else
        echo -e "${RED}No Swap${RESET}"
    fi
}

# --- 4. STATUS CHECK FUNCTIONS (For Checkbox) ---
is_hostname_set() { [ "$(hostname)" != "ubuntu" ]; }
is_updated() { [ -f /var/lib/apt/periodic/update-success-stamp ] && find /var/lib/apt/periodic/update-success-stamp -mtime -1 2>/dev/null | grep -q .; }
is_user_ok() { awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null | grep -q .; }
is_ssh_ok()  { [ -f /etc/ssh/sshd_config ] && grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; }
is_fw_ok()   { command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; }
is_f2b_ok()  { systemctl is-active --quiet fail2ban 2>/dev/null; }
is_tz_ok()   { timedatectl 2>/dev/null | grep -q "Asia/Jakarta"; }
is_swap_ok() { swapon --show --noheadings 2>/dev/null | grep -q "."; }

stat_icon() {
    if $1; then echo -e "$CHECK_MARK"; else echo -e "$CROSS_MARK"; fi
}

# --- 5. MAIN LOOP ---

while true; do
    clear
    # Header
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║                SERVER CONFIGURATION DASHBOARD (V7)                 ║${RESET}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${RESET}"
    
    # System Info Header
    IP=$(hostname -I | cut -d' ' -f1)
    echo -e " Host: ${BOLD}$(hostname)${RESET}  |  IP: ${BOLD}$IP${RESET}"
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${RESET}"
    
    # TABLE HEADER
    # Format: No | Stat | TaskName (Short) | Detail (Long)
    printf " ${BOLD}%-3s %-6s %-25s %-30s${RESET}\n" "NO" "STAT" "TASK" "CURRENT CONFIG"
    echo -e "${BLUE} ─── ────── ───────────────────────── ──────────────────────────────${RESET}"

    # ROW 1: Hostname
    printf " %-3s %-15s %-25s %-30s\n" "1." "$(stat_icon is_hostname_set)" "Set Hostname" "$(get_hostname_val)"
    
    # ROW 2: Update
    printf " %-3s %-15s %-25s %-30s\n" "2." "$(stat_icon is_updated)" "System Update" "$(get_update_val)"

    # ROW 3: User
    printf " %-3s %-15s %-25s %-30s\n" "3." "$(stat_icon is_user_ok)" "Create Sudo User" "$(get_user_val)"

    # ROW 4: SSH
    printf " %-3s %-15s %-25s %-30s\n" "4." "$(stat_icon is_ssh_ok)" "SSH Hardening" "$(get_ssh_val)"

    # ROW 5: Firewall
    printf " %-3s %-15s %-25s %-30s\n" "5." "$(stat_icon is_fw_ok)" "Setup Firewall" "$(get_fw_val)"

    # ROW 6: Fail2Ban
    printf " %-3s %-15s %-25s %-30s\n" "6." "$(stat_icon is_f2b_ok)" "Fail2Ban" "$(get_f2b_val)"

    # ROW 7: Timezone
    printf " %-3s %-15s %-25s %-30s\n" "7." "$(stat_icon is_tz_ok)" "Set Timezone" "$(get_tz_val)"

    # ROW 8: Swap
    printf " %-3s %-15s %-25s %-30s\n" "8." "$(stat_icon is_swap_ok)" "Auto Swap" "$(get_swap_val)"

    echo -e "${BLUE} ─── ────── ───────────────────────── ──────────────────────────────${RESET}"
    echo -e " ${BOLD}0.${RESET}  [EXIT] Close"
    echo ""
    
    # --- INPUT ---
    echo -e "${GRAY}Select task number (e.g., '1 4 5') or 'a' for all:${RESET}"
    read -p " ➤ " SELECTION

    # EXIT
    if [[ "$SELECTION" == "0" || "$SELECTION" == "q" ]]; then
        echo -e "\n${GREEN}Bye!${RESET}\n"; break
    fi

    if [[ "$SELECTION" == "a" || "$SELECTION" == "A" ]]; then SELECTION="1 2 3 4 5 6 7 8"; fi
    
    echo ""

    # --- EXECUTION ---
    for TASK in $SELECTION; do
        case "$TASK" in
            1)
                echo -e "${YELLOW}>> Changing Hostname...${RESET}"
                read -p "   New Hostname: " NEW_HOST
                if [ ! -z "$NEW_HOST" ]; then
                    hostnamectl set-hostname "$NEW_HOST"
                    sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOST/g" /etc/hosts
                    echo -e "${GREEN}   Done.${RESET}"
                fi
                ;;
            2)
                echo -e "${YELLOW}>> Updating System...${RESET}"
                apt-get update -y > /dev/null 2>&1
                apt-get upgrade -y > /dev/null 2>&1
                apt-get autoremove -y > /dev/null 2>&1
                touch /var/lib/apt/periodic/update-success-stamp
                echo -e "${GREEN}   Done.${RESET}"
                ;;
            3)
                echo -e "${YELLOW}>> Creating User...${RESET}"
                read -p "   Username: " NEW_USER
                if id "$NEW_USER" &>/dev/null; then
                    echo -e "${RED}   User exists.${RESET}"
                else
                    adduser --gecos "" "$NEW_USER" > /dev/null 2>&1
                    usermod -aG sudo "$NEW_USER"
                    mkdir -p /home/$NEW_USER/.ssh
                    echo -e "${CYAN}   Paste Public Key (Enter to skip):${RESET}"
                    read -r PUB_KEY
                    if [ ! -z "$PUB_KEY" ]; then
                        echo "$PUB_KEY" >> /home/$NEW_USER/.ssh/authorized_keys
                        chmod 700 /home/$NEW_USER/.ssh
                        chmod 600 /home/$NEW_USER/.ssh/authorized_keys
                        chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
                    fi
                    echo -e "${GREEN}   User Created.${RESET}"
                fi
                ;;
            4)
                echo -e "${YELLOW}>> Hardening SSH...${RESET}"
                if [ ! -f /etc/ssh/sshd_config ]; then apt-get install openssh-server -y >/dev/null 2>&1; fi
                cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null
                
                read -p "   Port [Default: 22]: " SSH_PORT
                SSH_PORT=${SSH_PORT:-22}
                
                sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
                sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                
                systemctl restart ssh > /dev/null 2>&1
                echo -e "${GREEN}   Done. Port: $SSH_PORT${RESET}"
                ;;
            5)
                echo -e "${YELLOW}>> Configuring Firewall...${RESET}"
                if ! command -v ufw &> /dev/null; then apt-get install ufw -y >/dev/null 2>&1; fi
                
                CURRENT_PORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
                CURRENT_PORT=${CURRENT_PORT:-22}
                
                ufw default deny incoming > /dev/null 2>&1
                ufw default allow outgoing > /dev/null 2>&1
                ufw allow $CURRENT_PORT/tcp > /dev/null 2>&1
                ufw allow 80/tcp > /dev/null 2>&1
                ufw allow 443/tcp > /dev/null 2>&1
                echo "y" | ufw enable > /dev/null 2>&1
                echo -e "${GREEN}   Done.${RESET}"
                ;;
            6)
                echo -e "${YELLOW}>> Installing Fail2Ban...${RESET}"
                apt-get install fail2ban -y > /dev/null 2>&1
                cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local 2>/dev/null
                systemctl enable fail2ban --now > /dev/null 2>&1
                echo -e "${GREEN}   Done.${RESET}"
                ;;
            7)
                echo -e "${YELLOW}>> Setting Timezone...${RESET}"
                timedatectl set-timezone Asia/Jakarta 2>/dev/null
                echo -e "${GREEN}   Done.${RESET}"
                ;;
            8)
                echo -e "${YELLOW}>> Creating Swap...${RESET}"
                if swapon --show | grep -q "file"; then
                    echo -e "${GREEN}   Exists.${RESET}"
                else
                    RAM=$(free -m | awk '/Mem:/ {print $2}')
                    SWAP=$((RAM * 2))
                    fallocate -l "${SWAP}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=$SWAP status=none
                    chmod 600 /swapfile
                    mkswap /swapfile >/dev/null 2>&1
                    swapon /swapfile >/dev/null 2>&1
                    if ! grep -q "/swapfile" /etc/fstab; then echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
                    echo -e "${GREEN}   Done ($SWAP MB).${RESET}"
                fi
                ;;
        esac
    done
    
    echo ""
    echo -e "${CYAN}──────────────────────────────────────────────────────────────────────${RESET}"
    read -n 1 -s -r -p "Press any key to refresh dashboard..."
done
