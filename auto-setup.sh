#!/bin/bash

# --- KONFIGURASI WARNA ---
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

# --- FUNGSI CEK STATUS (Updated: Suppress Errors) ---
# Menggunakan 2>/dev/null agar jika file/command tidak ada, error tidak muncul di layar
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

# --- LOGIKA UTAMA (LOOPING) ---

while true; do
    clear
    echo -e "${BLUE}┌──────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│         VPS SETUP WIZARD (LOOPING V2)        │${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────┘${RESET}"
    echo -e " Halo, ${BOLD}root${RESET}. Pilih tugas untuk dijalankan:\n"

    # Tampilkan Menu
    echo -e " ${BOLD}NO  STATUS   TASK NAME${RESET}"
    echo -e " ${BLUE}──  ──────   ─────────${RESET}"
    echo -e " ${BOLD}1.${RESET}  [ $(stat is_updated) ]   Update & Upgrade OS"
    echo -e " ${BOLD}2.${RESET}  [ $(stat is_user_ok) ]   Create User & Key"
    echo -e " ${BOLD}3.${RESET}  [ $(stat is_ssh_ok) ]   Harden SSH (Security)"
    echo -e " ${BOLD}4.${RESET}  [ $(stat is_fw_ok) ]   Setup Firewall (UFW)"
    echo -e " ${BOLD}5.${RESET}  [ $(stat is_f2b_ok) ]   Install Fail2Ban"
    echo -e " ${BOLD}6.${RESET}  [ $(stat is_tz_ok) ]   Set Timezone (WIB)"
    echo -e " ${BOLD}7.${RESET}  [ $(stat is_swap_ok) ]   Auto Swap (2x RAM)"
    echo -e " ${BOLD}0.${RESET}  [ EXIT ]   Keluar dari Script"
    echo ""
    echo -e "${CYAN}Tips: Pilih nomor (contoh: 1 3) lalu Enter.${RESET}"

    # Input User
    read -p " ➤ Pilihan Anda: " SELECTION

    # Cek Exit
    if [[ "$SELECTION" == "0" || "$SELECTION" == "q" ]]; then
        echo "Bye!"
        break
    fi

    # Jika user pilih 'a' (All)
    if [[ "$SELECTION" == "a" || "$SELECTION" == "A" ]]; then
        SELECTION="1 2 3 4 5 6 7"
    fi

    echo ""
    
    # Eksekusi Loop
    for TASK in $SELECTION; do
        case "$TASK" in
            1)
                echo -e "${YELLOW}>> [1/7] Updating System...${RESET}"
                apt-get update -qq && apt-get upgrade -y -qq
                touch /var/lib/apt/periodic/update-success-stamp
                ;;
            2)
                echo -e "${YELLOW}>> [2/7] Setup User...${RESET}"
                read -p "   Username baru: " NEW_USER
                if id "$NEW_USER" &>/dev/null; then
                    echo -e "${RED}   User sudah ada.${RESET}"
                else
                    adduser --gecos "" "$NEW_USER" > /dev/null
                    usermod -aG sudo "$NEW_USER"
                    mkdir -p /home/$NEW_USER/.ssh
                    # Opsional: Input Key
                    # ... (Kode user sama seperti sebelumnya) ...
                    echo -e "${GREEN}   User $NEW_USER dibuat.${RESET}"
                fi
                ;;
            3)
                echo -e "${YELLOW}>> [3/7] Hardening SSH...${RESET}"
                if [ ! -f /etc/ssh/sshd_config ]; then
                    echo -e "${RED}   SSH Server belum terinstall!${RESET}"
                else
                    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
                    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                    systemctl restart ssh
                    echo -e "${GREEN}   SSH diamankan.${RESET}"
                fi
                ;;
            4)
                echo -e "${YELLOW}>> [4/7] Config Firewall...${RESET}"
                # Cek apakah ufw ada
                if ! command -v ufw &> /dev/null; then
                    echo -e "${YELLOW}   Install UFW dulu...${RESET}"
                    apt-get install ufw -y -qq >/dev/null
                fi
                ufw default deny incoming > /dev/null
                ufw default allow outgoing > /dev/null
                ufw allow ssh > /dev/null
                ufw allow http > /dev/null
                ufw allow https > /dev/null
                echo "y" | ufw enable > /dev/null
                echo -e "${GREEN}   UFW Aktif.${RESET}"
                ;;
            5)
                echo -e "${YELLOW}>> [5/7] Installing Fail2Ban...${RESET}"
                apt-get install fail2ban -y -qq > /dev/null
                cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
                systemctl enable fail2ban --now > /dev/null
                echo -e "${GREEN}   Fail2Ban Aktif.${RESET}"
                ;;
            6)
                echo -e "${YELLOW}>> [6/7] Setting Timezone...${RESET}"
                timedatectl set-timezone Asia/Jakarta
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
                    fallocate -l "${SWAP}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$SWAP status=none
                    chmod 600 /swapfile
                    mkswap /swapfile > /dev/null
                    swapon /swapfile
                    if ! grep -q "/swapfile" /etc/fstab; then echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
                    echo -e "${GREEN}   Swap Aktif.${RESET}"
                fi
                ;;
        esac
    done
    
    echo ""
    echo -e "${BLUE}──────────────────────────────────────────────${RESET}"
    read -n 1 -s -r -p "Tekan sembarang tombol untuk kembali ke menu..."
    # Script akan kembali ke atas (while loop)
done
