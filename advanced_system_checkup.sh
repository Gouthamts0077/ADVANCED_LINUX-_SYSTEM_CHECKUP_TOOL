#!/bin/bash

# =============================================================================
#  ADVANCED LINUX SYSTEM CHECKUP TOOL
#  Author: Goutham T S
#  Usage:  sudo bash syscheck.sh [--quick|--full] [--report file]
# =============================================================================

VERSION="2.0"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
NC='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'

P="$GREEN[PASS]$NC"; W="$YELLOW[WARN]$NC"; F="$RED[FAIL]$NC"
I="$BLUE[INFO]$NC"; S="$CYAM[SCAN]$NC"; H="$MAGENTA[HARDEN]$NC"

PC=0; WC=0; FC=0; IC=0
MODE="full"; REPORT=""

ok()   { echo -e "  $P $1"; ((PC++)); }
warn() { echo -e "  $W $1"; ((WC++)); }
fail() { echo -e "  $F $1"; ((FC++)); }
info() { echo -e "  $I $1"; ((IC++)); }
hr()   { printf '%*s\n' 80 '' | tr ' ' '='; }

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick) MODE="quick"; shift ;;
        --full)  MODE="full";  shift ;;
        --report) REPORT="$2"; shift 2 ;;
        *) echo "Usage: $0 [--quick|--full] [--report file]"; exit 1 ;;
    esac
done

if [[ -n "$REPORT" ]]; then
    exec > >(tee -a "$REPORT") 2>&1
fi

if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}[!] Some checks require root. Re-run with: sudo $0${NC}"
fi

# ============================================================================
# HEADER
# ============================================================================
clear
echo -e "${CYAN}${BOLD}"
echo '  ╔══════════════════════════════════════════════════════════╗'
echo '  ║          ADVANCED LINUX SYSTEM CHECKUP TOOL v2.0        ║'
echo '  ╚══════════════════════════════════════════════════════════╝'
echo -e "${NC}"
echo -e "  ${DIM}Date:$(date '+%Y-%m-%d %H:%M:%S')  |  Host:$(hostname)  |  Mode:${MODE}${NC}"
echo ""

# ============================================================================
# 1. SYSTEM INFORMATION
# ============================================================================
hr
echo -e "${BOLD}${CYAN}[1] SYSTEM INFORMATION${NC}"
hr

if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    info "Distribution   : ${PRETTY_NAME:-$NAME $VERSION_ID}"
fi
info "Kernel         : $(uname -r)"
info "Architecture   : $(uname -m)"
info "Hostname       : $(hostname)"
info "Uptime         : $(uptime -p 2>/dev/null | sed 's/up //')"
info "Boot time      : $(who -b 2>/dev/null | awk '{print $3, $4}')"
info "Users logged  : $(who | wc -l)"

# ============================================================================
# 2. CPU ANALYSIS
# ============================================================================
echo ""
hr
echo -e "${BOLD}${CYAN}[2] CPU ANALYSIS${NC}"
hr

model=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
phys=$(grep 'physical id' /proc/cpuinfo | sort -u | wc -l)
threads_per_core=$((cores / (phys > 0 ? phys : 1)))
info "Model          : $model"
info "Logical cores  : $cores"
info "Sockets        : $phys"
info "Threads/core   : $threads_per_core"

# Load average
read -r l1 l5 l15 _ < /proc/loadavg
info "Load average   : $l1 (1m) / $l5 (5m) / $l15 (15m)"
load_score=$(echo "$l1 $cores" | awk '{printf "%.0f", ($1/$2)*100}')
if [[ $load_score -lt 50 ]]; then ok "Load score: ${load_score}% (healthy)"
elif [[ $load_score -lt 80 ]]; then warn "Load score: ${load_score}% (moderate)"
else fail "Load score: ${load_score}% (high)"
fi

# CPU usage
idle=$(awk '/^cpu / {print $5}' /proc/stat)
totalcpu=0
for v in $(awk '/^cpu / {for(i=2;i<=NF;i++) print $i}' /proc/stat); do
    ((totalcpu+=v))
done
usage=$((100 * (totalcpu - idle) / totalcpu))
if [[ $usage -lt 50 ]]; then ok "CPU usage: ${usage}%"
elif [[ $usage -lt 80 ]]; then warn "CPU usage: ${usage}%"
else fail "CPU usage: ${usage}%"
fi

# CPU temperature
if command -v sensors &>/dev/null; then
    temp=$(sensors -u 2>/dev/null | awk '/temp1_input/{print $2; exit}')
    if [[ -n "$temp" ]]; then
        tint=${temp%.*}
        if [[ $tint -lt 60 ]]; then ok "CPU temp: ${temp}°C"
        elif [[ $tint -lt 80 ]]; then warn "CPU temp: ${temp}°C"
        else fail "CPU temp: ${temp}°C"
        fi
    fi
fi

# CPU governor
gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
[[ -n "$gov" ]] && info "Governor       : $gov"

# Context switches & interrupts
ctx=$(grep 'ctxt' /proc/stat | awk '{print $2}')
proc_int=$(grep 'intr' /proc/stat | awk '{print $2}')
info "Context switches: $ctx"
info "Interrupts     : $proc_int"

# ============================================================================
# 3. MEMORY ANALYSIS
# ============================================================================
echo ""
hr
echo -e "${BOLD}${CYAN}[3] MEMORY ANALYSIS${NC}"
hr

mtotal=$(free -m | awk '/^Mem:/{print $2}')
mused=$(free -m | awk '/^Mem:/{print $3}')
mavail=$(free -m | awk '/^Mem:/{print $7}')
mbuff=$(free -m | awk '/^Mem:/{print $6}')
mcached=$(free -m | awk '/^Mem:/{print $7}')
mpct=$((100 * mused / mtotal))
real_used=$((mused - mbuff))
real_pct=$((100 * real_used / mtotal))

echo -e "  ${DIM}Total: ${mtotal}MB | Used: ${mused}MB | Buff/Cache: ${mbuff}MB | Avail: ${mavail}MB${NC}"
if [[ $real_pct -lt 60 ]]; then ok "Memory pressure: ${real_pct}% (healthy)"
elif [[ $real_pct -lt 80 ]]; then warn "Memory pressure: ${real_pct}% (moderate)"
else fail "Memory pressure: ${real_pct}% (critical)"
fi

# Swap
stotal=$(free -m | awk '/^Swap:/{print $2}')
sused=$(free -m | awk '/^Swap:/{print $3}')
if [[ $stotal -gt 0 ]]; then
    spct=$((100 * sused / stotal))
    info "Swap: ${stotal}MB total, ${sused}MB used (${spct}%)"
    if [[ $spct -lt 10 ]]; then ok "Swap usage: ${spct}%"
    elif [[ $spct -lt 30 ]]; then warn "Swap usage: ${spct}%"
    else fail "Swap usage: ${spct}%"
    fi
fi

# Top memory processes
info "Top 5 processes by memory:"
echo -e "  ${DIM}$(ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5 | awk '{printf "%-25s %5s%%  %s\n", $11, $4, $6}')${NC}"

# Memory fragmentation / hugepages
hp=$(grep HugePages_Total /proc/meminfo | awk '{print $2}')
[[ $hp -gt 0 ]] && info "HugePages     : ${hp} allocated"

# ============================================================================
# 4. DISK ANALYSIS
# ============================================================================
echo ""
hr
echo -e "${BOLD}${CYAN}[4] DISK ANALYSIS${NC}"
hr

# Filesystem usage
echo -e "  ${DIM}Filesystem usage:${NC}"
df -h -t ext4 -t ext3 -t ext2 -t xfs -t btrfs -t zfs 2>/dev/null | tail -n+2 | while read fss size used avail use mount; do
    pct=${use%\%}
    if [[ $pct -lt 50 ]]; then ok "${mount}: ${use} used (${avail} free)"
    elif [[ $pct -lt 75 ]]; then warn "${mount}: ${use} used (${avail} free)"
    elif [[ $pct -lt 90 ]]; then fail "${mount}: ${use} used (${avail} free)"
    else fail "${mount}: ${use} used (${avail} free) [CRITICAL]"
    fi
done

# INode usage
echo -e "  ${DIM}Inode usage:${NC}"
df -i -t ext4 -t ext3 -t ext2 -t xfs -t btrfs -t zfs 2>/dev/null | tail -n+2 | while read fss inodes iused iavail ipct mount; do
    ival=${ipct%\%}
    if [[ $ival -gt 90 ]]; then fail "INodes ${mount}: ${ipct} used [CRITICAL]"
    elif [[ $ival -gt 75 ]]; then warn "INodes ${mount}: ${ipct} used"
    fi
done

# Disk I/O
echo -e "  ${DIM}Disk I/O stats:${NC}"
iostat -x 1 2 2>/dev/null | tail -20 | while read line; do
    echo "    $line"
done 2>/dev/null || info "iostat not installed (install sysstat)"

# Mounted filesystems
echo -e "  ${DIM}Mount points:${NC}"
mount -l 2>/dev/null | grep -E 'ext4|xfs|btrfs|zfs' | awk '{printf "    %s -> %s (%s)\n", $1, $3, $5}' | head -10

# SMART status
if command -v smartctl &>/dev/null; then
    for d in /dev/sd?; do
        [[ -b "$d" ]] || continue
        ss=$(smartctl -H "$d" 2>/dev/null | grep "SMART overall-health" | awk -F': ' '{print $2}')
        if [[ "$ss" == "PASSED" ]]; then ok "SMART $d: PASSED"
        elif [[ -n "$ss" ]]; then fail "SMART $d: $ss"
        fi
    done
    for d in /dev/nvme?n?; do
        [[ -b "$d" ]] || continue
        ss=$(smartctl -H "$d" 2>/dev/null | grep "SMART overall-health" | awk -F': ' '{print $2}')
        if [[ "$ss" == "PASSED" ]]; then ok "SMART $d: PASSED"
        elif [[ -n "$ss" ]]; then fail "SMART $d: $ss"
        fi
    done
else
    info "smartctl not installed - install smartmontools for disk health"
fi

# Large files (only in full mode)
if [[ "$MODE" == "full" ]]; then
    echo -e "  ${DIM}Top 10 largest files (/home, /var, /tmp):${NC}"
    find /home /var /tmp -xdev -type f -size +100M 2>/dev/null | head -10 | while read f; do
        ls -lh "$f" 2>/dev/null | awk '{printf "    %s  %s\n", $5, $NF}'
    done
fi

# ============================================================================
# 5. NETWORK ANALYSIS
# ============================================================================
echo ""
hr
echo -e "${BOLD}${CYAN}[5] NETWORK ANALYSIS${NC}"
hr

# Interfaces
echo -e "  ${DIM}Network interfaces:${NC}"
ip -br addr 2>/dev/null | while read iface state ip rest; do
    [[ "$iface" == "lo" ]] && continue
    echo -e "    ${BOLD}$iface${NC}: ${state} - ${ip:--}"
done

# Connectivity
if ping -c1 -W3 8.8.8.8 &>/dev/null; then
    ping_time=$(ping -c1 -W3 8.8.8.8 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
    ok "Internet: reachable (${ping_time}ms)"
else
    fail "Internet: NOT reachable"
fi

# DNS
if host google.com &>/dev/null; then
    dns_ip=$(host google.com 2>/dev/null | head -1 | awk '{print $NF}')
    ok "DNS: resolving (${dns_ip})"
else
    fail "DNS: NOT resolving"
fi

# Default route
gw=$(ip route 2>/dev/null | grep default | awk '{print $3}')
info "Default gateway: ${gw:-none}"

# DNS servers
echo -e "  ${DIM}DNS servers:${NC}"
grep -v '^#' /etc/resolv.conf 2>/dev/null | grep nameserver | while read ns ip; do
    echo "    $ip"
done

# Listening ports
echo -e "  ${DIM}Listening ports:${NC}"
if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | tail -n+2 | awk '{print "    TCP: " $4, $NF}' | sort -u
    ss -ulnp 2>/dev/null | tail -n+2 | awk '{print "    UDP: " $4, $NF}' | sort -u
fi

# Firewall
if command -v ufw &>/dev/null; then
    ufw status 2>/dev/null | head -1 | grep -q active && ok "UFW: active" || warn "UFW: inactive"
elif command -v firewall-cmd &>/dev/null; then
    firewall-cmd --state 2>/dev/null | grep -q running && ok "firewalld: running" || warn "firewalld: not running"
elif command -v iptables &>/dev/null; then
    iptables -L -n 2>/dev/null | grep -q "Chain INPUT" && info "iptables: rules present" || info "iptables: no rules"
fi

# Bandwidth (quick)
if command -v ethtool &>/dev/null; then
    ethtool $(ip -br addr 2>/dev/null | grep -v lo | head -1 | awk '{print $1}') 2>/dev/null | grep "Speed:" | while read line; do
        info "Interface speed: $line"
    done
fi

# Open connections count
open_conn=$(ss -tn 2>/dev/null | wc -l)
info "Active TCP connections: $open_conn"

# ============================================================================
# 6. SECURITY AUDIT
# ============================================================================
echo ""
hr
echo -e "${BOLD}${MAGENTA}[6] SECURITY AUDIT${NC}"
hr

# SSH configuration
if [[ -f /etc/ssh/sshd_config ]]; then
    echo -e "  ${DIM}SSH Configuration:${NC}"
    grep -q 'PermitRootLogin yes' /etc/ssh/sshd_config 2>/dev/null && fail "SSH root login ENABLED" || ok "SSH root login disabled"
    grep -q 'PasswordAuthentication yes' /etc/ssh/sshd_config 2>/dev/null && warn "SSH password auth ENABLED" || ok "SSH password auth disabled"
    grep -q 'PubkeyAuthentication yes' /etc/ssh/sshd_config 2>/dev/null && ok "SSH pubkey auth enabled" || warn "SSH pubkey auth DISABLED"
    grep -q 'X11Forwarding yes' /etc/ssh/sshd_config 2>/dev/null && warn "SSH X11 forwarding ENABLED" || ok "SSH X11 forwarding disabled"
fi

# Sudoers audit
echo -e "  ${DIM}Sudoers audit:${NC}"
grep -r 'NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null | grep -q . && warn "NOPASSWD sudo entries found" || ok "No NOPASSWD sudo entries"
grep -r '!authenticate' /etc/sudoers /etc/sudoers.d 2>/dev/null | grep -q . && warn "!authenticate sudo entries found"

# User audit
echo -e "  ${DIM}User audit:${NC}"
root_users=$(awk -F: '($3 == 0) {print $1}' /etc/passwd 2>/dev/null)
rc=$(echo "$root_users" | wc -l)
if [[ $rc -eq 1 ]] && [[ "$root_users" == "root" ]]; then
    ok "Only root has UID 0"
else
    fail "Extra UID 0 users: $root_users"
fi

# Users with empty passwords
empty_pass=$(awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null)
[[ -n "$empty_pass" ]] && fail "Users with EMPTY passwords: $empty_pass" || ok "No empty password users"

# Users with no password expiry
no_expire=$(awk -F: '($2 != "!" && $2 != "!!" && $2 != "*" && $5 == "") {print $1}' /etc/shadow 2>/dev/null | head -5)
[[ -n "$no_expire" ]] && warn "Users without password expiry: $no_expire"

# World-writable files
echo -e "  ${DIM}World-writable files:${NC}"
ww=$(find /etc /bin /sbin /usr/bin /usr/sbin -xdev -type f -perm -0002 2>/dev/null | wc -l)
if [[ $ww -eq 0 ]]; then ok "No world-writable system files"
else warn "$ww world-writable files found (check /etc, /usr)"
fi

# SUID/SGID
suid=$(find / -xdev -type f -perm -4000 2>/dev/null | wc -l)
sgid=$(find / -xdev -type f -perm -2000 2>/dev/null | wc -l)
info "SUID binaries: $suid | SGID binaries: $sgid"
if [[ "$MODE" == "full" ]]; then
    echo -e "  ${DIM}SUID binaries:${NC}"
    find / -xdev -type f -perm -4000 2>/dev/null | sort | while read f; do
        echo "    $f"
    done
fi

# Files with capabilities
if command -v getcap &>/dev/null; then
    caps=$(getcap -r / 2>/dev/null | wc -l)
    info "Files with capabilities: $caps"
fi

# .rhosts / hosts.equiv
[[ -f /etc/hosts.equiv ]] && fail "hosts.equiv exists" || ok "No hosts.equiv"
rh=$(find /home -name .rhosts 2>/dev/null)
[[ -n "$rh" ]] && fail ".rhosts found: $rh" || ok "No .rhosts files"

# Failed logins
if command -v lastb &>/dev/null; then
    fb=$(lastb 2>/dev/null | grep -v btmp | wc -l)
    if [[ $fb -gt 10 ]]; then fail "$fb failed login attempts (recent)"
    elif [[ $fb -gt 0 ]]; then warn "$fb failed login attempts"
    fi
fi

# Open ports (external)
if command -v nmap &>/dev/null && [[ "$MODE" == "full" ]]; then
    echo -e "  ${DIM}Local open ports (nmap):${NC}"
    nmap -sT -p- --min-rate=10000 127.0.0.1 2>/dev/null | grep "open" | while read port; do
        echo "    $port"
    done
fi

# ============================================================================
# 7. SERVICES & SYSTEMD
# ============================================================================
echo ""
hr
echo -e "${BOLD}${CYAN}[7] SERVICES${NC}"
hr

if command -v systemctl &>/dev/null; then
    # Failed units
    fu=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
    if [[ $fu -eq 0 ]]; then ok "No failed systemd units"
    else fail "$fu failed systemd unit(s)"
        systemctl --failed --no-legend 2>/dev/null | while read unit _ _ _; do
            echo "    $unit"
        done
    fi

    # Missed timers
    mt=$(systemctl list-timers --all --no-legend 2>/dev/null | grep -c 'missed' || true)
    [[ $mt -gt 0 ]] && warn "$mt missed timer(s)" || ok "No missed timers"

    # Running services count
    rs=$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | wc -l)
    info "Running services: $rs"

    # Disabled services
    ds=$(systemctl list-unit-files --type=service --state=disabled --no-legend 2>/dev/null | wc -l)
    info "Disabled services: $ds"

    # Service failures details
    if [[ "$MODE" == "full" ]]; then
        echo -e "  ${DIM}Recent service failures (24h):${NC}"
        journalctl -u '*.service' --since "24 hours ago" -p err --no-pager 2>/dev/null | tail -10 | while read line; do
            echo "    $line"
        done
    fi
fi

# Legacy init
for svc in cron crond sshd ssh docker containerd; do
    if pgrep -x "$svc" &>/dev/null; then
        ok "$svc is running"
    fi
done

# ============================================================================
# 8. LOG AUDIT
# ============================================================================
echo ""
hr
echo -e "${BOLD}${CYAN}[8] LOG ANALYSIS${NC}"
hr

# Journal errors
if command -v journalctl &>/dev/null; then
    err_1h=$(journalctl -p err --since "1 hour ago" --no-pager 2>/dev/null | wc -l)
    err_24h=$(journalctl -p err --since "24 hours ago" --no-pager 2>/dev/null | wc -l)
    err_7d=$(journalctl -p err --since "7 days ago" --no-pager 2>/dev/null | wc -l)
    info "Errors: ${err_1h} (1h) / ${err_24h} (24h) / ${err_7d} (7d)"
    if [[ $err_24h -lt 5 ]]; then ok "Error rate: low"
    elif [[ $err_24h -lt 20 ]]; then warn "Error rate: moderate"
    else fail "Error rate: high ($err_24h errors in 24h)"
    fi

    # Critical messages
    crit=$(journalctl -p crit --since "7 days ago" --no-pager 2>/dev/null | wc -l)
    [[ $crit -gt 0 ]] && warn "$crit critical messages in 7 days"
fi

# Log sizes
echo -e "  ${DIM}Log file sizes:${NC}"
for logf in /var/log/syslog /var/log/messages /var/log/kern.log /var/log/auth.log /var/log/dpkg.log; do
    if [[ -f "$logf" ]]; then
        size=$(stat --printf="%s" "$logf" 2>/dev/null)
        sizemb=$((size / 1024 / 1024))
        if [[ $size -gt 1000000000 ]]; then fail "$logf: ${sizemb}MB (over 1GB!)"
        elif [[ $size -gt 500000000 ]]; then warn "$logf: ${sizemb}MB"
        fi
    fi
done

# Logrotate status
if command -v logrotate &>/dev/null; then
    lr=$(stat -c '%y' /var/lib/logrotate/status 2>/dev/null || stat -c '%y' /var/log/logrotate.status 2>/dev/null)
    info "Last logrotate: $lr"
fi

# ============================================================================
# 9. UPDATE & PACKAGE STATUS
# ============================================================================
echo ""
hr
echo -e "${BOLD}${CYAN}[9] PACKAGE & UPDATE STATUS${NC}"
hr

# APT updates
if command -v apt &>/dev/null; then
    up=$(apt list --upgradable 2>/dev/null | grep -c upgradable || true)
    if [[ $up -eq 0 ]]; then ok "No pending APT updates"
    else warn "$up package(s) can be upgraded"
        if [[ "$MODE" == "full" ]]; then
            echo -e "  ${DIM}Pending updates:${NC}"
            apt list --upgradable 2>/dev/null | tail -n+2 | while read pkg ver rest; do
                echo "    $pkg ($ver)"
            done
        fi
    fi
fi

# Kernel
kv=$(uname -r)
info "Kernel: $kv"

# Newer kernel available?
available_kernels=$(apt list --upgradable 2>/dev/null | grep -c "linux-image" || true)
[[ $available_kernels -gt 0 ]] && warn "$available_kernels kernel update(s) available"

# Last update
if [[ -f /var/log/apt/history.log ]]; then
    lu=$(grep 'Start-Date:' /var/log/apt/history.log | tail -1 | cut -d: -f2-)
    info "Last update: $lu"
fi

# Reboot required
if [[ -f /var/run/reboot-required ]]; then
    fail "System restart REQUIRED"
    cat /var/run/reboot-required 2>/dev/null
else
    ok "No restart required"
fi

# ============================================================================
# 10. PROCESS ANALYSIS
# ============================================================================
echo ""
hr
echo -e "${BOLD}${CYAN}[10] PROCESS ANALYSIS${NC}"
hr

# Zombie processes
zom=$(ps -eo stat | grep -c '^Z' || true)
if [[ $zom -eq 0 ]]; then ok "No zombie processes"
else fail "$zom zombie process(es)"
    ps aux 2>/dev/null | grep ' Z ' | head -5
fi

# Blocked processes
blk=$(ps -eo stat | grep -c '^D' || true)
[[ $blk -gt 0 ]] && warn "$blk blocked process(es) in D state"

# Total
pcount=$(ps --no-headers -eo pid 2>/dev/null | wc -l)
info "Total processes: $pcount"
info "Running: $(ps --no-headers -eo stat 2>/dev/null | grep -c 'R' || true)"
info "Sleeping: $(ps --no-headers -eo stat 2>/dev/null | grep -c 'S' || true)"

# Top CPU
echo -e "  ${DIM}Top 5 CPU consumers:${NC}"
ps aux --sort=-%cpu 2>/dev/null | head -6 | tail -5 | awk '{printf "    %-25s %5s%%\n", $11, $3}'

# Top MEM
echo -e "  ${DIM}Top 5 memory consumers:${NC}"
ps aux --sort=-%mem 2>/dev/null | head -6 | tail -5 | awk '{printf "    %-25s %5s%%\n", $11, $4}'

# ============================================================================
# 11. TIME SYNCHRONIZATION
# ============================================================================
echo ""
hr
echo -e "${BOLD}${CYAN}[11] TIME SYNCHRONIZATION${NC}"
hr

if timedatectl 2>/dev/null | grep -q "NTP enabled: yes\|NTP service: active"; then
    ok "NTP is enabled/synchronized"
else
    warn "NTP is NOT enabled"
fi

if command -v chronyc &>/dev/null; then
    chronyc tracking 2>/dev/null | grep -q "Leap status : Normal" && ok "Chrony: healthy" || warn "Chrony: issue"
    chronyc sources 2>/dev/null | head -5
elif command -v ntpq &>/dev/null; then
    ntpq -p 2>/dev/null | head -5
fi

rtc=$(timedatectl 2>/dev/null | awk -F': ' '/RTC time/{print $2}')
info "RTC time: $rtc"

# Time drift estimate
if command -v chronyc &>/dev/null; then
    drift=$(chronyc tracking 2>/dev/null | grep "Last offset" | awk '{print $4, $5}')
    info "Clock drift: $drift"
fi

# ============================================================================
# 12. KERNEL & SECURITY FEATURES
# ============================================================================
echo ""
hr
echo -e "${BOLD}${MAGENTA}[12] KERNEL HARDENING${NC}"
hr

# ASLR
aslr=$(cat /proc/sys/kernel/randomize_va_space 2>/dev/null)
if [[ $aslr -eq 2 ]]; then ok "ASLR: full randomization"
elif [[ $aslr -eq 1 ]]; then warn "ASLR: partial randomization"
else fail "ASLR: disabled"
fi

# Exec-shield / NX
nx=$(dmesg 2>/dev/null | grep -c "NX (Execute Disable)" || true)
[[ $nx -gt 0 ]] && ok "NX: enabled" || warn "NX: check needed"

# Kernel module loading
mod_disabled=$(cat /proc/sys/kernel/modules_disabled 2>/dev/null)
[[ $mod_disabled -eq 1 ]] && ok "Module loading: disabled (kiosk mode)" || info "Module loading: enabled"

# AppArmor / SELinux
if command -v aa-status &>/dev/null; then
    aa_enforced=$(aa-status 2>/dev/null | grep "profiles are in enforce" | awk '{print $1}')
    info "AppArmor: $aa_enforced profiles enforced"
elif command -v sestatus &>/dev/null; then
    sestatus 2>/dev/null | head -1 | grep -q enabled && ok "SELinux: enabled" || warn "SELinux: disabled"
else
    info "No LSM detected (AppArmor/SELinux not active)"
fi

# yama ptrace
yama=$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null)
case $yama in
    0) warn "ptrace scope: 0 (all processes - weak)" ;;
    1) ok "ptrace scope: 1 (restricted)" ;;
    2) ok "ptrace scope: 2 (admin-only)" ;;
    3) ok "ptrace scope: 3 (no-attach)" ;;
esac

# Core dumps
coredump=$(cat /proc/sys/kernel/core_pattern 2>/dev/null)
info "Core dump pattern: $coredump"

# ============================================================================
# 13. DOCKER / CONTAINER (if present)
# ============================================================================
if command -v docker &>/dev/null; then
    echo ""
    hr
    echo -e "${BOLD}${CYAN}[13] CONTAINERS${NC}"
    hr
    dc=$(docker ps -q 2>/dev/null | wc -l)
    info "Running containers: $dc"
    di=$(docker images -q 2>/dev/null | wc -l)
    info "Docker images: $di"
fi

# ============================================================================
# FINAL SUMMARY
# ============================================================================
echo ""
echo ""
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}${BOLD}              CHECKUP SUMMARY                     ${NC}"
echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}PASS: ${PC}${NC}"
echo -e "  ${YELLOW}WARN: ${WC}${NC}"
echo -e "  ${RED}FAIL: ${FC}${NC}"
echo -e "  ${BLUE}INFO: ${IC}${NC}"

total=$((PC + WC + FC))
score=0
[[ $total -gt 0 ]] && score=$((100 * PC / total))

echo ""
echo -e "  ${BOLD}HEALTH SCORE: ${score}%${NC}"
echo ""

if [[ $score -ge 90 ]]; then
    echo -e "  ${GREEN}${BOLD}EXCELLENT: System is in optimal condition.${NC}"
elif [[ $score -ge 75 ]]; then
    echo -e "  ${GREEN}${BOLD}GOOD: Minor issues found, review warnings.${NC}"
elif [[ $score -ge 50 ]]; then
    echo -e "  ${YELLOW}${BOLD}FAIR: Some issues need attention.${NC}"
elif [[ $score -ge 25 ]]; then
    echo -e "  ${YELLOW}${BOLD}POOR: Several issues found, prioritize fixes.${NC}"
else
    echo -e "  ${RED}${BOLD}CRITICAL: Immediate action required.${NC}"
fi

echo ""
echo -e "  ${DIM}Report generated: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "  ${DIM}Mode: ${MODE}${NC}"
echo -e "  ${DIM}Tool version: v${VERSION}${NC}"
echo ""
