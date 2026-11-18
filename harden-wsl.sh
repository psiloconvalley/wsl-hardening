#!/usr/bin/env bash
set -euo pipefail

# 1. Verify root / elevated privileges
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: Elevated privileges required. Run with sudo:"
   echo "  sudo ./harden-wsl.sh"
   exit 1
fi

clear
echo "=================================================================="
echo "             WSL Linux Baseline Hardening Utility"
echo "=================================================================="
echo "This script applies standard Linux least-privilege hardening:"
echo "  1. Enforces password authentication for elevated (sudo) commands"
echo "  2. Creates a standard user account (non-elevated privileges)"
echo "  3. Enforces private default file permissions (umask 077 / 700)"
echo "  4. Applies kernel sysctl protections & disables WSL Windows interop"
echo "=================================================================="
echo ""

# 2. Auto-detect existing administrative account
ADMIN_USER="${SUDO_USER:-}"
if [[ -z "$ADMIN_USER" ]] || ! id "$ADMIN_USER" &>/dev/null; then
    read -rp "Step 1: Enter your EXISTING administrative username: " ADMIN_USER
else
    echo "Step 1: Detected administrative account: '$ADMIN_USER'"
fi

# 3. Prompt for the new standard (non-elevated) user account
echo ""
echo "Step 2: Configure your NEW standard user account."
echo "  - Role : Default daily login with standard, non-elevated privileges (no sudo)."
echo "  - Rules: Lowercase letters, digits, or underscores only; no spaces (e.g., sandbox, daily)."
echo ""
read -rp "Enter username for the new standard account: " SANDBOX_USER

# Validate username against standard Linux naming rules
if [[ -z "$SANDBOX_USER" || "$SANDBOX_USER" == "$ADMIN_USER" || ! "$SANDBOX_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "ERROR: Invalid username. Use lowercase letters/numbers only, and choose a name different from '$ADMIN_USER'."
    exit 1
fi

echo ""
echo "--- Applying Hardening Configuration ---"

# 4. Verify admin password exists before removing NOPASSWD
if passwd -S "$ADMIN_USER" | grep -qE "NP|LK"; then
    echo "[1/6] Administrative account '$ADMIN_USER' has no password set. Configure one now:"
    passwd "$ADMIN_USER"
else
    echo "[1/6] Administrative account password verified."
fi

# 5. Strip NOPASSWD directives safely using visudo validation
echo "[2/6] Enforcing password prompts for sudo elevation..."
for file in /etc/sudoers.d/*; do
    if [[ -f "$file" ]] && grep -q "NOPASSWD:" "$file"; then
        cp "$file" "${file}.bak"
        sed -i 's/NOPASSWD:[[:space:]]*//g' "$file"
        if visudo -cf "$file" &>/dev/null; then
            rm -f "${file}.bak"
        else
            mv "${file}.bak" "$file"
            echo "      [WARN] Syntax validation failed on $file; original restored."
        fi
    fi
done
# 6. Provision standard (non-elevated) user account
echo "[3/6] Provisioning standard user account '$SANDBOX_USER'..."
if ! id "$SANDBOX_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$SANDBOX_USER"
    echo "      Set password for standard account '$SANDBOX_USER':"
    passwd "$SANDBOX_USER"
else
    echo "      Account '$SANDBOX_USER' already exists; preserving existing user."
    if passwd -S "$SANDBOX_USER" | grep -qE "NP|LK"; then
        echo "      Account '$SANDBOX_USER' has no password set. Configure one now:"
        passwd "$SANDBOX_USER"
    fi
fi


# 7. Restrict home directory permissions (mode 0700)
echo "[4/6] Restricting home directory permissions (chmod 0700)..."
chmod 0700 "/home/$SANDBOX_USER"
[[ -d "/home/$ADMIN_USER" ]] && chmod 0700 "/home/$ADMIN_USER"

# 8. Configure global file mode creation mask (umask 077)
echo "[5/6] Configuring global umask 077 (/etc/profile.d/umask.sh)..."
echo "umask 077" > /etc/profile.d/umask.sh
chmod 0644 /etc/profile.d/umask.sh

# 9. Apply kernel sysctl parameters & configure /etc/wsl.conf
echo "[6/6] Applying kernel sysctl parameters and disabling WSL interop..."
mkdir -p /etc/sysctl.d
cat << 'EOF' > /etc/sysctl.d/99-hardening.conf
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
EOF
sysctl --system &>/dev/null || true

cat << EOF > /etc/wsl.conf
[user]
default=$SANDBOX_USER

[interop]
enabled=false
appendWindowsPath=false
EOF

# 10. Automated Post-Configuration Audit
echo ""
echo "--- Running Automated Verification Audit ---"

if grep -rq "^[^#]*NOPASSWD:" /etc/sudoers.d/ 2>/dev/null; then
    echo "  [WARN] Active NOPASSWD directive still detected in /etc/sudoers.d/"
else
    echo "  [PASS] sudo elevation requires password authentication"
fi

if id -nG "$SANDBOX_USER" | grep -qwE "wheel|sudo"; then
    echo "  [WARN] '$SANDBOX_USER' still belongs to an elevated group"
else
    echo "  [PASS] '$SANDBOX_USER' verified as standard non-elevated user"
fi

if [[ "$(stat -c "%a" "/home/$SANDBOX_USER")" == "700" ]]; then
    echo "  [PASS] Home directory '/home/$SANDBOX_USER' restricted (mode 0700)"
else
    echo "  [WARN] Home directory mode mismatch on '/home/$SANDBOX_USER'"
fi

if grep -q "enabled=false" /etc/wsl.conf && grep -q "default=$SANDBOX_USER" /etc/wsl.conf; then
    echo "  [PASS] /etc/wsl.conf configured (default=$SANDBOX_USER, interop=false)"
else
    echo "  [WARN] /etc/wsl.conf verification failed"
fi

echo ""
echo "=================================================================="
echo "                   HARDENING SETUP COMPLETE"
echo "=================================================================="
echo "  Administrative User : $ADMIN_USER (elevated / sudo)"
echo "  Standard User       : $SANDBOX_USER (default login / non-elevated)"
echo "------------------------------------------------------------------"
echo "REQUIRED FINAL STEP:"
echo "  1. Open Windows PowerShell and execute:  wsl --shutdown"
echo "  2. Relaunch this WSL distribution."
echo ""
echo "MANUAL RUNTIME CHECKS (AFTER RESTART):"
echo "  whoami                  -> expected: $SANDBOX_USER"
echo "  umask                   -> expected: 0077"
echo "  clip.exe                -> expected: command not found"
echo "  ls /home/$ADMIN_USER    -> expected: Permission denied"
echo ""
echo "ELEVATING TO ADMIN LATER:"
echo "  Execute:  su - $ADMIN_USER"
echo "=================================================================="