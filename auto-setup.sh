#!/bin/bash

# ==========================================
# VPS SETUP WIZARD (V3 - STABLE)
# Fitur: Auto-Root Check, Looping Menu, Error Suppressed
# ==========================================

# --- 1. CEK ROOT (WAJIB) ---
if [[ $EUID -ne 0 ]]; then
   echo "-------------------------------------------------------"
   echo -e "\e[31m[ERROR] Script ini membutuhkan akses ROOT!\e[0m"
   echo "-------------------------------------------------------"
   echo "Silakan jalankan ulang dengan perintah sudo:"
   echo ""
   echo "    sudo $0"
   echo ""
   exit 1
fi

# --- 2. KONFIGURASI WARNA ---
BOLD="\e[1m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
RESET="\e[0m"

# Simbol Status
CHECK_MARK="${GREEN}✔${RESET}"
CROSS_MARK="${RED}✘${RESET}"

# --- 3. FUNGSI CEK STATUS (Silent Error) ---
# Menggunakan 2>/dev/null agar tampilan tetap bersih jika file belum ada
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

# --- 4. LOGIKA UTAMA (LOOPING) ---

while true; do
    clear
    echo -e "${BLUE}┌──────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│         VPS SETUP WIZARD (V3 - STABLE)       │${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────┘${RESET}"
    echo -e " Halo, ${BOLD}root${RESET}. Sistem siap dikonfigurasi.\n"

    # Tampilkan Menu Dashboard
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
    echo -e "${CYAN}Tips: Pilih nomor (contoh: 1 3 7) lalu Enter.${RESET}"

    # Input User
    read -p " ➤ Pilihan Anda: " SELECTION

    # Cek Exit
    if [[ "$SELECTION" == "0" || "$SELECTION" == "q" ]]; then
        clear
        echo "Bye! Setup selesai."
        break
    fi

    # Jika user pilih 'a' (All)
    if [[ "$SELECTION" == "a" || "$SELECTION" == "A" ]]; then
        SELECTION="1 2 3 4 5 6 7"
    fi

    echo ""
    
    # Eksekusi Loop Task
    for TASK in $SELECTION; do
        case "$TASK" in
            1)
                echo -e "${YELLOW}>> [1/7] Updating System...${RESET}"
                # Menggunakan -qq untuk mengurangi output spam
                apt-get update -qq && apt-get upgrade -y -qq
                apt-get autoremove -y -qq
                touch /var/lib/apt/periodic/update-success-stamp
                echo -e "${GREEN}   Update Selesai.${RESET}"
                ;;
            2)
                echo -e "${YELLOW}>> [2/7] Setup User...${RESET}"
                read -p "   Username baru: " NEW_USER
                if id "$NEW_USER" &>/dev/null; then
                    echo -e "${RED}   User $NEW_USER sudah ada.${RESET}"
                else
                    adduser --gecos "" "$NEW_USER" > /dev/null
                    usermod -aG sudo "$NEW_USER"
                    mkdir -p /home/$NEW_USER/.ssh
                    echo -e "${CYAN}   Paste SSH Public Key (Enter jika nanti saja):${RESET}"
                    read -r PUB_KEY
                    if [ ! -z "$PUB_KEY" ]; then
                        echo "$PUB_KEY" >> /home/$NEW_USER/.ssh/authorized_keys
                        chmod 700 /home/$NEW_USER/.ssh
                        chmod 600 /home/$NEW_USER/.ssh/authorized_keys
                        chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
                        echo -e "${GREEN}   SSH Key tersimpan.${RESET}"
                    fi
                    echo -e "${GREEN}   User $NEW_USER berhasil dibuat.${RESET}"
                fi
                ;;
            3)
                echo -e "${YELLOW}>> [3/7] Hardening SSH...${RESET}"
                if [ ! -f /etc/ssh/sshd_config ]; then
                    echo -e "${RED}   SSH Server belum terinstall!${RESET}"
                    echo -e "   Menginstall openssh-server..."
                    apt-get install openssh-server -y -qq
                fi
                cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
                sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
                sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                systemctl restart ssh
                echo -e "${GREEN}   SSH diamankan (No Root, No Password).${RESET}"
                ;;
            4)
                echo -e "${YELLOW}>> [4/7] Config Firewall...${RESET}"
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
                echo -e "${GREEN}   UFW Aktif & Dikonfigurasi.${RESET}"
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
                echo -e "${GREEN}   Timezone set: Asia/Jakarta (WIB).${RESET}"
                ;;
            7)
                echo -e "${YELLOW}>> [7/7] Checking Swap...${RESET}"
                if swapon --show | grep -q "file"; then
                    echo -e "${GREEN}   Swap sudah ada. Skip.${RESET}"
                else
                    RAM=$(free -m | awk '/Mem:/ {print $2}')
                    SWAP=$((RAM * 2))
                    echo "   Membuat Swap ${SWAP}MB (2x RAM)..."
                    fallocate -l "${SWAP}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$SWAP status=none
                    chmod 600 /swapfile
                    mkswap /swapfile > /dev/null
                    swapon /swapfile
                    if ! grep -q "/swapfile" /etc/fstab; then echo '/swapfile none swap sw 0 0' >> /etc/fstab; fi
                    echo -e "${GREEN}   Swap File Aktif.${RESET}"
                fi
                ;;
        esac
    done
    
    echo ""
    echo -e "${BLUE}──────────────────────────────────────────────${RESET}"
    read -n 1 -s -r -p "Tekan sembarang tombol untuk kembali ke menu..."
    # Script akan kembali ke atas (while true) setelah ditekan
done
