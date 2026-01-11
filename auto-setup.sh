#!/bin/bash

# ==========================================================
# SERVER AUTOMATION SUITE (FINAL UI EDITION)
# ==========================================================

# --- 1. ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
   echo -e "\n\e[31m[ERROR] Please run this script as ROOT (sudo).\e[0m\n"
   exit 1
fi

# --- 2. STYLING VARS ---
BOLD="\e[1m"
DIM="\e[2m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
MAGENTA="\e[35m"
WHITE="\e[97m"
RESET="\e[0m"

# Backgrounds
BG_BLUE="\e[44m"
BG_RED="\e[41m"

# Symbols
CHECK_MARK="${GREEN}✔${RESET}"
CROSS_MARK="${RED}✘${RESET}"
ARROW="➜"

# --- 3. CONFIG DETAIL FUNCTIONS (LOGIC V10) ---

get_hostname_val() { echo "$(hostname)"; }

get_update_val() {
    if [ -f /var/lib/apt/periodic/update-success-stamp ]; then
        if find /var/lib/apt/periodic/update-success-stamp -mtime -1 2>/dev/null | grep -q .; then
            echo "Updated (<24h)"
        else
            echo "Old Update (>24h)"
        fi
    else
        echo "Never Updated"
    fi
}

get_user_val() {
    LAST_USER=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | tail -n 1)
    COUNT=$(awk -F: '$3 >= 1000 && $1 != "nobody"' /etc/passwd | wc -l)
    if [ "$COUNT" -gt 0 ]; then echo "$COUNT User(s) (Last: $LAST_USER)"; else echo "${RED}Root Only${RESET}"; fi
}

get_ssh_val() {
    if [ ! -f /etc/ssh/sshd_config ]; then echo "Not Installed"; return; fi
    PORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}'); PORT=${PORT:-22}
    if grep -q "^PermitRootLogin no" /etc/ssh/sshd_config; then R_LOGIN="Root:${GREEN}OFF${RESET}"; else R_LOGIN="Root:${RED}ON${RESET}"; fi
    echo "Port:${BOLD}$PORT${RESET} | $R_LOGIN"
}

get_fw_val() {
    if ! command -v ufw &> /dev/null; then echo "Not Installed"; return; fi
    if ufw status | grep -q "Status: active"; then
        PORTS=$(ufw status | grep "ALLOW" | grep -v "(v6)" | awk -F"/" '{print $1}' | sort -nu | tr '\n' ',' | sed 's/,$//')
        if [ -z "$PORTS" ]; then echo "${GREEN}Active${RESET} (No Ports)"; else echo "${GREEN}Open:${RESET} $PORTS"; fi
    else
        echo "${RED}Inactive${RESET}"
    fi
}

get_f2b_val() {
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
         JAILS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | cut -d: -f2 | sed 's/\t//g' | sed 's/,//g' | sed 's/^ *//g')
         echo "${GREEN}Active${RESET} (${JAILS:-None})"
    else echo "${RED}Not Running${RESET}"; fi
}

get_bbr_val() {
    CURRENT_ALGO=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    if [ "$CURRENT_ALGO" == "bbr" ]; then echo -e "${GREEN}Enabled (BBR)${RESET}"; else echo "Disabled ($CURRENT_ALGO)"; fi
}

get_autoupdate_val() {
    if [ -f /etc/apt/apt.conf.d/20auto-upgrades ] && grep -q "1" /etc/apt/apt.conf.d/20auto-upgrades; then
        echo -e "${GREEN}Enabled${RESET}"; else echo "Disabled"; fi
}

get_docker_val() {
    if command -v docker &> /dev/null; then
        VER=$(docker --version | awk '{print $3}' | sed 's/,//')
        echo -e "${GREEN}Installed ($VER)${RESET}"; else echo "Not Installed"; fi
}

# --- 4. STATUS CHECK LOGIC ---
is_hostname_set() { [ "$(hostname)" != "ubuntu" ]; }
is_updated() { [ -f /var/lib/apt/periodic/update-success-stamp ] && find /var/lib/apt/periodic/update-success-stamp -mtime -1 2>/dev/null | grep -q .; }
is_user_ok() { awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null | grep -q .; }
is_ssh_ok()  { [ -f /etc/ssh/sshd_config ] && grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; }
is_fw_ok()   { command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; }
is_f2b_ok()  { systemctl is-active --quiet fail2ban 2>/dev/null; }
is_bbr_ok()  { sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; }
is_auto_ok() { [ -f /etc/apt/apt.conf.d/20auto-upgrades ] && grep -q "1" /etc/apt/apt.conf.d/20auto-upgrades; }
is_docker_ok() { command -v docker >/dev/null; }

stat_icon() { if $1; then echo -e "$CHECK_MARK"; else echo -e "$CROSS_MARK"; fi; }

# --- 5. UI COMPONENTS ---

draw_header() {
    clear
    echo -e "${BG_BLUE}${WHITE}${BOLD}                                                                      ${RESET}"
    echo -e "${BG_BLUE}${WHITE}${BOLD}                    SERVER AUTOMATION SUITE v1.0                      ${RESET}"
    echo -e "${BG_BLUE}${WHITE}${BOLD}                                                                      ${RESET}"
    echo ""
    
    # System Info Box
    IP=$(hostname -I | cut -d' ' -f1)
    OS=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    KERNEL=$(uname -r)
    
    echo -e "${CYAN}┌── SYSTEM INFO ──────────────────────────────────────────────────────┐${RESET}"
    printf "${CYAN}│${RESET}  ${BOLD}%-10s${RESET} : %-48s ${CYAN}│${RESET}\n" "Hostname" "$(hostname)"
    printf "${CYAN}│${RESET}  ${BOLD}%-10s${RESET} : %-48s ${CYAN}│${RESET}\n" "IP Addr" "$IP"
    printf "${CYAN}│${RESET}  ${BOLD}%-10s${RESET} : %-48s ${CYAN}│${RESET}\n" "OS Distro" "$OS"
    printf "${CYAN}│${RESET}  ${BOLD}%-10s${RESET} : %-48s ${CYAN}│${RESET}\n" "Kernel" "$KERNEL"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────┘${RESET}"
}

draw_row() {
    # $1=No, $2=Icon, $3=Task, $4=Detail
    printf " ${BOLD}%-3s${RESET} %-16s ${WHITE}%-22s${RESET} %-45s\n" "$1" "$2" "$3" "$4"
}

draw_separator() {
    echo -e "${DIM}───────────────────────────────────────────────────────────────────────${RESET}"
}

# --- 6. MAIN LOOP ---

while true; do
    draw_header
    
    # --- TABLE HEADER ---
    echo ""
    printf " ${DIM}%-3s %-6s %-22s %-35s${RESET}\n" "NO" "STAT" "TASK" "CURRENT CONFIG"
    draw_separator

    # GROUP 1: ESSENTIAL SECURITY
    echo -e "${CYAN} ${BOLD}:: ESSENTIAL SECURITY${RESET}"
    draw_row "1." "$(stat_icon is_hostname_set)" "Set Hostname" "$(get_hostname_val)"
    draw_row "2." "$(stat_icon is_updated)" "System Update" "$(get_update_val)"
    draw_row "3." "$(stat_icon is_user_ok)" "Create User" "$(get_user_val)"
    draw_row "4." "$(stat_icon is_ssh_ok)" "SSH Hardening" "$(get_ssh_val)"
    draw_row "5." "$(stat_icon is_fw_ok)" "Firewall (UFW)" "$(get_fw_val)"
    draw_row "6." "$(stat_icon is_f2b_ok)" "Fail2Ban" "$(get_f2b_val)"
    
    echo ""
    # GROUP 2: PERFORMANCE & DEVOPS
    echo -e "${MAGENTA} ${BOLD}:: PERFORMANCE & DEVOPS${RESET}"
    draw_row "7." "$(stat_icon is_bbr_ok)" "TCP BBR" "$(get_bbr_val)"
    draw_row "8." "$(stat_icon is_auto_ok)" "Auto Patching" "$(get_autoupdate_val)"
    draw_row "9." "$(stat_icon is_docker_ok)" "Docker Engine" "$(get_docker_val)"

    draw_separator
    echo -e " ${BOLD}0.${RESET}  Exit / Quit"
    echo ""
    
    echo -e "${YELLOW}Enter task numbers separated by space (e.g., '1 7 8') or 'a' for all:${RESET}"
    read -p " $ARROW " SELECTION

    if [[ "$SELECTION" == "0" || "$SELECTION" == "q" ]]; then
        echo -e "\n${GREEN}Setup Completed. Goodbye!${RESET}\n"
        break
    fi
    if [[ "$SELECTION" == "a" || "$SELECTION" == "A" ]]; then SELECTION="1 2 3 4 5 6 7 8 9"; fi
    echo ""

    # --- EXECUTION LOOP ---
    for TASK in $SELECTION; do
        case "$TASK" in
            1)
                echo -e "${BLUE}>> Setting Hostname...${RESET}"
                read -p "   New Hostname: " NEW_HOST
                if [ ! -z "$NEW_HOST" ]; then
                    hostnamectl set-hostname "$NEW_HOST"
                    sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOST/g" /etc/hosts
                    echo -e "${GREEN}   $CHECK_MARK Done.${RESET}"
                fi
                ;;
            2)
                echo -e "${BLUE}>> Updating System...${RESET}"
                apt-get update -y > /dev/null 2>&1
                apt-get upgrade -y > /dev/null 2>&1
                apt-get autoremove -y > /dev/null 2>&1
                touch /var/lib/apt/periodic/update-success-stamp
                echo -e "${GREEN}   $CHECK_MARK Done.${RESET}"
                ;;
            3)
                echo -e "${BLUE}>> Creating User...${RESET}"
                read -p "   Username: " NEW_USER
                if id "$NEW_USER" &>/dev/null; then
                    echo -e "${RED}   ! User exists.${RESET}"
                else
                    adduser --gecos "" "$NEW_USER" > /dev/null 2>&1
                    usermod -aG sudo "$NEW_USER"
                    mkdir -p /home/$NEW_USER/.ssh
                    echo -e "${DIM}   Paste Public Key (Enter to skip):${RESET}"
                    read -r PUB_KEY
                    if [ ! -z "$PUB_KEY" ]; then
                        echo "$PUB_KEY" >> /home/$NEW_USER/.ssh/authorized_keys
                        chmod 700 /home/$NEW_USER/.ssh
                        chmod 600 /home/$NEW_USER/.ssh/authorized_keys
                        chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
                    fi
                    echo -e "${GREEN}   $CHECK_MARK User Created.${RESET}"
                fi
                ;;
            4)
                echo -e "${BLUE}>> Hardening SSH...${RESET}"
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
                echo -e "${GREEN}   $CHECK_MARK Done. Port: $SSH_PORT.${RESET}"
                ;;
            5)
                echo -e "${BLUE}>> Configuring Firewall...${RESET}"
                if ! command -v ufw &> /dev/null; then apt-get install ufw -y >/dev/null 2>&1; fi
                CURRENT_PORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}'); CURRENT_PORT=${CURRENT_PORT:-22}
                ufw default deny incoming > /dev/null 2>&1
                ufw default allow outgoing > /dev/null 2>&1
                ufw allow $CURRENT_PORT/tcp > /dev/null 2>&1
                ufw allow 80/tcp > /dev/null 2>&1
                ufw allow 443/tcp > /dev/null 2>&1
                echo "y" | ufw enable > /dev/null 2>&1
                echo -e "${GREEN}   $CHECK_MARK Rules updated.${RESET}"
                ;;
            6)
                echo -e "${BLUE}>> Installing Fail2Ban...${RESET}"
                apt-get install fail2ban -y > /dev/null 2>&1
                cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local 2>/dev/null
                systemctl enable fail2ban --now > /dev/null 2>&1
                echo -e "${GREEN}   $CHECK_MARK Done.${RESET}"
                ;;
            7)
                echo -e "${BLUE}>> Enabling TCP BBR...${RESET}"
                if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
                    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
                    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
                    sysctl -p > /dev/null 2>&1
                    echo -e "${GREEN}   $CHECK_MARK BBR Enabled.${RESET}"
                else
                    echo -e "${GREEN}   $CHECK_MARK BBR already active.${RESET}"
                fi
                ;;
            8)
                echo -e "${BLUE}>> Configuring Auto-Updates...${RESET}"
                apt-get install unattended-upgrades -y > /dev/null 2>&1
                echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
                echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
                echo -e "${GREEN}   $CHECK_MARK Auto Security Updates Enabled.${RESET}"
                ;;
            9)
                echo -e "${BLUE}>> Installing Docker & Compose...${RESET}"
                if command -v docker &> /dev/null; then
                     echo -e "${GREEN}   $CHECK_MARK Docker already installed.${RESET}"
                else
                     curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
                     usermod -aG docker $USER
                     echo -e "${GREEN}   $CHECK_MARK Docker Installed.${RESET}"
                fi
                ;;
        esac
    done
    
    echo ""
    echo -e "${DIM}Press any key to refresh dashboard...${RESET}"
    read -n 1 -s -r
done
