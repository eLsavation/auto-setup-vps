#!/bin/bash

# ============================================================
# MODERN VPS SETUP (Powered by Charm.sh 'gum')
# ============================================================

# 1. Pastikan Root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Script ini harus dijalankan sebagai root (sudo)." 
   exit 1
fi

# 2. Auto-Install GUM (UI Tool)
if ! command -v gum &> /dev/null; then
    echo "Installing Gum for modern UI..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list
    apt-get update && apt-get install gum -y
fi

# --- CONFIG & HELPERS ---

LOG_FILE="/var/log/vps_setup.log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Fungsi Style Text
style_header() {
    gum style --foreground 212 --border-foreground 212 --border double --align center --width 50 --margin "1 2" --padding "2 4" "$1"
}

style_success() {
    gum style --foreground 82 "✅ $1"
}

style_error() {
    gum style --foreground 196 "❌ $1"
}

# --- CHECK FUNCTIONS (Return formatted strings) ---

get_status() {
    # $1 = Nama Task, $2 = Function Check
    if $2; then
        echo "✅ $1 (Sudah Config)"
    else
        echo "⬜ $1 (Belum Config)"
    fi
}

check_is_updated() {
    [ -f /var/lib/apt/periodic/update-success-stamp ] && find /var/lib/apt/periodic/update-success-stamp -mtime -1 | grep -q .
}

check_is_user_exist() {
    awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd | grep -q .
}

check_is_ssh_hardened() {
    grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config
}

check_is_firewall_active() {
    ufw status | grep -q "Status: active"
}

check_is_fail2ban_active() {
    systemctl is-active --quiet fail2ban
}

check_is_timezone_set() {
    timedatectl | grep -q "Asia/Jakarta"
}

check_is_swap_exist() {
    swapon --show --noheadings | grep -q "."
}

# --- ACTION FUNCTIONS ---

task_update() {
    gum spin --spinner dot --title "Updating & Upgrading System..." -- \
    bash -c "apt-get update && apt-get upgrade -y && apt-get autoremove -y && touch /var/lib/apt/periodic/update-success-stamp"
    style_success "System Updated."
    log "System Update Selesai"
}

task_user() {
    echo ""
    gum style --foreground 99 " SETUP USER BARU "
    USERNAME=$(gum input --placeholder "Masukkan Username Baru (bukan root)")
    
    if [ -z "$USERNAME" ]; then style_error "Username kosong, skip."; return; fi
    
    if id "$USERNAME" &>/dev/null; then
        style_error "User $USERNAME sudah ada."
    else
        adduser --gecos "" "$USERNAME"
        usermod -aG sudo "$USERNAME"
        
        # SSH Key Input (Multiline)
        echo ""
        gum style --foreground 212 "Masukkan SSH Public Key (Paste lalu tekan Ctrl+D):"
        PUB_KEY=$(gum write --placeholder "ssh-rsa AAAA...")
        
        if [ ! -z "$PUB_KEY" ]; then
            mkdir -p /home/$USERNAME/.ssh
            echo "$PUB_KEY" >> /home/$USERNAME/.ssh/authorized_keys
            chmod 700 /home/$USERNAME/.ssh
            chmod 600 /home/$USERNAME/.ssh/authorized_keys
            chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
            style_success "SSH Key ditambahkan."
        fi
        style_success "User $USERNAME berhasil dibuat."
        log "User $USERNAME created"
    fi
}

task_ssh() {
    gum spin --spinner points --title "Hardening SSH..." -- sleep 2
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart ssh
    style_success "SSH Hardening Selesai (Root Login & Password Auth OFF)"
    log "SSH Hardened"
}

task_firewall() {
    gum spin --spinner line --title "Setting up UFW Firewall..." -- sleep 1
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow http
    ufw allow https
    echo "y" | ufw enable > /dev/null
    style_success "Firewall Aktif (SSH, HTTP, HTTPS Allowed)"
    log "Firewall Activated"
}

task_fail2ban() {
    gum spin --spinner globe --title "Installing Fail2Ban..." -- \
    bash -c "apt-get install fail2ban -y && cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local && systemctl enable fail2ban && systemctl start fail2ban"
    style_success "Fail2Ban Installed & Running"
    log "Fail2Ban Installed"
}

task_timezone() {
    gum spin --spinner moon --title "Setting Timezone..." -- timedatectl set-timezone Asia/Jakarta
    style_success "Timezone set to Asia/Jakarta"
    log "Timezone Set"
}

task_swap() {
    if swapon --show | grep -q "file"; then
        style_success "Swap file sudah ada."
        return
    fi
    
    TOTAL_RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
    SWAP_SIZE_MB=$((TOTAL_RAM_MB * 2))
    
    gum confirm "RAM: ${TOTAL_RAM_MB}MB. Buat Swap ${SWAP_SIZE_MB}MB?" && {
        gum spin --spinner pulse --title "Creating Swap File (${SWAP_SIZE_MB}MB)..." -- \
        bash -c "fallocate -l ${SWAP_SIZE_MB}M /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB; chmod 600 /swapfile; mkswap /swapfile; swapon /swapfile"
        
        if ! grep -q "/swapfile" /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
        style_success "Swap ${SWAP_SIZE_MB}MB Created."
        log "Swap Created"
    } || style_error "Swap creation cancelled."
}

# --- MAIN MENU ---

clear
style_header "SERVER AUTOMATION KIT"

echo "Mendeteksi konfigurasi saat ini..."
# Prepare Menu Items based on current state
OPT_UPDATE=$(get_status "Update System" check_is_updated)
OPT_USER=$(get_status "Create User & Key" check_is_user_exist)
OPT_SSH=$(get_status "Harden SSH Security" check_is_ssh_hardened)
OPT_FIREWALL=$(get_status "Setup Firewall" check_is_firewall_active)
OPT_F2B=$(get_status "Install Fail2Ban" check_is_fail2ban_active)
OPT_TZ=$(get_status "Set Timezone WIB" check_is_timezone_set)
OPT_SWAP=$(get_status "Auto Swap (2x RAM)" check_is_swap_exist)

echo ""
gum style --foreground 244 "Gunakan [SPASI] untuk memilih, [ENTER] untuk konfirmasi."

# GUM CHOOSE: The Interactive Part
SELECTED=$(gum choose --no-limit --cursor-prefix "👉 " --selected.foreground 212 --height 15 \
    "$OPT_UPDATE" \
    "$OPT_USER" \
    "$OPT_SSH" \
    "$OPT_FIREWALL" \
    "$OPT_F2B" \
    "$OPT_TZ" \
    "$OPT_SWAP")

if [ -z "$SELECTED" ]; then
    style_error "Tidak ada yang dipilih. Keluar."
    exit 0
fi

echo ""
style_header "STARTING TASKS"

# Process Selection
# Kita grep string output dari gum choose
echo "$SELECTED" | while read -r item; do
    case "$item" in
        *"Update System"*) task_update ;;
        *"Create User"*) task_user ;;
        *"Harden SSH"*) task_ssh ;;
        *"Setup Firewall"*) task_firewall ;;
        *"Install Fail2Ban"*) task_fail2ban ;;
        *"Set Timezone"*) task_timezone ;;
        *"Auto Swap"*) task_swap ;;
    esac
done

echo ""
style_header "ALL DONE! 🚀"
