# SSH Admin Toolkit

SSH Admin Toolkit, Windows OpenSSH Server ve Linux/Kali sshd servislerini yönetmek için hazırlanmış menü tabanlı bir sistem yönetim aracıdır.

Bu proje; SSH servis durumunu kontrol etmek, aktif SSH portunu tespit etmek, SSH portunu değiştirmek, `sshd_config` dosyasını yedeklemek/test etmek, aktif SSH oturumlarını görüntülemek ve temel firewall işlemlerini kolaylaştırmak amacıyla geliştirilmiştir.

Araç hem Windows hem de Linux sistemlerde çalışan iki ayrı script içerir:

- Windows için PowerShell tabanlı OpenSSH yönetim paneli
- Linux/Kali için Bash tabanlı sshd yönetim paneli

## Amaç

Bu projenin amacı, SSH yönetimi sırasında sık kullanılan işlemleri tek bir menü altında toplamak ve özellikle sistem yöneticileri, siber güvenlik öğrencileri, laboratuvar ortamında çalışan kullanıcılar ve Linux/Windows servis yönetimini öğrenen kişiler için pratik bir yönetim aracı sunmaktır.

## Özellikler

### Windows OpenSSH Paneli

- OpenSSH Server servis durumunu görüntüler
- SSH servisinin aktif/pasif durumunu kontrol eder
- Aktif SSH portunu tespit eder
- SSH portunu değiştirmeye yardımcı olur
- `sshd_config` dosyasını yedekler ve test eder
- Aktif SSH bağlantılarını listeler
- Belirli SSH oturumlarını sonlandırmaya yardımcı olur
- Windows Firewall üzerinde SSH port izinlerini yönetir
- Belirli IP adreslerine izin verme veya engelleme işlemlerini destekler

### Linux/Kali SSH Paneli

- `ssh` / `sshd` servis durumunu görüntüler
- SSH servis adını otomatik tespit eder
- Aktif SSH portunu veya portlarını gösterir
- SSH portunu değiştirmeye yardımcı olur
- `sshd_config` dosyasını yedekler ve test eder
- Aktif SSH oturumlarını ve ilgili process bilgilerini listeler
- Belirli SSH oturumlarını PID üzerinden sonlandırmaya yardımcı olur
- UFW ve firewalld durumlarını görüntüler
- UFW üzerinden IP bazlı allow/deny işlemlerini kolaylaştırır

## Kullanım Amacı

Bu araç aşağıdaki senaryolarda kullanılabilir:

- SSH servisinin çalışıp çalışmadığını kontrol etmek
- SSH portunun gerçekten hangi portta dinlediğini görmek
- SSH portunu güvenli şekilde değiştirmek
- Firewall üzerinde SSH erişimini düzenlemek
- Aktif SSH bağlantılarını incelemek
- Test/lab ortamında SSH servis yönetimini öğrenmek
- Windows ve Linux sistem yönetimi pratiği yapmak

## Güvenlik Uyarısı

Bu araç yalnızca size ait olan, yönettiğiniz veya kullanma yetkiniz bulunan sistemlerde kullanılmalıdır.

SSH servisini durdurma, port değiştirme, firewall kuralı silme veya aktif SSH oturumlarını sonlandırma gibi işlemler mevcut bağlantınızı kesebilir. Özellikle uzak sunucularda işlem yapmadan önce alternatif erişim yöntemi bulunduğundan emin olun.

Bu proje saldırı, yetkisiz erişim veya güvenlik atlatma amacıyla geliştirilmemiştir. Amaç sistem yönetimi, servis kontrolü ve eğitim/laboratuvar kullanımıdır.

## Önerilen Kullanım

Windows tarafında scripti yönetici yetkili PowerShell ile çalıştırın:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
.\win-openssh-panel.ps1


## Lisans

Bu proje MIT lisansı ile lisanslanmıştır. Detaylar için [LICENSE](LICENSE) dosyasına bakabilirsiniz.
