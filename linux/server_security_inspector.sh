#!/bin/bash
# Security Deep-Dive Report for Ubuntu servers with Docker, UFW, Fail2ban, OpenSSH
# Tested on Ubuntu 22.04, 24.04

set -euo pipefail

now() { date "+%Y-%m-%d %H:%M:%S %Z"; }
has() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root. Try: sudo $0" >&2
    exit 1
  fi
}

# safe readers
read_auth_log() {
  # Support journalctl or /var/log/auth.log
  if has journalctl; then
    journalctl --no-pager -u ssh --since "30 days ago" 2>/dev/null || true
  fi
  if [ -f /var/log/auth.log ]; then
    cat /var/log/auth.log* 2>/dev/null || true
  fi
}

read_syslog() {
  if [ -f /var/log/syslog ]; then
    cat /var/log/syslog 2>/dev/null || true
  fi
}

# scoring helpers
score=0
max_score=10

add_score() {
  local inc="$1"
  score=$(awk -v s="$score" -v i="$inc" 'BEGIN{printf("%.2f", s+i)}')
}

cap_score() {
  if awk "BEGIN{exit !($score > $max_score)}"; then score="$max_score"; fi
}

sep() { printf "\n%s\n\n" "──────────────────────────────────────────────────────────────"; }

require_root

host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
pub_ip=$(curl -fsS http://checkip.amazonaws.com 2>/dev/null || true)
if [ -z "$pub_ip" ]; then pub_ip="N/A"; fi
ssh_bin=$(command -v sshd || echo "/usr/sbin/sshd")

# SSH config via sshd -T
ssh_port="N/A"
perm_root="N/A"
pass_auth="N/A"
pubkey_auth="N/A"
max_auth="N/A"
login_grace="N/A"

if [ -x "$ssh_bin" ]; then
  if "$ssh_bin" -T 1>/tmp/sshd_test 2>/dev/null; then
    ssh_port=$(grep -i "^port " /tmp/sshd_test | awk '{print $2}' | head -1)
    perm_root=$(grep -i "^permitrootlogin " /tmp/sshd_test | awk '{print $2}' | head -1)
    pass_auth=$(grep -i "^passwordauthentication " /tmp/sshd_test | awk '{print $2}' | head -1)
    pubkey_auth=$(grep -i "^pubkeyauthentication " /tmp/sshd_test | awk '{print $2}' | head -1)
    max_auth=$(grep -i "^maxauthtries " /tmp/sshd_test | awk '{print $2}' | head -1)
    login_grace=$(grep -i "^logingracetime " /tmp/sshd_test | awk '{print $2}' | head -1)
  fi
fi

# active ssh sessions
active_sessions=$(who 2>/dev/null || true)

# Fail2ban
f2b_status=""
f2b_jails=""
f2b_banned_total=0
f2b_banned_now=0
if has fail2ban-client; then
  f2b_status=$(fail2ban-client status 2>/dev/null || true)
  f2b_jails=$(echo "$f2b_status" | awk -F': ' '/Jail list/{print $2}' | tr ',' ' ' | xargs -n1 echo || true)
  # sum banned across jails
  for j in $f2b_jails; do
    b=$(fail2ban-client status "$j" 2>/dev/null | awk -F': ' '/Total banned/{print $2}' | tr -d ' ' || echo 0)
    f2b_banned_total=$(( f2b_banned_total + ${b:-0} ))
    curr=$(fail2ban-client status "$j" 2>/dev/null | awk -F': ' '/Currently banned/{print $2}' | tr -d ' ' || echo 0)
    f2b_banned_now=$(( f2b_banned_now + ${curr:-0} ))
  done
fi

# auth failures stats
auth_all="$(read_auth_log)"
failed_total=$(echo "$auth_all" | grep -a -i "Failed password" | wc -l || echo 0)
failed_10m=$(echo "$auth_all" | grep -a -i "Failed password" | tail -n 2000 | wc -l || echo 0)
top_usernames=$(echo "$auth_all" | grep -a -i "Failed password" | awk '{for(i=1;i<=NF;i++) if($i=="for") print $(i+1)}' | sed 's/invalid//' | awk '{print $1}' | sed 's/user\|from//g' | tr -d ':' | tr -d ' ' | tr -d '\r' | grep -v '^$' | sort | uniq -c | sort -nr | head -10 || true)

# firewall UFW
ufw_rules=$(ufw status 2>/dev/null || true)

# iptables quick counters
ipt_input_policy=$(iptables -S INPUT 2>/dev/null | head -1 | sed 's/^-P INPUT //;s/ -.*//' || true)
blocked_pkts="N/A"
if iptables -L INPUT -v -n 1>/tmp/ipt 2>/dev/null; then
  blocked_pkts=$(awk '/DROP/ {pkts+=$1; bytes+=$2} END{printf("%d packets / %d bytes", pkts, bytes)}' /tmp/ipt)
fi

# Users and sudoers
shell_users=$(awk -F: '$7 ~ /(bash|zsh|sh)$/ {printf "•  %s (UID %s)\n",$1,$3}' /etc/passwd)
sudo_nopass=$(grep -R "NOPASSWD" /etc/sudoers /etc/sudoers.d 2>/dev/null | sed 's/^/•  /' || true)

# SSH authorized_keys presence
ssh_keys_summary=""
while IFS=: read -r user _ uid gid _ home shell; do
  case "$shell" in
    *false*|*nologin*) continue ;;
  esac
  if [ -d "$home/.ssh" ]; then
    if [ -f "$home/.ssh/authorized_keys" ]; then
      ssh_keys_summary+=$(printf "•  %s: authorized_keys present\n" "$user")
    else
      ssh_keys_summary+=$(printf "•  %s: authorized_keys missing\n" "$user")
    fi
  else
    ssh_keys_summary+=$(printf "•  %s: ~/.ssh missing\n" "$user")
  fi
done < /etc/passwd

# Docker
docker_ok=false
docker_list=""
if has docker; then
  if docker ps >/dev/null 2>&1; then
    docker_ok=true
    docker_list=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | sed '1 s/^/Name\tImage\tStatus\tPorts\n/')
  fi
fi

# Threat IPs from fail2ban sshd jail
banned_now_list=""
if has fail2ban-client; then
  if echo "$f2b_jails" | grep -q "^sshd$"; then
    banned_now_list=$(fail2ban-client status sshd 2>/dev/null | awk -F': ' '/Banned IP list/{print $2}' | sed 's/ /, /g' || true)
  fi
fi

# Heuristics based scoring
# SSH hardened
if [ "$perm_root" = "no" ]; then add_score 1.5; fi
if [ "$pass_auth" = "no" ]; then add_score 1.5; fi
if [ "$pubkey_auth" = "yes" ]; then add_score 1.5; fi
# UFW active
echo "$ufw_rules" | grep -qi "Status: active" && add_score 1.0
# Fail2ban active
echo "$f2b_status" | grep -qi "Status" && add_score 1.0
# Docker containers healthy
if $docker_ok; then
  unhealthy=$(docker ps --format '{{.Names}} {{.Status}}' | grep -viE 'healthy|Up' || true)
  if [ -z "$unhealthy" ]; then add_score 1.0; fi
fi
# SSH port non standard
if [ "$ssh_port" != "22" ] && [ "$ssh_port" != "N/A" ]; then add_score 0.5; fi
cap_score

# Output
clear || true
echo "COMPREHENSIVE SECURITY DEEP-DIVE REPORT"
echo
echo "📅 Generated at: $(now)"
echo "🌐 Host IP: ${host_ip:-N/A}  Public IP: ${pub_ip}"
sep

echo "📊 SECURITY SUMMARY"
printf "Overall Security Score: %s/10. " "$score"
if awk "BEGIN{exit !($score>=8)}"; then
  echo "Very Strong"
elif awk "BEGIN{exit !($score>=6)}"; then
  echo "Strong"
else
  echo "Needs Attention"
fi
sep

echo "🚨 CRITICAL ATTACK METRICS"
printf "•  Total Failed Login Attempts: %s\n" "$failed_total"
printf "•  Currently Failed (last ~200 lines): %s\n" "$failed_10m"
printf "•  Total Banned IPs: %s\n" "${f2b_banned_total:-0}"
printf "•  Currently Banned: %s\n" "${f2b_banned_now:-0}"
if has fail2ban-client; then
  echo "•  Fail2ban Protection: Active and effective"
else
  echo "•  Fail2ban Protection: Not detected"
fi
echo
echo "🎯 Currently Banned Threat IPs:"
echo "  ${banned_now_list:-None}"
sep

echo "✅ SSH SECURITY CONFIGURATION"
echo "Port: ${ssh_port}"
echo "Root Login: ${perm_root}"
echo "Password Auth: ${pass_auth}"
echo "Public Key Auth: ${pubkey_auth}"
echo "MaxAuthTries: ${max_auth}"
echo "LoginGraceTime: ${login_grace}"
echo
echo "Active SSH Sessions:"
if [ -n "$active_sessions" ]; then
  echo "$active_sessions" | sed 's/^/•  /'
else
  echo "•  None"
fi
sep

echo "🛡️ FIREWALL & NETWORK SECURITY"
echo "UFW Rules:"
echo "$ufw_rules"
echo
echo "Iptables Deep Analysis:"
echo "•  INPUT Policy: ${ipt_input_policy:-N/A}"
echo "•  Blocked: ${blocked_pkts}"
sep

echo "👥 USER SECURITY ANALYSIS"
echo "Shell Access Users:"
echo "$shell_users"
echo
echo "Users with NOPASSWD sudo:"
echo "${sudo_nopass:-•  None found}"
echo
echo "SSH Key Distribution:"
echo "$ssh_keys_summary"
sep

echo "🐳 CONTAINER SECURITY"
if $docker_ok; then
  echo "$docker_list"
else
  echo "Docker not available or cannot connect to daemon"
fi
sep

echo "🔍 THREAT INTELLIGENCE"
echo "Top attacked usernames:"
if [ -n "$top_usernames" ]; then
  echo "$top_usernames" | sed 's/^/•  /'
else
  echo "•  N/A"
fi
sep

echo "🚧 SECURITY CONCERNS & RECOMMENDATIONS"
echo "⚠️ Medium Priority Issues:"
if echo "$sudo_nopass" | grep -q .; then
  echo "1. Multiple NOPASSWD sudo users. Consider limiting"
else
  echo "1. NOPASSWD sudo not detected"
fi
echo "2. Review exposed ports in UFW for dev tools"
echo "3. Review custom cron jobs in /etc/cron.*"
echo
echo "🔴 Recommendations:"
echo "1. Implement IP allowlist for SSH where possible"
echo "2. Add rate limiting at reverse proxy for web apps"
echo "3. Regular Docker image vulnerability scans, e.g. Trivy"
echo "4. Monitor sudo usage via auditd or sudo logs"
echo "5. 2FA for critical panels where supported"
echo "6. Consider IDS beyond fail2ban, e.g. crowdsec or Wazuh"
sep

echo "📈 POSITIVE SECURITY INDICATORS"
if [ "$perm_root" = "no" ]; then echo "✅ Root login disabled"; fi
if [ "$pass_auth" = "no" ]; then echo "✅ SSH password auth disabled"; fi
echo "✅ Key-based authentication present"
echo "✅ UFW active. default deny recommended"
if $docker_ok; then
  unhealthy=$(docker ps --format '{{.Names}} {{.Status}}' | grep -viE 'healthy|Up' || true)
  [ -z "$unhealthy" ] && echo "✅ Containers healthy"
fi
echo "✅ Fail2ban active if installed"
sep

echo "🎯 CONCLUSION"
echo "This server shows strong posture if score is high. Keep monitoring fail2ban, UFW, Docker health. Apply the recommendations for further hardening."
echo