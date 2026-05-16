# Windows & Kali Linux SSH Admin Toolkit

Windows & Kali Linux SSH Admin Toolkit is a cross-platform SSH administration toolkit designed for managing OpenSSH Server on Windows and `ssh/sshd` services on Kali Linux / Debian-based Linux systems.

This project includes two separate menu-based scripts:

- PowerShell-based SSH administration panel for Windows OpenSSH Server
- Bash-based SSH administration panel for Kali Linux / Linux systems

The toolkit helps administrators and learners perform common SSH management tasks such as checking service status, detecting active SSH ports, changing SSH configuration, reviewing active SSH sessions, and managing basic firewall rules.

---

## Documentation

🇹🇷 Türkçe dokümantasyon:  
[README_TURKISH.md](README_TURKISH.md)

🇬🇧 English documentation:  
[README_ENGLISH.md](README_ENGLISH.md)

---

## Main Features

- SSH service status control
- Active SSH port detection
- SSH port configuration
- `sshd_config` backup and validation
- Active SSH session listing
- Selected SSH session termination
- Windows Firewall SSH rule management
- UFW / firewalld status review
- IP-based SSH allow / deny operations
- Menu-based usage for easier administration

---

## Project Structure

```text
ssh-script-windows-kali-linux/
│
├── windows/
│   └── windows-openssh-script.ps1
│
├── linux/
│   └── linux-openssh.sh
│
├── README.md
├── README_TURKISH.md
├── README_ENGLISH.md
└── LICENSE


## Security Notice

This toolkit is intended only for systems that you own, manage, or are explicitly authorized to administer.

Changing SSH ports, stopping SSH services, modifying firewall rules, or terminating active SSH sessions may disconnect existing remote connections. Always make sure you have alternative access before applying critical changes on remote systems.

This project is designed for system administration, learning, and lab usage. It is not intended for unauthorized access, exploitation, or bypassing security controls.
