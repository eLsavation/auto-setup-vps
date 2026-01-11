#!/bin/bash

# ==============================================================================
# PRO BASH SERVER SETUP
# ==============================================================================

# --- WARNA & FORMATTING ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- VARIABLES ---
LOG_FILE="/var/log/pro_setup.log"
declare -a TASKS
declare -a STATUS
declare -a SELECTED

TASKS[1]="System Update & Upgrade"
TASKS[2]="Create User & SSH Key"
TASKS[3]="Harden SSH (No Root/Pass)"
TASKS[4]="Setup UFW Firewall"
TASKS[5]="Install Fail2Ban"
TASKS[6]="Set Timezone (WIB)"
TASKS[7]="Auto Swap (2x RAM)"

# Default selection: False (Not selected)
for i in {1..7}; do SELECTED[$i]=false; done

# --- HELPER FUNCTIONS ---
log() { echo "[$(date)] $1" >> "$LOG_FILE"; }

header() {
    clear
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BOLD}   SERVER AUTOMATION DASHBOARD   ${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo -e "   ${CYAN}Hostname:${NC} $(hostname)  |  ${CYAN}IP:${NC} $(hostname -I | cut -d' ' -f1)"
    echo -e "   ${CYAN}OS:${NC} $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "   ${BOLD}NO  | STATUS    | SELECT | TASK NAME${NC}"
    echo -e "${BLUE}------------------------------------------------------------${NC}"
}

# --- CHECK FUNCTIONS (Real-time Status) ---
get_status_symbol() {
    if [ "$1" == "ON" ]; then echo -e "${GREEN}[OK]${NC} "; else echo -e "${RED}[--]${NC} "; fi
}

refresh_status() {
    # 1. Update
    if [ -f /var/lib/apt/periodic/update-success-stamp ] && find /var/lib/apt/periodic/update-success-stamp -mtime -1 | grep -q .; then
        STATUS[1]="ON"; else STATUS[1]="OFF"; fi
    
    # 2. User
    if awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | grep -q .; then
        STATUS[2]="ON"; else STATUS[2]="OFF"; fi

    # 3. SSH
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
        STATUS[3]="ON"; else STATUS[3]="OFF"; fi

    # 4. Firewall
    if ufw status | grep -q "Status: active"; then
        STATUS[4]="ON"; else STATUS[4]="OFF"; fi

    # 5. Fail2Ban
    if systemctl is-active --quiet fail2ban; then
        STATUS[5]="ON"; else STATUS[5]="OFF"; fi
    
    # 6. Timezone
    if timedatectl | grep -q "Asia/Jakarta"; then
        STATUS[6]="ON"; else STATUS[6]="OFF"; fi

    # 7. Swap
    if swapon --show --noheadings | grep -q "."; then
        STATUS[7]="ON"; else STATUS[7]="OFF"; fi
}

# --- ACTION FUNCTIONS ---
run_task_1() {
    echo -e "${YELLOW}>> Updating System...${NC}"
    apt-get update -qq && apt-get upgrade -y -qq && apt-get autoremove -y -qq
    touch /var/lib/apt/periodic/update-success-stamp
}

run_task_2() {
    echo -e "${YELLOW}>> Creating User...${NC}"
    read -p "   Enter New Username: " NEW_USER
    if id "$NEW_USER" &>/dev/null; then
        echo -e "${RED}   User exists!${NC}"
    else
        adduser --gecos "" "$NEW_USER"
        usermod -aG sudo "$NEW_USER"
        mkdir -p /home/$NEW_USER/.ssh
        echo -e "${CYAN}   Paste SSH Public Key below (Enter to skip):${NC}"
        read -r PUB_KEY
        if [ ! -z "$PUB_KEY" ]; then
            echo "$PUB_KEY" >> /home/$NEW_USER/.ssh/authorized_keys
            chmod 700 /home/$NEW_USER/.ssh
            chmod 600 /home/$NEW_USER/.ssh/authorized_keys
            chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
        fi
        echo -e "${GREEN}   User created.${NC}"
    fi
}

run_task_3() {
    echo -e "${YELLOW}>> Hardening SSH...${NC}"
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart ssh
}

run_task_4() {
    echo -e "${YELLOW}>> Configuring Firewall...${NC}"
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    echo "y" | ufw enable >/dev/null
}

run_task_5() {
    echo -e "${YELLOW}>> Installing Fail2Ban...${NC}"
    apt-get install fail2ban -y -qq
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    systemctl enable fail2ban --now
}

run_task_6() {
    echo -e "${YELLOW}>> Setting Timezone...${NC}"
    timedatectl set-timezone Asia/Jakarta
}

run_task_7() {
    echo -e "${YELLOW}>> Calculating Swap...${NC}"
    if swapon --show | grep -q "file"; then echo "Swap exists."; return; fi
    TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
    SWAP_SIZE=$((TOTAL_RAM * 2))
    echo "   Creating ${SWAP_SIZE}MB Swap..."
    fallocate -l "${SWAP_SIZE}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE status=none
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q "/swapfile" /etc/fstab; then echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
}

# --- MAIN LOOP ---

# Check Root
if [[ $EUID -ne 0 ]]; then echo -e "${RED}Run as Root!${NC}"; exit 1; fi

while true; do
    refresh_status
    header
    
    # Print Table
    for i in {1..7}; do
        # Determine Checkbox
        if [ "${SELECTED[$i]}" = true ]; then
            CHECKBOX="${GREEN}[X]${NC}"
            ROW_COLOR="${BOLD}"
        else
            CHECKBOX="[ ]"
            ROW_COLOR=""
        fi
        
        # Determine Status Symbol
        STAT_SYM=$(get_status_symbol "${STATUS[$i]}")
        
        printf "   %s%2d  | %-11s |  %s   | %s%s\n" "$ROW_COLOR" "$i" "$STAT_SYM" "$CHECKBOX" "${TASKS[$i]}" "${NC}"
    done
    
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    echo -e "   Controls: Type ${BOLD}number${NC} to toggle, ${BOLD}'a'${NC} for all, ${BOLD}'r'${NC} to run."
    echo -e "${BLUE}------------------------------------------------------------${NC}"
    
    read -p "   Your Choice > " CHOICE
    
    case "$CHOICE" in
        [1-7])
            if [ "${SELECTED[$CHOICE]}" = true ]; then
                SELECTED[$CHOICE]=false
            else
                SELECTED[$CHOICE]=true
            fi
            ;;
        "a"|"A")
            for i in {1..7}; do SELECTED[$i]=true; done
            ;;
        "c"|"C")
             for i in {1..7}; do SELECTED[$i]=false; done
             ;;
        "r"|"R")
            echo ""
            echo -e "${GREEN}=== STARTING EXECUTION ===${NC}"
            for i in {1..7}; do
                if [ "${SELECTED[$i]}" = true ]; then
                    case $i in
                        1) run_task_1 ;;
                        2) run_task_2 ;;
                        3) run_task_3 ;;
                        4) run_task_4 ;;
                        5) run_task_5 ;;
                        6) run_task_6 ;;
                        7) run_task_7 ;;
                    esac
                    log "Task $i executed."
                fi
            done
            echo -e "${GREEN}=== ALL DONE. Press Enter to exit. ===${NC}"
            read
            clear
            exit 0
            ;;
        "q"|"Q")
            clear
            exit 0
            ;;
        *)
            ;;
    esac
done
