
---

# English README Description

```md
# SSH Admin Toolkit

SSH Admin Toolkit is a menu-based system administration tool designed to manage Windows OpenSSH Server and Linux/Kali sshd services.

This project was developed to simplify common SSH administration tasks such as checking SSH service status, detecting the active SSH port, changing the SSH port, backing up and testing the `sshd_config` file, viewing active SSH sessions, and managing basic firewall rules.

The toolkit includes two separate scripts:

- A PowerShell-based OpenSSH management panel for Windows
- A Bash-based sshd management panel for Linux/Kali

## Purpose

The purpose of this project is to collect frequently used SSH administration tasks under a single interactive menu and provide a practical management tool for system administrators, cybersecurity students, lab users, and people learning Windows/Linux service administration.

## Features

### Windows OpenSSH Panel

- Displays OpenSSH Server service status
- Checks whether the SSH service is active or inactive
- Detects the active SSH port
- Helps change the SSH listening port
- Backs up and tests the `sshd_config` file
- Lists active SSH connections
- Helps terminate selected SSH sessions
- Manages SSH port rules in Windows Firewall
- Supports allowing or blocking specific IP addresses

### Linux/Kali SSH Panel

- Displays `ssh` / `sshd` service status
- Automatically detects the SSH service name
- Shows active SSH port or ports
- Helps change the SSH listening port
- Backs up and tests the `sshd_config` file
- Lists active SSH sessions and related process information
- Helps terminate selected SSH sessions by PID
- Displays UFW and firewalld status
- Simplifies IP-based allow/deny rules through UFW

## Use Cases

This tool can be used for the following scenarios:

- Checking whether the SSH service is running
- Finding the actual SSH listening port
- Safely changing the SSH port
- Managing SSH access through firewall rules
- Reviewing active SSH connections
- Learning SSH service management in a test/lab environment
- Practicing Windows and Linux system administration

## Security Notice

This tool must only be used on systems that you own, manage, or are explicitly authorized to administer.

Operations such as stopping the SSH service, changing the SSH port, deleting firewall rules, or terminating active SSH sessions may disconnect your current remote session. When working on remote servers, always make sure you have an alternative access method before making critical changes.

This project is not designed for attacks, unauthorized access, or bypassing security controls. Its purpose is system administration, service control, and educational/lab usage.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Recommended Usage

Run the Windows script from an elevated PowerShell session:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
.\win-openssh-panel.ps1
