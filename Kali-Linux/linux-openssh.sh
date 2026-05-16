#!/usr/bin/env bash
# LINUX OPENSSH TEK PANEL v1
# Servis + Firewall + Port/Config + Aktif SSH oturum yonetimi
# Ubuntu / Debian / Kali icin optimize edildi. RHEL/Fedora tarafinda sshd servisi de desteklenir.

set -o pipefail

VERSION="Linux OpenSSH Tek Panel v1"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
PANEL_DROPIN="$SSHD_CONFIG_DIR/99-openssh-panel.conf"

# Root kontrolu
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Bu panel root yetkisi ister. sudo ile yeniden baslatiliyor..."
    exec sudo bash "$0" "$@"
fi

wait_enter() {
    echo ""
    read -r -p "Devam etmek icin Enter'a bas: " _
}

pause_short() {
    sleep 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_ssh_service() {
    if command_exists systemctl; then
        if systemctl list-unit-files ssh.service >/dev/null 2>&1 || systemctl status ssh >/dev/null 2>&1; then
            echo "ssh"
            return
        fi
        if systemctl list-unit-files sshd.service >/dev/null 2>&1 || systemctl status sshd >/dev/null 2>&1; then
            echo "sshd"
            return
        fi
    fi

    if command_exists service; then
        if service ssh status >/dev/null 2>&1; then
            echo "ssh"
            return
        fi
        if service sshd status >/dev/null 2>&1; then
            echo "sshd"
            return
        fi
    fi

    # Debian/Ubuntu/Kali icin varsayilan
    echo "ssh"
}

SSH_SERVICE="$(detect_ssh_service)"

service_is_known() {
    if command_exists systemctl; then
        systemctl status "$SSH_SERVICE" >/dev/null 2>&1 || systemctl list-unit-files "$SSH_SERVICE.service" >/dev/null 2>&1
        return $?
    fi

    if command_exists service; then
        service "$SSH_SERVICE" status >/dev/null 2>&1
        return $?
    fi

    return 1
}

get_service_main_pid() {
    if command_exists systemctl; then
        local main_pid
        main_pid="$(systemctl show "$SSH_SERVICE" -p MainPID --value 2>/dev/null)"
        if [[ "$main_pid" =~ ^[0-9]+$ ]] && [ "$main_pid" -gt 0 ]; then
            echo "$main_pid"
            return
        fi
    fi

    # fallback: listener gibi gorunen ilk root sshd PID
    pgrep -xo sshd 2>/dev/null || true
}

service_status_line() {
    if command_exists systemctl; then
        local active enabled mainpid
        active="$(systemctl is-active "$SSH_SERVICE" 2>/dev/null || true)"
        enabled="$(systemctl is-enabled "$SSH_SERVICE" 2>/dev/null || true)"
        mainpid="$(get_service_main_pid)"
        echo "Service: $SSH_SERVICE | Active: ${active:-unknown} | Enabled: ${enabled:-unknown} | MainPID: ${mainpid:-Yok}"
    elif command_exists service; then
        echo "Service: $SSH_SERVICE"
        service "$SSH_SERVICE" status 2>/dev/null | head -n 5
    else
        echo "systemctl/service bulunamadi."
    fi
}

get_current_ssh_ports() {
    # En dogru okuma: sshd -T efektif config. Birden fazla port varsa hepsini basar.
    if command_exists sshd; then
        local ports
        ports="$(sshd -T 2>/dev/null | awk '$1 == "port" {print $2}' | sort -n | uniq | tr '\n' ' ')"
        if [ -n "${ports// }" ]; then
            echo "$ports" | xargs
            return
        fi
    fi

    # Fallback: Match blogundan onceki aktif Port satirlari.
    if [ -f "$SSHD_CONFIG" ]; then
        awk '
            BEGIN { inmatch=0; found=0 }
            /^[[:space:]]*Match[[:space:]]/ { inmatch=1 }
            !inmatch && /^[[:space:]]*Port[[:space:]]+[0-9]+/ && $0 !~ /^[[:space:]]*#/ { print $2; found=1 }
            END { if (found == 0) print 22 }
        ' "$SSHD_CONFIG" | sort -n | uniq | tr '\n' ' ' | xargs
        return
    fi

    echo "22"
}

get_primary_ssh_port() {
    get_current_ssh_ports | awk '{print $1}'
}

show_listen_status() {
    local ports
    ports="$(get_current_ssh_ports)"

    if ! command_exists ss; then
        echo "ss komutu bulunamadi."
        return
    fi

    local any=0
    for port in $ports; do
        echo "--- Port $port LISTEN durumu ---"
        local output
        output="$(ss -tulpen 2>/dev/null | awk -v p=":$port" '$0 ~ p {print}')"
        if [ -n "$output" ]; then
            echo "$output"
            any=1
        else
            echo "Port $port LISTEN durumda degil."
        fi
        echo ""
    done

    [ "$any" -eq 0 ] && true
}

show_active_tcp_connections() {
    local ports
    ports="$(get_current_ssh_ports)"

    if ! command_exists ss; then
        echo "ss komutu bulunamadi."
        return
    fi

    local found=0
    for port in $ports; do
        echo "--- Port $port aktif TCP SSH baglantilari ---"
        local output
        output="$(ss -tnp state established 2>/dev/null | awk -v p=":$port" '$0 ~ p {print}')"
        if [ -n "$output" ]; then
            echo "$output"
            found=1
        else
            echo "Aktif TCP baglantisi yok."
        fi
        echo ""
    done

    [ "$found" -eq 0 ] && true
}

show_dashboard() {
    clear
    echo "======================================"
    echo " $VERSION"
    echo "======================================"
    echo ""

    echo "1) SSH SERVIS DURUMU:"
    service_status_line

    echo ""
    echo "2) SSH CONFIG:"
    if [ -f "$SSHD_CONFIG" ]; then
        echo "Config dosyasi: $SSHD_CONFIG"
    else
        echo "Config dosyasi bulunamadi: $SSHD_CONFIG"
    fi
    echo "Aktif SSH port/portlari: $(get_current_ssh_ports)"

    echo ""
    echo "3) LISTEN DURUMU:"
    show_listen_status

    echo "4) AKTIF SSH OTURUM PROCESS DURUMU:"
    echo "Ana ekranda gosterilmiyor. Aktif SSH oturumlarini gormek ve kill etmek icin ana menuden 5'i sec."

    echo ""
    echo "5) FIREWALL KURALLARI:"
    echo "Ana ekranda gosterilmiyor. Firewall kurallarini gormek icin ana menuden 6'yi sec."
}

backup_sshd_config() {
    if [ ! -f "$SSHD_CONFIG" ]; then
        echo "sshd_config bulunamadi, yedek alinamadi."
        return 1
    fi

    local ts backup
    ts="$(date +%Y%m%d-%H%M%S)"
    backup="$SSHD_CONFIG.bak-$ts"
    cp "$SSHD_CONFIG" "$backup"
    echo "Yedek alindi: $backup"
}

test_sshd_config() {
    if ! command_exists sshd; then
        echo "sshd komutu bulunamadi. openssh-server kurulu olmayabilir."
        return 1
    fi

    if [ ! -f "$SSHD_CONFIG" ]; then
        echo "sshd_config bulunamadi: $SSHD_CONFIG"
        return 1
    fi

    echo "sshd_config test ediliyor..."
    if sshd -t -f "$SSHD_CONFIG"; then
        echo "Config testi basarili."
        return 0
    else
        echo "Config testinde hata var."
        return 1
    fi
}

has_sshd_config_dropin_include() {
    [ -f "$SSHD_CONFIG" ] || return 1
    grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSHD_CONFIG"
}

comment_global_port_lines_in_main_config() {
    local ts tmp
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    tmp="$(mktemp)"

    awk -v ts="$ts" '
        BEGIN { inmatch=0 }
        /^[[:space:]]*Match[[:space:]]/ { inmatch=1 }
        !inmatch && /^[[:space:]]*Port[[:space:]]+[0-9]+/ && $0 !~ /^[[:space:]]*#/ {
            print "# DISABLED_BY_LINUX_PANEL " ts " : " $0
            next
        }
        { print }
    ' "$SSHD_CONFIG" > "$tmp"

    cat "$tmp" > "$SSHD_CONFIG"
    rm -f "$tmp"
}

insert_port_before_match_in_main_config() {
    local new_port ts tmp
    new_port="$1"
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    tmp="$(mktemp)"

    awk -v port="$new_port" -v ts="$ts" '
        BEGIN { inserted=0 }
        !inserted && /^[[:space:]]*Match[[:space:]]/ {
            print ""
            print "# Added by Linux OpenSSH panel " ts
            print "Port " port
            print ""
            inserted=1
        }
        { print }
        END {
            if (inserted == 0) {
                print ""
                print "# Added by Linux OpenSSH panel " ts
                print "Port " port
            }
        }
    ' "$SSHD_CONFIG" > "$tmp"

    cat "$tmp" > "$SSHD_CONFIG"
    rm -f "$tmp"
}

set_ssh_port_config() {
    local new_port
    new_port="$1"

    backup_sshd_config || return 1

    # Ana config icindeki global Port satirlarini kapat.
    comment_global_port_lines_in_main_config

    # Drop-in Include varsa panel drop-in kullan. Yoksa ana configte Match oncesine yaz.
    if [ -d "$SSHD_CONFIG_DIR" ] && has_sshd_config_dropin_include; then
        cat > "$PANEL_DROPIN" <<EOF_DROPIN
# Managed by Linux OpenSSH panel
# Created: $(date '+%Y-%m-%d %H:%M:%S')
Port $new_port
EOF_DROPIN
        echo "Port $new_port drop-in dosyasina yazildi: $PANEL_DROPIN"
    else
        insert_port_before_match_in_main_config "$new_port"
        echo "Port $new_port ana config dosyasinda Match blogundan once yazildi."
    fi

    test_sshd_config
}

restart_ssh_service() {
    if command_exists systemctl; then
        systemctl restart "$SSH_SERVICE"
    elif command_exists service; then
        service "$SSH_SERVICE" restart
    else
        return 1
    fi
}

start_ssh_service() {
    if command_exists systemctl; then
        systemctl start "$SSH_SERVICE"
    elif command_exists service; then
        service "$SSH_SERVICE" start
    else
        return 1
    fi
}

stop_ssh_service() {
    if command_exists systemctl; then
        systemctl stop "$SSH_SERVICE"
    elif command_exists service; then
        service "$SSH_SERVICE" stop
    else
        return 1
    fi
}

enable_ssh_service() {
    if command_exists systemctl; then
        systemctl enable "$SSH_SERVICE"
    else
        echo "systemctl yok. enable islemi desteklenmiyor."
        return 1
    fi
}

disable_ssh_service() {
    if command_exists systemctl; then
        systemctl disable "$SSH_SERVICE"
    else
        echo "systemctl yok. disable islemi desteklenmiyor."
        return 1
    fi
}

service_menu() {
    while true; do
        clear
        echo "=============================="
        echo " SSH SERVIS YONETIMI"
        echo "=============================="
        echo ""
        service_status_line
        echo ""
        echo "1) ssh servisini baslat"
        echo "2) ssh servisini durdur"
        echo "3) ssh servisini yeniden baslat"
        echo "4) Baslangici enable yap ve servisi baslat"
        echo "5) Baslangici disable yap"
        echo "6) Servis durumunu yenile"
        echo "B) Geri don"
        echo ""
        read -r -p "Secim yap: " choice

        case "$choice" in
            1)
                if start_ssh_service; then echo "SSH servisi baslatildi."; else echo "SSH servisi baslatilamadi."; fi
                wait_enter
                ;;
            2)
                echo "Dikkat: SSH ile bagliysan oturumun dusebilir."
                read -r -p "Devam edilsin mi? E/H: " confirm
                if [[ "$confirm" =~ ^[Ee]$ ]]; then
                    if stop_ssh_service; then echo "SSH servisi durduruldu."; else echo "SSH servisi durdurulamadi."; fi
                else
                    echo "Islem iptal edildi."
                fi
                wait_enter
                ;;
            3)
                echo "Dikkat: SSH ile bagliysan oturumun dusebilir."
                read -r -p "Devam edilsin mi? E/H: " confirm
                if [[ "$confirm" =~ ^[Ee]$ ]]; then
                    if restart_ssh_service; then echo "SSH servisi yeniden baslatildi."; else echo "SSH servisi yeniden baslatilamadi."; fi
                else
                    echo "Islem iptal edildi."
                fi
                wait_enter
                ;;
            4)
                enable_ssh_service
                start_ssh_service
                echo "SSH servisi enable yapildi ve baslatildi."
                wait_enter
                ;;
            5)
                disable_ssh_service
                echo "SSH servisi disable yapildi."
                wait_enter
                ;;
            6)
                continue
                ;;
            B|b)
                return
                ;;
            *)
                echo "Gecersiz secim."
                wait_enter
                ;;
        esac
    done
}

set_ssh_port_menu() {
    local new_port
    read -r -p "Yeni SSH portunu gir. Ornek: 2222: " new_port

    if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then
        echo "Gecersiz port. Sadece sayi gir."
        wait_enter
        return
    fi

    if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        echo "Gecersiz port. Port 1 ile 65535 arasinda olmali."
        wait_enter
        return
    fi

    if command_exists ss && ss -tulpen 2>/dev/null | awk -v p=":$new_port" '$0 ~ p {found=1} END {exit found ? 0 : 1}'; then
        echo "Port $new_port su anda baska bir servis tarafindan dinleniyor."
        wait_enter
        return
    fi

    echo "SSH portu $new_port olarak ayarlanacak."
    echo "Baglanti komutu: ssh kullanici@LinuxIP -p $new_port"
    read -r -p "Devam edilsin mi? E/H: " confirm

    if [[ ! "$confirm" =~ ^[Ee]$ ]]; then
        echo "Islem iptal edildi."
        wait_enter
        return
    fi

    if set_ssh_port_config "$new_port"; then
        echo "Config basarili. Firewall tarafini da guncellemen gerekebilir."
        auto_firewall_offer_after_port_change "$new_port"
        echo "SSH servisi yeniden baslatiliyor..."
        if restart_ssh_service; then
            echo "SSH portu $new_port olarak ayarlandi ve servis yeniden baslatildi."
        else
            echo "SSH servisi yeniden baslatilamadi. Config test basariliydi ama servis restart olmadi."
        fi
    else
        echo "Config test basarisiz. Servis yeniden baslatilmadi. Yedekten geri donmeyi dusun."
    fi

    wait_enter
}

restore_port_22_menu() {
    echo "SSH portu tekrar 22 yapilacak."
    read -r -p "Devam edilsin mi? E/H: " confirm

    if [[ ! "$confirm" =~ ^[Ee]$ ]]; then
        echo "Islem iptal edildi."
        wait_enter
        return
    fi

    if set_ssh_port_config 22; then
        auto_firewall_offer_after_port_change 22
        if restart_ssh_service; then
            echo "SSH portu tekrar 22 yapildi ve servis yeniden baslatildi."
        else
            echo "SSH servisi yeniden baslatilamadi."
        fi
    else
        echo "Config test basarisiz. Servis yeniden baslatilmadi."
    fi

    wait_enter
}

analyze_port_lines() {
    clear
    echo "=============================="
    echo " SSHD_CONFIG PORT ANALIZI"
    echo "=============================="
    echo ""

    if [ ! -f "$SSHD_CONFIG" ]; then
        echo "sshd_config bulunamadi: $SSHD_CONFIG"
        wait_enter
        return
    fi

    echo "Ana config icindeki Port / Match / Include satirlari:"
    echo ""
    nl -ba "$SSHD_CONFIG" | grep -E '^[[:space:]]*[0-9]+[[:space:]]+([[:space:]]*#.*Port|[[:space:]]*Port|[[:space:]]*Match|[[:space:]]*Include)' || true

    echo ""
    if [ -f "$PANEL_DROPIN" ]; then
        echo "Panel drop-in dosyasi: $PANEL_DROPIN"
        nl -ba "$PANEL_DROPIN"
    else
        echo "Panel drop-in dosyasi yok: $PANEL_DROPIN"
    fi

    echo ""
    echo "Efektif SSH port/portlari: $(get_current_ssh_ports)"
    wait_enter
}

open_config_editor() {
    local editor
    editor="${EDITOR:-nano}"

    if ! command_exists "$editor"; then
        editor="vi"
    fi

    "$editor" "$SSHD_CONFIG"
}

config_menu() {
    while true; do
        clear
        echo "=============================="
        echo " SSH PORT / CONFIG YONETIMI"
        echo "=============================="
        echo ""
        echo "Config dosyasi: $SSHD_CONFIG"
        echo "Aktif SSH port/portlari: $(get_current_ssh_ports)"
        echo ""
        echo "1) SSH portunu degistir"
        echo "2) SSH portunu tekrar 22 yap"
        echo "3) sshd_config dosyasini editor ile ac"
        echo "4) sshd_config dosyasini test et"
        echo "5) Baglanti komutunu goster"
        echo "6) sshd_config Port satirlarini analiz et"
        echo "B) Geri don"
        echo ""
        read -r -p "Secim yap: " choice

        case "$choice" in
            1) set_ssh_port_menu ;;
            2) restore_port_22_menu ;;
            3) open_config_editor ;;
            4) test_sshd_config; wait_enter ;;
            5) show_connect_command ;;
            6) analyze_port_lines ;;
            B|b) return ;;
            *) echo "Gecersiz secim."; wait_enter ;;
        esac
    done
}

show_connect_command() {
    local ports primary
    ports="$(get_current_ssh_ports)"
    primary="$(echo "$ports" | awk '{print $1}')"

    echo ""
    echo "Baglanmak icin:"
    if [ "$primary" = "22" ]; then
        echo "ssh kullanici@LinuxIP"
        echo "Ornek: ssh kali@192.168.56.101"
    else
        echo "ssh kullanici@LinuxIP -p $primary"
        echo "Ornek: ssh kali@192.168.56.101 -p $primary"
    fi
    wait_enter
}

get_sshd_process_table() {
    local main_pid
    main_pid="$(get_service_main_pid)"

    if ! command_exists ps; then
        echo "ps komutu bulunamadi."
        return 1
    fi

    printf "%-8s %-8s %-12s %-10s %-32s %s\n" "PID" "PPID" "USER" "STAT" "ROLE" "COMMAND"
    printf "%-8s %-8s %-12s %-10s %-32s %s\n" "---" "----" "----" "----" "----" "-------"

    ps -eo pid=,ppid=,user=,stat=,args= | grep '[s]shd' | while read -r proc_id parent_id proc_user proc_stat proc_cmd; do
        local role
        if [ -n "$main_pid" ] && [ "$proc_id" = "$main_pid" ]; then
            role="ANA SERVIS/LISTENER - OLDURME"
        elif echo "$proc_cmd" | grep -Eq '\[priv\]|preauth'; then
            role="SSH OTURUM PRIV/PARENT"
        elif echo "$proc_cmd" | grep -Eq '@pts|notty|session|sshd:'; then
            role="SSH OTURUM SURECI - KILL EDILEBILIR"
        else
            role="DIGER SSHD SURECI"
        fi
        printf "%-8s %-8s %-12s %-10s %-32s %s\n" "$proc_id" "$parent_id" "$proc_user" "$proc_stat" "$role" "$proc_cmd"
    done
}

show_ssh_sessions() {
    clear
    echo "=============================="
    echo " AKTIF SSH OTURUMLARI"
    echo "=============================="
    echo ""
    echo "Servis ana PID: $(get_service_main_pid)"
    echo "Ana servis/listener oldurulmez. Oturum sureci PID'i kill edilir."
    echo ""
    echo "PROCESS LISTESI:"
    get_sshd_process_table
    echo ""
    echo "AKTIF TCP BAGLANTILARI:"
    show_active_tcp_connections
    wait_enter
}

kill_selected_ssh_session() {
    clear
    echo "=============================="
    echo " SECILEN SSH OTURUMUNU KILL ET"
    echo "=============================="
    echo ""
    echo "Servis ana PID: $(get_service_main_pid)"
    echo ""
    get_sshd_process_table
    echo ""
    echo "Ana servis/listener PID girilirse islem yapilmaz."
    echo "Oturum sureci PID'i gir. Linux tarafinda genelde 'sshd: kullanici@pts/...' veya '[priv]' zinciri gorunur."
    echo ""
    read -r -p "Kill edilecek SSH oturum PID degerini gir: " pid_input

    if [[ ! "$pid_input" =~ ^[0-9]+$ ]]; then
        echo "Gecersiz PID. Sadece sayi gir."
        wait_enter
        return
    fi

    local main_pid target_cmd
    main_pid="$(get_service_main_pid)"

    if [ -n "$main_pid" ] && [ "$pid_input" = "$main_pid" ]; then
        echo "$pid_input ana SSH servis/listener PID'sidir. ISLEM YAPILMADI."
        wait_enter
        return
    fi

    if ! ps -p "$pid_input" >/dev/null 2>&1; then
        echo "$pid_input PID bulunamadi."
        wait_enter
        return
    fi

    target_cmd="$(ps -p "$pid_input" -o args= 2>/dev/null)"

    if ! echo "$target_cmd" | grep -q "sshd"; then
        echo "$pid_input sshd sureci degil. ISLEM YAPILMADI."
        echo "Komut: $target_cmd"
        wait_enter
        return
    fi

    echo "$pid_input PID sonlandiriliyor..."
    kill "$pid_input" 2>/dev/null || true
    sleep 1

    if ps -p "$pid_input" >/dev/null 2>&1; then
        echo "Normal kill yetmedi. kill -9 deneniyor..."
        kill -9 "$pid_input" 2>/dev/null || true
        sleep 1
    fi

    if ps -p "$pid_input" >/dev/null 2>&1; then
        echo "$pid_input PID sonlandirilamadi."
    else
        echo "$pid_input PID sonlandirildi. SSH oturumu dusmus olmali."
    fi

    wait_enter
}

kill_all_ssh_sessions() {
    clear
    echo "=============================="
    echo " TUM SSH OTURUMLARINI KILL ET"
    echo "=============================="
    echo ""
    local main_pid
    main_pid="$(get_service_main_pid)"

    echo "Servis ana PID: ${main_pid:-Yok}"
    echo "Ana servis haricindeki sshd surecleri hedeflenecek."
    echo ""
    get_sshd_process_table
    echo ""
    read -r -p "Tum SSH oturum surecleri kill edilsin mi? E/H: " confirm

    if [[ ! "$confirm" =~ ^[Ee]$ ]]; then
        echo "Islem iptal edildi."
        wait_enter
        return
    fi

    ps -eo pid=,args= | grep '[s]shd' | while read -r proc_id proc_cmd; do
        if [ -n "$main_pid" ] && [ "$proc_id" = "$main_pid" ]; then
            continue
        fi
        echo "$proc_id kill ediliyor: $proc_cmd"
        kill "$proc_id" 2>/dev/null || true
    done

    sleep 1
    wait_enter
}

session_menu() {
    while true; do
        clear
        echo "=============================="
        echo " SSH OTURUM YONETIMI"
        echo "=============================="
        echo ""
        echo "1) Aktif SSH oturumlarini listele"
        echo "2) Secilen SSH oturumunu PID ile kill et"
        echo "3) Tum SSH oturumlarini kill et"
        echo "B) Geri don"
        echo ""
        read -r -p "Secim yap: " choice

        case "$choice" in
            1) show_ssh_sessions ;;
            2) kill_selected_ssh_session ;;
            3) kill_all_ssh_sessions ;;
            B|b) return ;;
            *) echo "Gecersiz secim."; wait_enter ;;
        esac
    done
}

ufw_status() {
    if command_exists ufw; then
        ufw status verbose
    else
        echo "ufw kurulu degil. Debian/Ubuntu/Kali icin kurulum: sudo apt install ufw"
    fi
}

firewalld_status() {
    if command_exists firewall-cmd; then
        firewall-cmd --state 2>/dev/null || true
        firewall-cmd --list-all 2>/dev/null || true
    else
        echo "firewalld kurulu degil."
    fi
}

auto_firewall_offer_after_port_change() {
    local new_port
    new_port="$1"

    if command_exists ufw; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            read -r -p "UFW aktif. Port $new_port/tcp icin izin eklensin mi? E/H: " confirm
            if [[ "$confirm" =~ ^[Ee]$ ]]; then
                ufw allow "$new_port/tcp"
                echo "UFW port izni eklendi: $new_port/tcp"
            fi
        fi
    fi

    if command_exists firewall-cmd; then
        if firewall-cmd --state >/dev/null 2>&1; then
            read -r -p "firewalld aktif. Port $new_port/tcp icin izin eklensin mi? E/H: " confirm
            if [[ "$confirm" =~ ^[Ee]$ ]]; then
                firewall-cmd --permanent --add-port="$new_port/tcp"
                firewall-cmd --reload
                echo "firewalld port izni eklendi: $new_port/tcp"
            fi
        fi
    fi
}

firewall_allow_ip() {
    local port ips
    port="$(get_primary_ssh_port)"
    read -r -p "SSH icin izin verilecek IP/IP'leri gir. Birden fazla IP icin virgulle ayir: " ips

    IFS=',' read -ra arr <<< "$ips"
    for raw in "${arr[@]}"; do
        ip="$(echo "$raw" | xargs)"
        [ -z "$ip" ] && continue
        if command_exists ufw; then
            ufw allow from "$ip" to any port "$port" proto tcp
            echo "UFW izin eklendi: $ip -> port $port/tcp"
        else
            echo "ufw yok. Komut atlandi: $ip"
        fi
    done
    wait_enter
}

firewall_allow_any() {
    local port
    port="$(get_primary_ssh_port)"

    if command_exists ufw; then
        ufw allow "$port/tcp"
        echo "UFW Any izin eklendi: $port/tcp"
    else
        echo "ufw kurulu degil."
    fi
    wait_enter
}

firewall_block_ip() {
    local port ip
    port="$(get_primary_ssh_port)"
    read -r -p "SSH icin engellenecek IP adresini gir: " ip

    if [ -z "$ip" ]; then
        echo "Gecerli IP girilmedi."
        wait_enter
        return
    fi

    if command_exists ufw; then
        ufw deny from "$ip" to any port "$port" proto tcp
        echo "UFW deny eklendi: $ip -> port $port/tcp"
    else
        echo "ufw kurulu degil."
    fi
    wait_enter
}

firewall_remove_rule_number() {
    if ! command_exists ufw; then
        echo "ufw kurulu degil."
        wait_enter
        return
    fi

    ufw status numbered
    echo ""
    read -r -p "Silinecek UFW kural numarasini gir: " num

    if [[ ! "$num" =~ ^[0-9]+$ ]]; then
        echo "Gecersiz numara."
        wait_enter
        return
    fi

    yes | ufw delete "$num"
    wait_enter
}

firewall_enable_ufw() {
    if command_exists ufw; then
        ufw --force enable
    else
        echo "ufw kurulu degil."
    fi
    wait_enter
}

firewall_disable_ufw() {
    if command_exists ufw; then
        ufw disable
    else
        echo "ufw kurulu degil."
    fi
    wait_enter
}

firewall_menu() {
    while true; do
        clear
        echo "=============================="
        echo " SSH FIREWALL YONETIMI"
        echo "=============================="
        echo ""
        echo "Aktif SSH port/portlari: $(get_current_ssh_ports)"
        echo ""
        echo "UFW DURUMU:"
        ufw_status
        echo ""
        echo "firewalld DURUMU:"
        firewalld_status
        echo ""
        echo "1) Firewall durumunu yenile/listele"
        echo "2) UFW: SSH icin sadece belirli IP/IP'lere izin ekle"
        echo "3) UFW: SSH portunu herkese ac"
        echo "4) UFW: Belirli IP adresini SSH icin engelle"
        echo "5) UFW: Numarali kural sil"
        echo "6) UFW enable"
        echo "7) UFW disable"
        echo "B) Geri don"
        echo ""
        read -r -p "Secim yap: " choice

        case "$choice" in
            1) continue ;;
            2) firewall_allow_ip ;;
            3) firewall_allow_any ;;
            4) firewall_block_ip ;;
            5) firewall_remove_rule_number ;;
            6) firewall_enable_ufw ;;
            7) firewall_disable_ufw ;;
            B|b) return ;;
            *) echo "Gecersiz secim."; wait_enter ;;
        esac
    done
}

main_menu() {
    local exit_panel=0
    while [ "$exit_panel" -eq 0 ]; do
        show_dashboard
        echo ""
        echo "======================================"
        echo " ANA MENU"
        echo "======================================"
        echo "1) Durum ekranini yenile"
        echo "2) SSH servis yonetimi"
        echo "3) SSH port / config yonetimi"
        echo "4) Baglanti komutunu goster"
        echo "5) Aktif SSH oturumlarini listele / secileni kill et"
        echo "6) SSH firewall kurallari yonetimi"
        echo "Q) Cikis"
        echo ""
        read -r -p "Secim yap: " choice

        case "$choice" in
            1) continue ;;
            2) service_menu ;;
            3) config_menu ;;
            4) show_connect_command ;;
            5) session_menu ;;
            6) firewall_menu ;;
            Q|q) exit_panel=1 ;;
            *) echo "Gecersiz secim."; wait_enter ;;
        esac
    done
}

main_menu
