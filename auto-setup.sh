#!/bin/bash

# ==========================================================
# SERVER SETUP AUTOMATION (V12 - FIX TAMPILAN)
# ==========================================================

# --- 1. ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
   echo "Error: Script must be run as ROOT."
   exit 1
fi

# --- 2. STYLING VARS (FIXED ANSI FORMAT) ---
# Menggunakan $'\033...' memastikan bash membacanya sebagai warna, bukan teks.
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
CYAN=$'\033[36m'
WHITE=$'\033[97m'
RESET=$'\033[0m'

# Icons
ICON_OK="${GREEN}●${RESET}"
ICON_NO="${RED}○${RESET}"
ARROW="${CYAN}➜${RESET}"

# --- 3. LOGIC & STATUS FUNCTIONS ---

get_hostname_val() { echo "$(hostname)"; }

get_update_val() {
    if [ -f /var/lib/apt/periodic/update-success-stamp ]; then
        if find /var/lib/apt/periodic/update-success-stamp -mtime -1 2>/dev/null | grep -q .; then
            echo "${GREEN}Updated${RESET}"; else echo "${YELLOW}Outdated${RESET}"; fi
    else echo "${RED}Never${RESET}"; fi
}

get_user_val() {
    COUNT=$(awk -F: '$3 >= 1000 && $1 != "nobody"' /etc/passwd | wc -l)
    LAST=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | tail -n 1)
    if [ "$COUNT" -gt 0 ]; then echo "$COUNT User(s) ($LAST)"; else echo "${RED}Root Only${RESET}"; fi
}

get_ssh_val() {
    if [ ! -f /etc/ssh/sshd_config ]; then echo "Not Installed"; return; fi
    PORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}'); PORT=${PORT:-22}
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then ROOT="${GREEN}OFF${RESET}"; else ROOT="${RED}ON${RESET}"; fi
    echo "Port $PORT | Root $ROOT"
}

get_fw_val() {
    if ! command -v ufw &> /dev/null; then echo "Missing"; return; fi
    if ufw status | grep -q "Status: active"; then
        PORTS=$(ufw status | grep "ALLOW" | grep -v "(v6)" | awk -F"/" '{print $1}' | sort -nu | tr '\n' ',' | sed 's/,$//')
        echo "${GREEN}Active${RESET} [${PORTS:-None}]"
    else echo "${RED}Inactive${RESET}"; fi
}

get_f2b_val() {
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
         JAILS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | cut -d: -f2 | sed 's/\t//g' | sed 's/,//g' | sed 's/^ *//g')
         echo "${GREEN}ON${RESET} (${JAILS:-None})"
    else echo "${RED}OFF${RESET}"; fi
}

get_autoupdate_val() {
    if [ -f /etc/apt/apt.conf.d/20auto-upgrades ] && grep -q "1" /etc/apt/apt.conf.d/20auto-upgrades; then
        echo "${GREEN}Enabled${RESET}"; else echo "${DIM}Disabled${RESET}"; fi
}

# --- 4. CHECK BOOLEANS ---
is_hostname_set() { [ "$(hostname)" != "ubuntu" ]; }
is_updated() { [ -f /var/lib/apt/periodic/update-success-stamp ] && find /var/lib/apt/periodic/update-success-stamp -mtime -1 2>/dev/null | grep -q .; }
is_user_ok() { awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null | grep -q .; }
is_ssh_ok()  { [ -f /etc/ssh/sshd_config ] && grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; }
is_fw_ok()   { command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; }
is_f2b_ok()  { systemctl is-active --quiet fail2ban 2>/dev/null; }
is_auto_ok() { [ -f /etc/apt/apt.conf.d/20auto-upgrades ] && grep -q "1" /etc/apt/apt.conf.d/20auto-upgrades; }

stat_icon() { if $1; then echo -e "$ICON_OK"; else echo -e "$ICON_NO"; fi; }

# --- 5. UI COMPONENTS ---

draw_line() { echo -e "${DIM}────────────────────────────────────────────────────────────────────────${RESET}"; }

draw_header() {
    clear
    echo -e "${BOLD}${CYAN}"
    echo "  SERVER CONFIGURATION DASHBOARD"
    echo -e "${RESET}"
    
    # Simple System Info
    IP=$(hostname -I | cut -d' ' -f1)
    OS=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    echo -e "  HOST : ${WHITE}$(hostname)${RESET}"
    echo -e "  IP   : ${WHITE}$IP${RESET}"
    echo -e "  OS   : ${WHITE}$OS${RESET}"
    echo ""
}

draw_row() {
    # Format: ID | Icon | Task Name | Status Detail
    # Menggunakan %b agar escape color code terbaca dengan benar
    printf "  ${BOLD}%-2s${RESET}  %b  ${WHITE}%-20s${RESET}  %b\n" "$1" "$2" "$3" "$4"
}

# --- 6. MAIN LOOP ---

while true; do
    draw_header
    
    echo -e "  ${DIM}ID  ST  TASK                  CURRENT STATE${RESET}"
    draw_line

    # MENU ITEMS
    draw_row "1" "$(stat_icon is_hostname_set)" "Hostname" "$(get_hostname_val)"
    draw_row "2" "$(stat_icon is_updated)" "System Update" "$(get_update_val)"
    draw_row "3" "$(stat_icon is_user_ok)" "Sudo User" "$(get_user_val)"
    draw_row "4" "$(stat_icon is_ssh_ok)" "SSH Hardening" "$(get_ssh_val)"
    draw_row "5" "$(stat_icon is_fw_ok)" "Firewall (UFW)" "$(get_fw_val)"
    draw_row "6" "$(stat_icon is_f2b_ok)" "Fail2Ban" "$(get_f2b_val)"
    draw_row "7" "$(stat_icon is_auto_ok)" "Auto Patching" "$(get_autoupdate_val)"

    echo ""
    draw_line
    echo -e "  ${DIM}[q] Quit  |  [a] Select All${RESET}"
    echo ""
    
    read -p "  $ARROW Select ID (e.g., 1 4 5): " SELECTION

    if [[ "$SELECTION" == "q" ]]; then echo -e "\n  ${GREEN}Done.${RESET}\n"; break; fi
    if [[ "$SELECTION" == "a" ]]; then SELECTION="1 2 3 4 5 6 7"; fi
    echo ""

    # --- EXECUTION ---
    for TASK in $SELECTION; do
        case "$TASK" in
            1)
                echo -e "  ${CYAN}>> Setting Hostname...${RESET}"
                read -p "     New Name: " NEW_HOST
                if [ ! -z "$NEW_HOST" ]; then
                    hostnamectl set-hostname "$NEW_HOST"
                    sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOST/g" /etc/hosts
                    echo -e "     ${GREEN}Success.${RESET}"
                fi
                ;;
            2)
                echo -e "  ${CYAN}>> Updating System...${RESET}"
                apt-get update -y >/dev/null 2>&1 && apt-get upgrade -y >/dev/null 2>&1 && apt-get autoremove -y >/dev/null 2>&1
                touch /var/lib/apt/periodic/update-success-stamp
                echo -e "     ${GREEN}Success.${RESET}"
                ;;
            3)
                echo -e "  ${CYAN}>> Creating User...${RESET}"
                read -p "     Username: " NEW_USER
                if id "$NEW_USER" &>/dev/null; then
                    echo -e "     ${RED}User exists.${RESET}"
                else
                    adduser --gecos "" "$NEW_USER" >/dev/null 2>&1
                    usermod -aG sudo "$NEW_USER"
                    mkdir -p /home/$NEW_USER/.ssh
                    echo -e "     ${DIM}Paste PubKey (Enter to skip):${RESET}"
                    read -r PUB_KEY
                    if [ ! -z "$PUB_KEY" ]; then
                        echo "$PUB_KEY" >> /home/$NEW_USER/.ssh/authorized_keys
                        chmod 700 /home/$NEW_USER/.ssh
                        chmod 600 /home/$NEW_USER/.ssh/authorized_keys
                        chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
                    fi
                    echo -e "     ${GREEN}Created.${RESET}"
                fi
                ;;
            4)
                echo -e "  ${CYAN}>> SSH Hardening...${RESET}"
                if [ ! -f /etc/ssh/sshd_config ]; then apt-get install openssh-server -y >/dev/null 2>&1; fi
                cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null
                read -p "     Port [22]: " SSH_PORT
                SSH_PORT=${SSH_PORT:-22}
                sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
                sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                systemctl restart ssh >/dev/null 2>&1
                echo -e "     ${GREEN}Secured on Port $SSH_PORT.${RESET}"
                ;;
            5)
                echo -e "  ${CYAN}>> Configuring UFW...${RESET}"
                if ! command -v ufw &> /dev/null; then apt-get install ufw -y >/dev/null 2>&1; fi
                CPORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}'); CPORT=${CPORT:-22}
                ufw default deny incoming >/dev/null 2>&1
                ufw default allow outgoing >/dev/null 2>&1
                ufw allow $CPORT/tcp >/dev/null 2>&1
                ufw allow 80/tcp >/dev/null 2>&1
                ufw allow 443/tcp >/dev/null 2>&1
                echo "y" | ufw enable >/dev/null 2>&1
                echo -e "     ${GREEN}Firewall Active.${RESET}"
                ;;
            6)
                echo -e "  ${CYAN}>> Installing Fail2Ban...${RESET}"
                apt-get install fail2ban -y >/dev/null 2>&1
                cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local 2>/dev/null
                systemctl enable fail2ban --now >/dev/null 2>&1
                echo -e "     ${GREEN}Installed.${RESET}"
                ;;
            7)
                echo -e "  ${CYAN}>> Auto-Updates...${RESET}"
                apt-get install unattended-upgrades -y >/dev/null 2>&1
                echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
                echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
                echo -e "     ${GREEN}Enabled.${RESET}"
                ;;
        esac
    done
    
    echo ""
    echo -e "  ${DIM}Press any key...${RESET}"
    read -n 1 -s -r
done
