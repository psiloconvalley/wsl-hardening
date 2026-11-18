# WSL Linux Baseline Hardening Utility

A lightweight security hardening utility for RHEL-based **WSL 2** distributions (**Rocky Linux**, **AlmaLinux**, **Fedora**, **Oracle Linux**).

By default, WSL distributions configure a single administrative user with passwordless `sudo` (`NOPASSWD: ALL`), permissive default file creation masks, and unrestricted execution of Windows host binaries. `harden-wsl.sh` locks down those defaults to create an isolated, non-elevated daily workspace.

## Features

1. **Verifies Admin Password:** Ensures your administrative account has a password set before modifying `sudoers` rules so you never lock yourself out.
2. **Enforces `sudo` Password Prompts:** Strips `NOPASSWD:` directives from `/etc/sudoers.d/` and validates syntax with `visudo -cf` before saving.
3. **Creates a Standard User Account:** Provisions a non-elevated daily user (without `wheel` or `sudo` group membership) and sets it as your default WSL login.
4. **Restricts File & Folder Permissions:** Applies `chmod 0700` to user home directories and sets a global `umask 077` in `/etc/profile.d/umask.sh`.
5. **Applies Kernel Hardening:** Configures `/etc/sysctl.d/99-hardening.conf` (`kptr_restrict=2`, `dmesg_restrict=1`, disabled ICMP redirects/source routing, and TCP SYN cookies).
6. **Disables WSL Windows Interop:** Configures `/etc/wsl.conf` to prevent Linux scripts from executing Windows `.exe` binaries (`cmd.exe`, `powershell.exe`, `clip.exe`).
7. **Automated Verification Audit:** Runs `[PASS]` / `[WARN]` checks against permissions, group memberships, and configuration files upon completion.

## Usage

1. **Download the script inside your WSL instance:**
   ```bash
   curl -fsSL https://githubusercontent.com -o harden-wsl.sh
   chmod +x harden-wsl.sh
   ```
2. **Run with `sudo`:**
   ```bash
   sudo ./harden-wsl.sh
   ```
3. **Restart WSL from Windows PowerShell** to apply `/etc/wsl.conf`:
   ```powershell
   wsl --shutdown
   ```
4. **Reopen your WSL terminal**—you will log directly into your new standard account.

## Emergency Recovery

If you ever mistype a username or forget your standard account password, open **Windows PowerShell** and log in directly as `root` to fix it:
```powershell
wsl -d <DistroName> -u root
```

## Disclaimer

Always review system-hardening scripts before running them with elevated (`sudo`) privileges. Tested on Rocky Linux 9 and AlmaLinux 9 on WSL 2.
