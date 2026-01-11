#!/bin/bash

# ==========================================================
# SERVER SETUP AUTOMATION (V17 - UNIVERSAL MULTI-DISTRO)
# Author: github.com/eLsavation
# Supported: Ubuntu, Debian, CentOS, RHEL, Alma, Rocky
# ==========================================================

# --- 1. ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
   echo "Error: Script must be run as ROOT."
   exit 1
fi

# --- 2. OS DETECTION ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo "Unknown OS. Aborting."
    exit 1
fi

# Set Package Manager & Firewall Command
if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS" == "kali" || "$OS" == "linuxmint" ]]; then
    PKG_MGR="apt-get"
    INSTALL_CMD="apt-get install -y"
    UPDATE_CMD="apt-get update -y && apt-get upgrade -y"
    FIREWALL_TYPE="ufw"
    SSH_SERVICE="ssh"
elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "almalinux" || "$OS" == "rocky" || "$OS" == "fedora" ]]; then
    PKG_MGR="dnf"
    # Fallback to yum if dnf not found
    if ! command -v dnf &> /dev/null; then PKG_MGR="yum"; fi
    INSTALL_CMD="$PKG_MGR install -y"
    UPDATE_CMD="$PKG_MGR update -y"
    FIREWALL_TYPE="firewalld"
    SSH_SERVICE="sshd"
else
    echo "OS $OS not explicitly supported, but trying best effort..."
    PKG_MGR="apt-get" # Default fallback
    INSTALL_CMD="apt-get install -y"
    FIREWALL_TYPE="ufw"
    SSH_SERVICE="ssh"
fi

# --- 3. STYLING VARS ---
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
CYAN=$'\033[36m'
WHITE=$'\033[97m'
RESET=$'\033[0m'

ICON_OK="${GREEN}●${RESET}"
ICON_NO="${RED}○${RESET}"
ARROW="${CYAN}➜${RESET}"

# --- 4. STATUS FUNCTIONS ---
get_hostname_val() { echo "$(hostname)"; }
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
    if [[ "$FIREWALL_TYPE" == "ufw" ]]; then
        if ! command -v ufw &> /dev/null; then echo "Missing"; return; fi
        if ufw status | grep -q "Status: active"; then
            PORTS=$(ufw status | grep "ALLOW" | grep "/tcp" | grep -v "(v6)" | awk -F"/" '{print $1}' | sort -nu | tr '\n' ',' | sed 's/,$//')
            echo "${GREEN}Active${RESET} (UFW) [${PORTS:-None}]"
        else echo "${RED}Inactive${RESET}"; fi
    elif [[ "$FIREWALL_TYPE" == "firewalld" ]]; then
        if ! command -v firewall-cmd &> /dev/null; then echo "Missing"; return; fi
        if firewall-cmd --state &>/dev/null; then
            PORTS=$(firewall-cmd --list-ports | tr ' ' ',')
            SERVICES=$(firewall-cmd --list-services | tr ' ' ',')
            echo "${GREEN}Active${RESET} [${PORTS:-Default}]"
        else echo "${RED}Inactive${RESET}"; fi
    fi
}
get_swap_val() {
    if swapon --show | grep -q "file"; then
        SIZE=$(free -h | awk '/Swap:/ {print $2}')
        echo "${GREEN}Active${RESET} ($SIZE)"
    else echo "${RED}No Swap${RESET}"; fi
}

# --- 5. CHECK BOOLEANS ---
is_hostname_set() { [ "$(hostname)" != "localhost" ] && [ "$(hostname)" != "ubuntu" ] && [ "$(hostname)" != "centos" ]; }
is_updated() { 
    if [[ "$PKG_MGR" == "apt-get" ]]; then
        [ -f /var/lib/apt/periodic/update-success-stamp ] && find /var/lib/apt/periodic/update-success-stamp -mtime -1 2>/dev/null | grep -q .
    else
        # For RPM based, just assume false unless manually checked or complex logic
        return 1 
    fi
}
is_user_ok() { awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null | grep -q .; }
is_ssh_ok()  { [ -f /etc/ssh/sshd_config ] && grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; }
is_fw_ok()   { 
    if [[ "$FIREWALL_TYPE" == "ufw" ]]; then command -v ufw >/dev/null && ufw status | grep -q "active"; 
    else command -v firewall-cmd >/dev/null && firewall-cmd --state &>/dev/null; fi
}
is_swap_ok() { swapon --show --noheadings 2>/dev/null | grep -q "."; }

stat_icon() { if $1; then echo -e "$ICON_OK"; else echo -e "$ICON_NO"; fi; }

# --- 6. UI HEADER ---
draw_header() {
    clear
    MY_HOST=$(hostname)
    MY_IP=$(hostname -I | cut -d' ' -f1)
    MY_OS_PRETTY=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
    if [ ${#MY_OS_PRETTY} -gt 48 ]; then MY_OS_PRETTY="${MY_OS_PRETTY:0:45}..."; fi
    RAM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
    CPU_CORES=$(nproc)
    AUTHOR="github.com/eLsavation"

    printf "${CYAN}╔═════════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "${CYAN}║${RESET} ${BOLD}${WHITE}%-44s${RESET} ${DIM}%20s${RESET} ${CYAN}║${RESET}\n" "VPS AUTO SETUP WIZARD" "v17 ($OS)"
    printf "${CYAN}╠═════════════════════════════════════════════════════════════════╣${RESET}\n"
    printf "${CYAN}║${RESET} ${YELLOW}%-10s${RESET} : ${WHITE}%-50s${RESET} ${CYAN}║${RESET}\n" "Author" "$AUTHOR"
    printf "${CYAN}║${RESET} ${YELLOW}%-10s${RESET} : ${WHITE}%-50s${RESET} ${CYAN}║${RESET}\n" "Hostname" "$MY_HOST"
    printf "${CYAN}║${RESET} ${YELLOW}%-10s${RESET} : ${WHITE}%-50s${RESET} ${CYAN}║${RESET}\n" "IP Addr" "$MY_IP"
    printf "${CYAN}║${RESET} ${YELLOW}%-10s${RESET} : ${WHITE}%-50s${RESET} ${CYAN}║${RESET}\n" "OS System" "$MY_OS_PRETTY"
    printf "${CYAN}║${RESET} ${YELLOW}%-10s${RESET} : ${WHITE}%-50s${RESET} ${CYAN}║${RESET}\n" "Specs" "${CPU_CORES} vCPU / ${RAM_TOTAL} RAM"
    printf "${CYAN}╚═════════════════════════════════════════════════════════════════╝${RESET}\n"
    echo ""
}

draw_row() { printf "  ${BOLD}%-2s${RESET}  %b  ${WHITE}%-20s${RESET}  %b\n" "$1" "$2" "$3" "$4"; }

# --- 7. MAIN LOOP ---
while true; do
    draw_header
    echo -e "  ${DIM}ID  ST  TASK                  CURRENT STATE${RESET}"
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────${RESET}"
    
    draw_row "1" "$(stat_icon is_hostname_set)" "Hostname" "$(get_hostname_val)"
    draw_row "2" "$(stat_icon is_updated)" "System Update" "Update OS Packages"
    draw_row "3" "$(stat_icon is_user_ok)" "Sudo User" "$(get_user_val)"
    draw_row "4" "$(stat_icon is_ssh_ok)" "SSH Hardening" "$(get_ssh_val)"
    draw_row "5" "$(stat_icon is_fw_ok)" "Firewall Setup" "$(get_fw_val)"
    draw_row "6" "$(stat_icon is_swap_ok)" "Auto Swap (2x RAM)" "$(get_swap_val)"
    
    echo ""
    echo -e "${DIM}────────────────────────────────────────────────────────────────────────${RESET}"
    echo -e "  ${DIM}[q] Quit  |  [a] Select All${RESET}"
    echo ""
    read -p "  $ARROW Select ID (e.g., 1 4): " SELECTION
    
    if [[ "$SELECTION" == "q" ]]; then echo -e "\n  ${GREEN}Bye!${RESET}\n"; break; fi
    if [[ "$SELECTION" == "a" ]]; then SELECTION="1 2 3 4 5 6"; fi
    echo ""

    for TASK in $SELECTION; do
        case "$TASK" in
            1)
                echo -e "  ${CYAN}>> Setting Hostname...${RESET}"
                read -p "     New Name: " NEW_HOST
                if [ ! -z "$NEW_HOST" ]; then
                    hostnamectl set-hostname "$NEW_HOST"
                    if grep -q "127.0.1.1" /etc/hosts; then
                        sed -i "s/127.0.1.1.*/127.0.1.1 $NEW_HOST/g" /etc/hosts
                    else
                        echo "127.0.1.1 $NEW_HOST" >> /etc/hosts
                    fi
                    echo -e "     ${GREEN}Success.${RESET}"
                fi
                ;;
            2)
                echo -e "  ${CYAN}>> Updating System ($PKG_MGR)...${RESET}"
                eval "$UPDATE_CMD >/dev/null 2>&1"
                if [[ "$PKG_MGR" == "apt-get" ]]; then touch /var/lib/apt/periodic/update-success-stamp; fi
                echo -e "     ${GREEN}Success.${RESET}"
                ;;
            3)
                echo -e "  ${CYAN}>> Creating User...${RESET}"
                read -p "     Username: " NEW_USER
                if id "$NEW_USER" &>/dev/null; then
                    echo -e "     ${RED}User exists.${RESET}"
                else
                    if command -v adduser &>/dev/null; then
                         adduser --disabled-password --gecos "" "$NEW_USER" >/dev/null 2>&1
                    else
                         useradd -m -s /bin/bash "$NEW_USER" # Fallback for CentOS
                    fi
                    
                    # Add to sudo/wheel
                    if getent group sudo &>/dev/null; then usermod -aG sudo "$NEW_USER"; fi
                    if getent group wheel &>/dev/null; then usermod -aG wheel "$NEW_USER"; fi
                    
                    echo -e "     ${YELLOW}Set Password for $NEW_USER:${RESET}"
                    passwd "$NEW_USER"
                    
                    mkdir -p /home/$NEW_USER/.ssh
                    echo -e "     ${DIM}Paste PubKey (Enter to skip):${RESET}"
                    read -r PUB_KEY
                    if [ ! -z "$PUB_KEY" ]; then
                        echo "$PUB_KEY" >> /home/$NEW_USER/.ssh/authorized_keys
                        chmod 700 /home/$NEW_USER/.ssh
                        chmod 600 /home/$NEW_USER/.ssh/authorized_keys
                        chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
                        # SELinux Fix for SSH Keys (CentOS)
                        if command -v restorecon &>/dev/null; then restorecon -R -v /home/$NEW_USER/.ssh >/dev/null 2>&1; fi
                    fi
                    echo -e "     ${GREEN}Created.${RESET}"
                fi
                ;;
            4)
                echo -e "  ${CYAN}>> SSH Hardening...${RESET}"
                # Install openssh if missing
                if [ ! -f /etc/ssh/sshd_config ]; then $INSTALL_CMD openssh-server >/dev/null 2>&1; fi
                
                cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null
                read -p "     Port [22]: " SSH_PORT
                SSH_PORT=${SSH_PORT:-22}
                
                sed -i '/^Port/d' /etc/ssh/sshd_config
                sed -i '/^#Port/d' /etc/ssh/sshd_config
                echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
                sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                
                # Fix Ubuntu Socket
                if systemctl is-active --quiet ssh.socket; then
                    systemctl stop ssh.socket >/dev/null 2>&1
                    systemctl disable ssh.socket >/dev/null 2>&1
                fi
                
                # Fix CentOS SELinux for custom port
                if command -v semanage &>/dev/null && [[ "$SSH_PORT" != "22" ]]; then
                     echo -e "     ${YELLOW}Updating SELinux for Port $SSH_PORT...${RESET}"
                     semanage port -a -t ssh_port_t -p tcp $SSH_PORT >/dev/null 2>&1
                fi
                
                # Fix /run/sshd
                mkdir -p /run/sshd; chmod 0755 /run/sshd
                
                echo -e "     ${YELLOW}Restarting SSH...${RESET}"
                if sshd -t; then
                    systemctl restart "$SSH_SERVICE" >/dev/null 2>&1
                    echo -e "     ${GREEN}Success on Port $SSH_PORT.${RESET}"
                else
                    cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
                    echo -e "     ${RED}Config Error. Reverted.${RESET}"
                fi
                ;;
            5)
                echo -e "  ${CYAN}>> Configuring Firewall ($FIREWALL_TYPE)...${RESET}"
                CPORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}'); CPORT=${CPORT:-22}
                
                if [[ "$FIREWALL_TYPE" == "ufw" ]]; then
                    $INSTALL_CMD ufw >/dev/null 2>&1
                    ufw default deny incoming >/dev/null 2>&1
                    ufw default allow outgoing >/dev/null 2>&1
                    ufw allow $CPORT/tcp >/dev/null 2>&1
                    ufw allow 80/tcp >/dev/null 2>&1
                    ufw allow 443/tcp >/dev/null 2>&1
                    echo "y" | ufw enable >/dev/null 2>&1
                elif [[ "$FIREWALL_TYPE" == "firewalld" ]]; then
                    $INSTALL_CMD firewalld >/dev/null 2>&1
                    systemctl enable firewalld --now >/dev/null 2>&1
                    firewall-cmd --permanent --add-port=$CPORT/tcp >/dev/null 2>&1
                    firewall-cmd --permanent --add-service=http >/dev/null 2>&1
                    firewall-cmd --permanent --add-service=https >/dev/null 2>&1
                    firewall-cmd --reload >/dev/null 2>&1
                fi
                echo -e "     ${GREEN}Firewall Rules Updated.${RESET}"
                ;;
            6)
                echo -e "  ${CYAN}>> Creating Swap...${RESET}"
                if swapon --show | grep -q "file"; then
                    echo -e "     ${YELLOW}Exists.${RESET}"
                else
                    RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
                    SWAP_MB=$((RAM_MB * 2))
                    echo -e "     Creating ${SWAP_MB}MB..."
                    dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_MB status=none
                    chmod 600 /swapfile
                    mkswap /swapfile >/dev/null 2>&1
                    swapon /swapfile >/dev/null 2>&1
                    if ! grep -q "/swapfile" /etc/fstab; then echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
                    echo -e "     ${GREEN}Done.${RESET}"
                fi
                ;;
        esac
    done
    
    echo ""
    echo -e "  ${DIM}Press any key...${RESET}"
    read -n 1 -s -r
done
