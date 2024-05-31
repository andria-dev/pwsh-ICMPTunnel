# ICMPTunnel

A reverse shell tunneled through ICMP and written in PowerShell on both ends (Linux server and universal implant).

## Setup

Make sure that you disable the automatic ping response on the Linux server by setting the `icmp_echo_ignore_all` setting to 1. You can re-enable the automatic ping responses later by setting it to 0 or restarting your computer.

```bash
# Bash
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all
```
```powershell
# PowerShell
Write-Output 1 | Out-File /proc/sys/net/ipv4/icmp_echo_ignore_all
```
