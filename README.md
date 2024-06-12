# ICMPTunnel

A plaintext reverse shell tunneled through ICMP written in PowerShell on both ends (Linux server and universal implant).

## Setup

Make sure that you disable the automatic ping response on the Linux server (attacker) by setting the `icmp_echo_ignore_all` setting to 1. You can re-enable the automatic ping responses later by setting it to `0` or restarting your computer.

```bash
# Bash
echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all
```

```powershell
# PowerShell
Write-Output 1 | Out-File /proc/sys/net/ipv4/icmp_echo_ignore_all
```

## Usage

In order to use the ICMP Tunnel, you need to configure the implant to point back to your attacker machine (`$ServerIPAddress` in PowerShell or `#_IPAddress` in DuckyScript). After that you need to deploy both the ICMP tunnel server and implant (the order should not matter).

### Server

Deploying the server is fairly simple after having completed the setup instructions above: import the module and run the `Start-ICMPTunnelServer` cmdlet.

```powershell
Import-Module .\ICMPTunnel.psd1
Start-ICMPTunnelServer
```

You can use the `Get-Help` command to see the allowed parameters.

### Client

You can automatically deploy the implant to the target with an O.MG cable or manually by starting PowerShell on the target, downloading the `ICMPTunnelImplant.ps1` script, and running it.

## Contributing or Modifying

You can run the `dev.ps1` script to easily clear your screen, remove the ICMPTunnel module, re-import the ICMPTunnel module, and run `Start-ICMPTunnelServer`. This is useful because you must remove the ICMPTunnel module before re-importing it to use the updated script every time you change it. PRs and issues are welcome.
