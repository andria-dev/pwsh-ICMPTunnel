# ICMPTunnel

A reverse shell tunneled through ICMP and written in PowerShell on both ends (Linux server and universal implant).

## Setup

Make sure that you disable the automatic ping response on the Linux server.

```bash
# Bash
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all
```
```powershell
# PowerShell
Write-Output 1 | Out-File /proc/sys/net/ipv4/icmp_echo_ignore_all
```
