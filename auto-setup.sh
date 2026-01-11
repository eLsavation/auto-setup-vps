#!/bin/bash

# ==========================================
# VPS SETUP WIZARD (V4 - CLEAN & SILENT)
# Fitur: Silent Install, Auto-Root, Looping
# ==========================================

# --- 1. CEK ROOT ---
if [[ $EUID -ne 0 ]]; then
   echo "Error: Jalankan script ini dengan 'sudo'!"
   exit 1
fi

# --- 2. WARNA ---
BOLD="\e[1m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# Simbol
CHECK_MARK="${GREEN}✔${RESET}"
CROSS_MARK="${RED}✘${RESET}"

# --- 3. FUNGSI CEK STATUS (Silent) ---
is_updated() { [ -f /var/lib/apt/periodic/update-success-stamp ] && find /var/lib/apt/periodic/update-success-stamp -mtime -1 2>/dev/null | grep -q .; }
is_user_ok() { awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd 2>/dev/null | grep -q .; }
is_ssh_ok()  { [ -f /etc/ssh/sshd_config ] && grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config 2>/dev/null; }
is_fw_ok()   { command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; }
is_f2b_ok()  { systemctl is-active --quiet fail2ban 2>/dev/null; }
is_tz_ok()   { timedatectl 2>/dev/null | grep -q "Asia/Jakarta"; }
is_swap_ok() { swapon --show --noheadings 2>/dev/null | grep -q "."; }

stat() {
    if $1; then echo -e "$CHECK_MARK"; else echo -e "$CROSS_MARK"; fi
}

# --- 4. LOGIKA UTAMA ---

while true; do
    clear
    echo -e "${BLUE}┌──────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│           VPS SETUP WIZARD (CLEAN)           │${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────┘${RESET}"
    echo -e " Halo, ${BOLD}root${RESET}. Pilih tugas:\n"

    echo -e " ${BOLD}NO  STATUS   TASK NAME${RESET}"
    echo -e " ${BLUE}──  ──────   ─────────${RESET}"
    echo -e " ${BOLD}1.${RESET}  [ $(stat is_updated) ]   Update & Upgrade OS"
    echo -e " ${BOLD}2.${RESET}  [ $(stat is_user_ok) ]   Create User & Key"
    echo -e " ${BOLD}3.${RESET}  [ $(stat is_ssh_ok) ]   Harden SSH (Security)"
    echo -e " ${BOLD}4.${RESET}  [ $(stat is_fw_ok) ]   Setup Firewall (UFW)"
    echo -e " ${BOLD}5.${RESET}  [ $(stat is_f2b_ok) ]   Install Fail2Ban"
    echo -e " ${BOLD}6.${RESET}  [ $(stat is_tz_ok) ]   Set Timezone (WIB)"
    echo -e " ${BOLD}7.${RESET}  [ $(stat is_swap_ok) ]   Auto Swap (2x RAM)"
    echo -e " ${BOLD}0.${RESET}  [ EXIT ]   Keluar"
    echo ""
    echo -e "${CYAN}Tips: Pilih nomor (contoh: 1 3 7) lalu Enter.${RESET}"

    read -p " ➤ Pilihan Anda: " SELECTION

    if [[ "$SELECTION" == "0" || "$SELECTION" == "q" ]]; then
        clear; echo "Bye!"; break
    fi

    if [[ "$SELECTION" == "a" || "$SELECTION" == "A" ]]; then
        SELECTION="1 2 3 4 5 6 7"
    fi

    echo ""
    
    for TASK in $SELECTION; do
        case "$TASK" in
            1)
                echo -e "${YELLOW}>> [1/7] Updating System...${RESET}"
                # Redirect output ke /dev/null agar benar-benar silent
                apt-get update -y > /dev/null 2>&1
                apt-get upgrade -y > /dev/null 2>&1
                apt-get autoremove -y > /dev/null 2>&1
                touch /var/lib/apt/periodic/update-success-stamp
                echo -e "${GREEN}   Selesai.${RESET}"
                ;;
            2)
                echo -e "${YELLOW}>> [2/7] Setup User...${RESET}"
                read -p "   Username baru: " NEW_USER
                if id "$NEW_USER" &>/dev/null; then
                    echo -e "${RED}   User sudah ada.${RESET}"
                else
                    adduser --gecos "" "$NEW_USER" > /dev/null 2>&1
                    usermod -aG sudo "$NEW_USER"
                    mkdir -p /home/$NEW_USER/.ssh
                    echo -e "${CYAN}   Paste SSH Public Key (Enter jika skip):${RESET}"
                    read -r PUB_KEY
                    if [ ! -z "$PUB_KEY" ]; then
                        echo "$PUB_KEY" >> /home/$NEW_USER/.ssh/authorized_keys
                        chmod 700 /home/$NEW_USER/.ssh
                        chmod 600 /home/$NEW_USER/.ssh/authorized_keys
                        chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
                        echo -e "${GREEN}   SSH Key disimpan.${RESET}"
                    fi
                    echo -e "${GREEN}   User dibuat.${RESET}"
                fi
                ;;
            3)
                echo -e "${YELLOW}>> [3/7] Hardening SSH...${RESET}"
                # Install silent jika belum ada
                if [ ! -f /etc/ssh/sshd_config ]; then
                    echo -e "   Menginstall OpenSSH Server..."
                    apt-get install openssh-server -y > /dev/null 2>&1
                fi
                
                # Edit config silent
                cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak 2>/dev/null
                sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null
                sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config 2>/dev/null
                sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null
                sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null
                
                # Restart silent
                systemctl restart ssh > /dev/null 2>&1
                echo -e "${GREEN}   SSH diamankan (No Root, No Pass).${RESET}"
                ;;
            4)
                echo -e "${YELLOW}>> [4/7] Config Firewall...${RESET}"
                if ! command -v ufw &> /dev/null; then
                    echo "   Menginstall UFW..."
                    apt-get install ufw -y > /dev/null 2>&1
                fi
                ufw default deny incoming > /dev/null 2>&1
                ufw default allow outgoing > /dev/null 2>&1
                ufw allow ssh > /dev/null 2>&1
                ufw allow http > /dev/null 2>&1
                ufw allow https > /dev/null 2>&1
                echo "y" | ufw enable > /dev/null 2>&1
                echo -e "${GREEN}   UFW Aktif.${RESET}"
                ;;
            5)
                echo -e "${YELLOW}>> [5/7] Installing Fail2Ban...${RESET}"
                apt-get install fail2ban -y > /dev/null 2>&1
                cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local 2>/dev/null
                systemctl enable fail2ban --now > /dev/null 2>&1
                echo -e "${GREEN}   Fail2Ban Aktif.${RESET}"
                ;;
            6)
                echo -e "${YELLOW}>> [6/7] Setting Timezone...${RESET}"
                timedatectl set-timezone Asia/Jakarta 2>/dev/null
                echo -e "${GREEN}   Timezone: WIB.${RESET}"
                ;;
            7)
                echo -e "${YELLOW}>> [7/7] Checking Swap...${RESET}"
                if swapon --show | grep -q "file"; then
                    echo -e "${GREEN}   Swap sudah ada.${RESET}"
                else
                    RAM=$(free -m | awk '/Mem:/ {print $2}')
                    SWAP=$((RAM * 2))
                    echo "   Membuat Swap ${SWAP}MB..."
                    fallocate -l "${SWAP}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=$SWAP status=none
                    chmod 600 /swapfile
                    mkswap /swapfile > /dev/null 2>&1
                    swapon /swapfile > /dev/null 2>&1
                    if ! grep -q "/swapfile" /etc/fstab; then echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
                    echo -e "${GREEN}   Swap Aktif.${RESET}"
                fi
                ;;
        esac
    done
    
    echo ""
    echo -e "${BLUE}──────────────────────────────────────────────${RESET}"
    read -n 1 -s -r -p "Tekan tombol apapun untuk kembali..."
done
