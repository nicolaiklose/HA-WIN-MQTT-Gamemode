# Start-ZockenListener_final.ps1 (patched waits + schtasks invocation fix)
$ErrorActionPreference = 'Stop'

# --- Config ---
$BrokerHost = 'homeassistant.local'
$BrokerPort = 1883
$Topic      = 'windows/klose-xmg/zocken'

$FallbackUser = 'mqtt_pc'
$FallbackPass = ''   # fill in or use registry secrets

$MosqSub   = 'C:\Program Files\mosquitto\mosquitto_sub.exe'
$PsExec    = 'C:\Windows\System32\PsExec.exe'
$ZockenPath= 'C:\Scripts\zocken.ps1'

$LogPath = 'C:\Scripts\listener.log'
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null

function Write-Log([string]$msg){
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  Add-Content -Path $LogPath -Value "[$ts] $msg"
}

function Get-MqttCredentials {
  $registryPath = 'HKLM:\SOFTWARE\Zocken\Secrets'
  if (Test-Path $registryPath) {
    try {
      $user = (Get-ItemProperty $registryPath -Name 'MqttUser' -ErrorAction Stop).MqttUser
      $blob = (Get-ItemProperty $registryPath -Name 'MqttPass' -ErrorAction Stop).MqttPass
      if ($blob) {
        $secure = ConvertTo-SecureString $blob -Scope LocalMachine
        $plain  = [System.Net.NetworkCredential]::new('', $secure).Password
        return @{ User=$user; Pass=$plain }
      }
    } catch { Write-Log "Secrets read failed: $($_.Exception.Message)" }
  }
  Write-Log "Registry credentials not found. Using fallback plaintext (less secure)."
  return @{ User=$FallbackUser; Pass=$FallbackPass }
}

function Get-ArcadeSessionId {
  $lines = (quser 2>$null) | ForEach-Object { $_.TrimEnd() }
  $line  = $lines | Where-Object { $_ -match '^\s*arcade\b' } | Select-Object -First 1
  if (-not $line) { return $null }
  if ($line -match '\s(\d+)\s+(Aktiv|Getr\.)') { return [int]$Matches[1] }
  $m = [regex]::Matches($line, '\s(\d+)\s')
  if ($m.Count -gt 0) { return [int]$m[$m.Count-1].Groups[1].Value }
  return $null
}

# preflight
foreach($p in @($MosqSub,$PsExec,$ZockenPath)){
  if(-not (Test-Path $p)){ throw "$p not found" }
}

$creds = Get-MqttCredentials
$MqttUser = $creds.User
$MqttPass = $creds.Pass

Write-Log ("Listener starting. Broker: {0}:{1} Topic: {2} User: {3}" -f $BrokerHost,$BrokerPort,$Topic,$MqttUser)

while($true){
  try{
    Write-Log "Connecting to MQTT broker $BrokerHost..."
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $MosqSub
    $psi.Arguments = "-h `"$BrokerHost`" -p $BrokerPort -t `"$Topic`" -u `"$MqttUser`" -P `"$MqttPass`" -v"
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    Write-Log "mosquitto_sub started (PID $($proc.Id))."

    while(-not $proc.HasExited){
      $line = $proc.StandardOutput.ReadLine()
      if([string]::IsNullOrWhiteSpace($line)){ continue }
      Write-Log "MQTT: $line"
      $parts = $line.Split(' ',2)
      if($parts.Count -lt 2){ continue }
      $payload = $parts[1].Trim().ToLowerInvariant()

      switch($payload){
        'enable'{
          Write-Log "Action: ENABLE"
          $sid = Get-ArcadeSessionId
          if(-not $sid){ Write-Log "Arcade session not found. Skipping enable."; continue }

          # 1) tscon
          Write-Log "Calling tscon to attach session $sid to console"
          & $PsExec -accepteula -s tscon $sid /dest:console
          Start-Sleep -Seconds 4   # increased wait for session attach / desktop init

          # 2) display/audio without steam
          Write-Log "Running zocken.ps1 -Enable -NoSteam in session $sid"
          & $PsExec -accepteula -i $sid -s powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ZockenPath -Enable -NoSteam
          Start-Sleep -Seconds 6   # allow EDID/audio stack to settle

          # 3) start steam task (fixed: no -NoNewWindow together with -WindowStyle)
          Write-Log "Triggering scheduled task Arcade-StartSteam"
          & schtasks.exe /Run /TN "Arcade-StartSteam" | Out-Null
        }
        'disable'{
          Write-Log "Action: DISABLE"
          $sid = Get-ArcadeSessionId
          if(-not $sid){ Write-Log "Arcade session not found. Skipping disable."; continue }

          Write-Log "Triggering scheduled task Arcade-StopSteam"
          & schtasks.exe /Run /TN "Arcade-StopSteam" | Out-Null
          Start-Sleep -Seconds 2

          Write-Log "Running zocken.ps1 -Disable -NoSteam in session $sid"
          & $PsExec -accepteula -i $sid -s powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ZockenPath -Disable -NoSteam
          Start-Sleep -Seconds 2

          Write-Log "Disconnecting Arcade session (showing logon screen)"
          & $PsExec -accepteula -i $sid -s tsdiscon

        }
        default{
          Write-Log "Unknown payload: $payload"
        }
      }
    }

    Write-Log "mosquitto_sub exited. Waiting 5s before reconnect."
    Start-Sleep -Seconds 5
  } catch {
    Write-Log "Listener exception: $($_.Exception.Message). Reconnect in 5s."
    Start-Sleep -Seconds 5
  }
}
