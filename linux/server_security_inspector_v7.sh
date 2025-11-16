#!/bin/bash
################################################################################
# Linux Server Security Audit Script
#
# Description:
#   Comprehensive security assessment tool that analyzes Linux server security
#   posture, detects threats, and provides prioritized recommendations.
#
# Features:
#   - SSH configuration analysis
#   - Failed login attempt tracking with IP geolocation
#   - Firewall and network security assessment
#   - User privilege audit (sudo/NOPASSWD detection)
#   - Docker container security check
#   - Dynamic threat level assessment (CRITICAL/HIGH/MEDIUM/LOW)
#   - Prioritized security recommendations with ready-to-execute commands
#   - Security scoring system (0-10)
#
# Usage:
#   sudo ./server_security_inspector_v7.sh
#
# Requirements:
#   - Root/sudo privileges
#   - Optional: whois, nslookup, host (for IP geolocation)
#
# Output:
#   - Comprehensive security report with:
#     * Security score and threat level
#     * Attack metrics and attacking IPs with geolocation
#     * SSH, firewall, user, and container security status
#     * Prioritized recommendations (CRITICAL → LOW)
#     * Ready-to-execute remediation commands
#
# Author: Ahmed Belal
# Version: 7.0
# Last Updated: 2025-11-16
# License: MIT
# GitHub: https://github.com/ahmedbelal
################################################################################

set -euo pipefail

# Cleanup temp files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR" /tmp/sshd_test /tmp/ipt 2>/dev/null || true' EXIT

now() { date "+%Y-%m-%d %H:%M:%S %Z"; }
has() { command -v "$1" >/dev/null 2>&1; }
require_root() { [ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }; }

read_auth_log() {
  if has journalctl; then journalctl --no-pager -u ssh --since "30 days ago" 2>/dev/null || true; fi
  if [ -f /var/log/auth.log ]; then cat /var/log/auth.log* 2>/dev/null || true; fi
}

read_syslog() {
  if [ -f /var/log/syslog ]; then cat /var/log/syslog 2>/dev/null || true; fi
}

# Country code to name mapping
get_country_name() {
    case "$1" in
        IR) echo "Iran" ;;
        CN) echo "China" ;;
        US) echo "United States" ;;
        RU) echo "Russia" ;;
        IN) echo "India" ;;
        BR) echo "Brazil" ;;
        DE) echo "Germany" ;;
        FR) echo "France" ;;
        GB) echo "United Kingdom" ;;
        AU) echo "Australia" ;;
        CA) echo "Canada" ;;
        JP) echo "Japan" ;;
        KR) echo "South Korea" ;;
        NL) echo "Netherlands" ;;
        SG) echo "Singapore" ;;
        HK) echo "Hong Kong" ;;
        VN) echo "Vietnam" ;;
        TH) echo "Thailand" ;;
        ID) echo "Indonesia" ;;
        PL) echo "Poland" ;;
        UA) echo "Ukraine" ;;
        TR) echo "Turkey" ;;
        IT) echo "Italy" ;;
        ES) echo "Spain" ;;
        MX) echo "Mexico" ;;
        AR) echo "Argentina" ;;
        ZA) echo "South Africa" ;;
        EG) echo "Egypt" ;;
        SA) echo "Saudi Arabia" ;;
        AE) echo "UAE" ;;
        IL) echo "Israel" ;;
        SE) echo "Sweden" ;;
        NO) echo "Norway" ;;
        FI) echo "Finland" ;;
        DK) echo "Denmark" ;;
        CH) echo "Switzerland" ;;
        AT) echo "Austria" ;;
        BE) echo "Belgium" ;;
        CZ) echo "Czech Republic" ;;
        RO) echo "Romania" ;;
        BG) echo "Bulgaria" ;;
        GR) echo "Greece" ;;
        PT) echo "Portugal" ;;
        HU) echo "Hungary" ;;
        IE) echo "Ireland" ;;
        LV) echo "Latvia" ;;
        LT) echo "Lithuania" ;;
        EE) echo "Estonia" ;;
        SK) echo "Slovakia" ;;
        SI) echo "Slovenia" ;;
        HR) echo "Croatia" ;;
        RS) echo "Serbia" ;;
        *) echo "$1" ;;
    esac
}

# Fast IP geolocation using multiple methods
get_ip_location() {
    local ip="$1"
    local cache_file="$TMPDIR/ip_${ip}"

    # Return cached result if exists
    if [ -f "$cache_file" ]; then
        cat "$cache_file"
        return
    fi

    local result=""

    # Method 1: whois (most reliable, offline)
    if has whois && [ -z "$result" ]; then
        local whois_data=$(timeout 1 whois "$ip" 2>/dev/null || echo "")
        if [ -n "$whois_data" ]; then
            local country_code=$(echo "$whois_data" | grep -i "^country:" | head -1 | awk '{print $2}')
            local netname=$(echo "$whois_data" | grep -i "^netname:\|^NetName:" | head -1 | cut -d: -f2- | xargs)
            local org=$(echo "$whois_data" | grep -i "^org-name:\|^organization:" | head -1 | cut -d: -f2- | xargs)

            if [ -n "$country_code" ]; then
                local country_name=$(get_country_name "$country_code")
                result="${country_name} (${country_code})"
                [ -n "$org" ] && result="${result} | ${org}" || [ -n "$netname" ] && result="${result} | ${netname}"
            fi
        fi
    fi

    # Method 2: nslookup reverse DNS
    if has nslookup && [ -z "$result" ]; then
        local hostname=$(timeout 1 nslookup "$ip" 2>/dev/null | grep "name =" | awk '{print $NF}' | sed 's/\.$//')
        if [ -n "$hostname" ]; then
            result="Hostname: ${hostname}"
        fi
    fi

    # Method 3: host command
    if has host && [ -z "$result" ]; then
        local hostname=$(timeout 1 host "$ip" 2>/dev/null | grep "domain name pointer" | awk '{print $NF}' | sed 's/\.$//')
        if [ -n "$hostname" ]; then
            result="Hostname: ${hostname}"
        fi
    fi

    # Default if all methods fail
    [ -z "$result" ] && result="Unknown"

    # Cache the result
    echo "$result" > "$cache_file"
    echo "$result"
}

# scoring
score=0
max_score=10
add_score() { score=$(awk -v s="$score" -v i="$1" 'BEGIN{printf("%.2f", s+i)}'); }
cap_score() {
    if awk "BEGIN{exit !($score > $max_score)}"; then
        score="$max_score"
    fi
}

sep() { printf "\n%s\n\n" "──────────────────────────────────────────────────────────────"; }

require_root

host_ip=$(hostname -I | awk '{print $1}')
pub_ip=$(timeout 2 curl -fsS http://checkip.amazonaws.com 2>/dev/null || echo "N/A")

ssh_bin=$(command -v sshd || echo "/usr/sbin/sshd")

ssh_port="N/A"
perm_root="N/A"
pass_auth="N/A"
pubkey_auth="N/A"
max_auth="N/A"
login_grace="N/A"

if [ -x "$ssh_bin" ] && "$ssh_bin" -T > /tmp/sshd_test 2>/dev/null; then
  ssh_port=$(grep -i "^port " /tmp/sshd_test | awk '{print $2}' | head -1)
  perm_root=$(grep -i "^permitrootlogin " /tmp/sshd_test | awk '{print $2}')
  pass_auth=$(grep -i "^passwordauthentication " /tmp/sshd_test | awk '{print $2}')
  pubkey_auth=$(grep -i "^pubkeyauthentication " /tmp/sshd_test | awk '{print $2}')
  max_auth=$(grep -i "^maxauthtries " /tmp/sshd_test | awk '{print $2}')
  login_grace=$(grep -i "^logingracetime " /tmp/sshd_test | awk '{print $2}')
fi

active_sessions=$(who || true)

auth_all="$(read_auth_log | tr -d '\000')"

failed_total=$(echo "$auth_all" | grep -i "Failed password" | wc -l || echo 0)
failed_10m=$(echo "$auth_all" | tail -n 2000 | grep -i "Failed password" | wc -l || echo 0)

# Extract attacking IPs with geolocation
attack_ips_raw=$(echo "$auth_all" | grep -i "Failed password" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -nr | head -5)

ufw_rules=$(ufw status 2>/dev/null || echo "Status: inactive")

ipt_input_policy=$(iptables -S INPUT 2>/dev/null | head -1 | sed 's/^-P INPUT //;s/ -.*//' || echo "N/A")
blocked_pkts="N/A"
if iptables -L INPUT -v -n > /tmp/ipt 2>/dev/null; then
  blocked_pkts=$(awk '/DROP/ {pkts+=$1; bytes+=$2} END{printf("%d packets / %d bytes", pkts, bytes)}' /tmp/ipt)
fi

shell_users=$(awk -F: '$7 ~ /(bash|zsh|sh)$/ {printf "•  %s (UID %s)\n",$1,$3}' /etc/passwd)
sudo_nopass=$(grep -R "NOPASSWD" /etc/sudoers /etc/sudoers.d 2>/dev/null || true)

ssh_keys_summary=""
while IFS=: read -r user _ uid gid _ home shell; do
  case "$shell" in *nologin*|*false*) continue ;; esac
  if [ -d "$home/.ssh" ]; then
    if [ -f "$home/.ssh/authorized_keys" ]; then
        ssh_keys_summary+="•  $user: authorized_keys present\n"
    else
        ssh_keys_summary+="•  $user: authorized_keys missing\n"
    fi
  else
    ssh_keys_summary+="•  $user: ~/.ssh missing\n"
  fi
done < /etc/passwd

docker_ok=false
docker_list=""
if has docker && docker ps >/dev/null 2>&1; then
  docker_ok=true
  docker_list=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | sed '1 s/^/Name\tImage\tStatus\tPorts\n/')
fi

top_usernames=$(echo "$auth_all" | grep -i "Failed password" | awk '{for(i=1;i<=NF;i++) if($i=="for") print $(i+1)}' | sed 's/invalid//' | sed 's/[ :]//g' | sort | uniq -c | sort -nr | head -10)

# scoring
[ "$perm_root" = "no" ] && add_score 1.5
[ "$pass_auth" = "no" ] && add_score 1.5
[ "$pubkey_auth" = "yes" ] && add_score 1.5
echo "$ufw_rules" | grep -qi "Status: active" && add_score 1
[ "$ssh_port" != "22" ] && [ "$ssh_port" != "N/A" ] && add_score 0.5
if [ "$docker_ok" = true ]; then
    unhealthy=$(docker ps --format '{{.Names}} {{.Status}}' | grep -viE 'healthy|Up' || true)
    if [ -z "$unhealthy" ]; then
        add_score 1
    fi
fi
cap_score

clear 2>/dev/null || true
echo "COMPREHENSIVE SECURITY DEEP-DIVE REPORT"
echo
echo "📅 Generated at: $(now)"
echo "🌐 Host IP: $host_ip  Public IP: $pub_ip"
sep

echo "📊 SECURITY SUMMARY"
printf "Overall Security Score: %s/10. " "$score"
awk "BEGIN{print ($score>=8)?\"Very Strong\":($score>=6)?\"Strong\":\"Needs Attention\"}"
sep

echo "🚨 CRITICAL ATTACK METRICS"
echo "•  Total Failed Login Attempts: $failed_total"
echo "•  Currently Failed (last ~2000 lines): $failed_10m"
echo
echo "Top Attacking IPs (with geolocation):"
if [ -n "$attack_ips_raw" ]; then
    echo "$attack_ips_raw" | while read -r count ip; do
        if [ -n "$ip" ]; then
            location=$(get_ip_location "$ip")
            echo "•  $ip ($count attempts) - $location"
        fi
    done
else
    echo "•  No significant attacks detected"
fi
sep

echo "✅ SSH SECURITY CONFIGURATION"
echo "Port: $ssh_port"
echo "Root Login: $perm_root"
echo "Password Auth: $pass_auth"
echo "Public Key Auth: $pubkey_auth"
echo "MaxAuthTries: $max_auth"
echo "LoginGraceTime: $login_grace"
echo
echo "Active SSH Sessions:"
if [ -n "$active_sessions" ]; then
    echo "$active_sessions" | sed 's/^/•  /'
else
    echo "• None"
fi
sep

echo "🛡️ FIREWALL & NETWORK SECURITY"
echo "UFW Rules:"
echo "$ufw_rules"
echo
echo "Iptables:"
echo "• INPUT Policy: $ipt_input_policy"
echo "• Blocked: $blocked_pkts"
sep

echo "👥 USER SECURITY"
echo "$shell_users"
echo
echo "Users with NOPASSWD sudo:"
echo "${sudo_nopass:-• None}"
echo
echo "SSH Key Distribution:"
printf "%b" "$ssh_keys_summary"
sep

echo "🐳 CONTAINER SECURITY"
if [ -n "$docker_list" ]; then
    echo "$docker_list"
else
    echo "• Docker not running or not installed"
fi
sep

echo "🔍 THREAT INTELLIGENCE"
if [ -n "$top_usernames" ]; then
    echo "$top_usernames" | sed 's/^/• /'
else
    echo "• No failed login attempts detected"
fi
sep

###############################################
# 🔥 Dynamic Recommendations (enhanced)
###############################################

# Calculate threat level
threat_level="LOW"
if [ "$failed_total" -gt 1000 ]; then
    threat_level="CRITICAL"
elif [ "$failed_total" -gt 500 ]; then
    threat_level="HIGH"
elif [ "$failed_total" -gt 100 ]; then
    threat_level="MEDIUM"
fi

echo "🎯 PRIORITIZED SECURITY RECOMMENDATIONS"
echo "Threat Level: $threat_level | Security Score: $score/10"
echo

rec_num=1

# 🔴 CRITICAL Priority
if [ "$threat_level" = "CRITICAL" ] || [ "$threat_level" = "HIGH" ]; then
    echo "🔴 CRITICAL PRIORITY:"
    if [ -n "$attack_ips_raw" ]; then
        echo "$rec_num. Block attacking IPs immediately:"
        echo "$attack_ips_raw" | while read -r count ip; do
            [ -n "$ip" ] && echo "   sudo ufw deny from $ip"
        done
        rec_num=$((rec_num + 1))
    fi
fi

if [ "$pass_auth" = "yes" ] && [ "$failed_total" -gt 100 ]; then
    echo "$rec_num. 🔴 CRITICAL: Disable SSH password authentication NOW"
    echo "   Command: sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && sudo systemctl restart sshd"
    rec_num=$((rec_num + 1))
elif [ "$pass_auth" = "yes" ] && [ "$failed_total" -gt 20 ]; then
    echo "$rec_num. 🟠 HIGH: Disable SSH password authentication"
    echo "   Command: sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config"
    rec_num=$((rec_num + 1))
fi

if ! echo "$ufw_rules" | grep -qi "Status: active"; then
    echo "$rec_num. 🔴 CRITICAL: Enable firewall immediately"
    echo "   Command: sudo ufw enable"
    rec_num=$((rec_num + 1))
fi

if echo "$sudo_nopass" | grep -q .; then
    sudo_count=$(echo "$sudo_nopass" | wc -l)
    echo "$rec_num. 🔴 CRITICAL: Remove NOPASSWD sudo ($sudo_count users affected)"
    echo "   Review: /etc/sudoers and /etc/sudoers.d/"
    rec_num=$((rec_num + 1))
fi

echo
echo "🟠 HIGH PRIORITY:"

if [ "$perm_root" = "yes" ]; then
    echo "$rec_num. Disable SSH root login"
    echo "   Command: sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config"
    rec_num=$((rec_num + 1))
fi

if [ "$ssh_port" = "22" ] && [ "$failed_total" -gt 50 ]; then
    echo "$rec_num. Change SSH port from default (under attack)"
    echo "   Edit /etc/ssh/sshd_config: Port 2222"
    rec_num=$((rec_num + 1))
fi

if [ "$failed_total" -gt 50 ] && ! has fail2ban; then
    echo "$rec_num. Install fail2ban for auto-blocking"
    echo "   Command: sudo apt update && sudo apt install fail2ban -y"
    rec_num=$((rec_num + 1))
fi

if echo "$ufw_rules" | grep -Eq "32768|32769"; then
    echo "$rec_num. Close high ephemeral ports (32768-32769)"
    echo "   Command: sudo ufw delete allow 32768 && sudo ufw delete allow 32769"
    rec_num=$((rec_num + 1))
fi

echo
echo "🟡 MEDIUM PRIORITY:"

if echo "$docker_list" | grep -qi traefik; then
    echo "$rec_num. Enable rate limiting in Traefik"
    rec_num=$((rec_num + 1))
fi

if [ "$docker_ok" = true ]; then
    echo "$rec_num. Run Trivy security scan on Docker images"
    echo "   Command: docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image --severity HIGH,CRITICAL"
    rec_num=$((rec_num + 1))
fi

if echo "$docker_list" | grep -Eq "portainer|coolify"; then
    echo "$rec_num. Enable 2FA in Portainer/Coolify dashboards"
    rec_num=$((rec_num + 1))
fi

if ls /etc/cron.*/* >/dev/null 2>&1; then
    echo "$rec_num. Review cron jobs for suspicious entries"
    echo "   Command: ls -la /etc/cron.*/*"
    rec_num=$((rec_num + 1))
fi

echo
echo "🟢 LOW PRIORITY:"

if ! has crowdsec; then
    echo "$rec_num. Consider installing CrowdSec IDS"
    echo "   Command: curl -s https://install.crowdsec.net | sudo sh"
    rec_num=$((rec_num + 1))
fi

if [ "$ssh_port" = "22" ] && [ "$failed_total" -lt 50 ]; then
    echo "$rec_num. Consider changing SSH port for security by obscurity"
    rec_num=$((rec_num + 1))
fi

echo "$rec_num. Schedule regular security audits (weekly)"
echo "   Add to cron: 0 2 * * 0 /path/to/sec-check-v1-enhanced.sh > /var/log/security-audit.log"
sep

echo "💡 NEXT STEPS BASED ON THREAT LEVEL:"
case "$threat_level" in
    "CRITICAL")
        echo "⚠️  IMMEDIATE ACTION REQUIRED:"
        echo "1. Block all attacking IPs NOW"
        echo "2. Disable password authentication"
        echo "3. Review logs for breach indicators"
        echo "4. Consider temporary SSH port change"
        ;;
    "HIGH")
        echo "⚠️  URGENT - Act within 24 hours:"
        echo "1. Implement critical recommendations"
        echo "2. Install fail2ban"
        echo "3. Monitor attack patterns"
        echo "4. Review user access"
        ;;
    "MEDIUM")
        echo "📊 Act within this week:"
        echo "1. Follow high priority recommendations"
        echo "2. Strengthen SSH configuration"
        echo "3. Enable automated monitoring"
        ;;
    *)
        echo "✅ Maintain current security posture:"
        echo "1. Follow recommendations by priority"
        echo "2. Schedule regular audits"
        echo "3. Keep system updated"
        ;;
esac
sep

echo "🚧 SECURITY CONCERNS SUMMARY"
echo "⚠️ Issues Found:"
if echo "$sudo_nopass" | grep -q .; then
  echo "• Multiple NOPASSWD sudo users detected"
fi
if echo "$ufw_rules" | grep -Eq "32768|32769"; then
  echo "• High ephemeral ports exposed in UFW"
fi
if ls /etc/cron.*/* >/dev/null 2>&1; then
    echo "• Cron jobs exist - review manually"
fi
if [ "$pass_auth" = "yes" ]; then
    echo "• SSH password authentication enabled"
fi
if [ "$perm_root" = "yes" ]; then
    echo "• SSH root login enabled"
fi
if [ "$ssh_port" = "22" ]; then
    echo "• Using default SSH port"
fi
sep

echo "🎯 CONCLUSION"
if awk "BEGIN{exit !($score >= 8)}"; then
    echo "✅ EXCELLENT: Server security is very strong. Continue monitoring."
elif awk "BEGIN{exit !($score >= 6)}"; then
    echo "✅ GOOD: Server security is acceptable. Follow recommendations for improvement."
else
    echo "⚠️  NEEDS ATTENTION: Server security requires immediate improvement!"
fi
echo "Threat Level: $threat_level | Failed Logins: $failed_total | Score: $score/10"