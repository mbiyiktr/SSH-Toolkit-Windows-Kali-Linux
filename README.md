# Windows & Kali Linux SSH Admin Toolkit

Windows & Kali Linux SSH Admin Toolkit is a cross-platform SSH administration toolkit designed for managing OpenSSH Server on Windows and `ssh/sshd` services on Kali Linux / Debian-based Linux systems.

This project includes two separate menu-based scripts:

- PowerShell-based SSH administration panel for Windows OpenSSH Server
- Bash-based SSH administration panel for Kali Linux / Linux systems

The toolkit helps administrators and learners perform common SSH management tasks such as checking service status, detecting active SSH ports, changing SSH configuration, reviewing active SSH sessions, and managing basic firewall rules.

<img width="954" height="698" alt="ss-linux" src="https://github.com/user-attachments/assets/7d8885c5-7147-4159-93c6-c351487a5d78" />

---

## Video

<p align="center">
  <a href="https://youtu.be/taS7BoFwp1Q">
    <img src="https://img.youtube.com/vi/taS7BoFwp1Q/maxresdefault.jpg" width="700">
  </a>
</p>

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
