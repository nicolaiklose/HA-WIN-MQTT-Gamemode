#Requires -RunAsAdministrator
param(
  [switch]$Enable,
  [switch]$Disable,
  [string]$TargetPnPId = 'SECA50D',
  [int]$Width  = 1920,
  [int]$Height = 1080,
  [int]$Hz     = 60,
  [string]$AudioId,
  [string]$AudioName,
  [string]$AudioMatch = 'EPSON|PJ|HDMI|NVIDIA|AMD|Intel',
  [switch]$NoSteam
)

$global:ZockenLog = 'C:\ProgramData\zocken_task.log'
$branch = if ($Enable) {'Enable'} elseif ($Disable) {'Disable'} else {'None'}
$bound  = ($PSBoundParameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; '
"=== $(Get-Date -Format s) branch=$branch bound=[$bound]" | Out-File $global:ZockenLog -Append -Encoding utf8
try { Start-Transcript -Path $global:ZockenLog -Append -ErrorAction SilentlyContinue } catch {}

Import-Module DisplayConfig -ErrorAction Stop
Import-Module AudioDeviceCmdlets -ErrorAction Stop

$steamExePath = $null
foreach ($p in @(
  'C:\Spiele\Steam\steam.exe',
  "$env:ProgramFiles\Steam\steam.exe",
  "$env:ProgramFiles(x86)\Steam\steam.exe"
)) { if (Test-Path $p) { $steamExePath = $p; break } }

$AudioStateFile = Join-Path $env:ProgramData 'zocken_audio_prev.txt'

function Resolve-AudioTarget {
  param([string]$NameHint, [string]$Id, [string]$Name, [string]$Match)
  $list = Get-AudioDevice -List -ErrorAction SilentlyContinue | Where-Object { $_.Type -eq 'Playback' }
  if ($Id) { $t = $list | Where-Object { $_.ID -eq $Id } | Select-Object -First 1; if ($t) { return $t } }
  if ($Name) { $t = $list | Where-Object { $_.Name -eq $Name } | Select-Object -First 1; if ($t) { return $t } }
  if ($NameHint) { $t = $list | Where-Object { $_.Name -like ("*" + $NameHint + "*") } | Select-Object -First 1; if ($t) { return $t } }
  if ($Match) { $t = $list | Where-Object { $_.Name -match $Match } | Select-Object -First 1; if ($t) { return $t } }
  $t = $list | Where-Object { $_.Name -match 'HDMI' } | Select-Object -First 1
  return $t
}

$all = Get-DisplayInfo
$projector = $all | Where-Object { $_.DevicePath -like "*#${TargetPnPId}#*" } | Select-Object -First 1
if (-not $projector) { Write-Error "Beamer nicht gefunden."; try { Stop-Transcript | Out-Null } catch {}; exit 1 }

if ($Disable -and $Enable) { Write-Error "Nur -Enable ODER -Disable."; try { Stop-Transcript | Out-Null } catch {}; exit 1 }

if ($Disable) {
  if ($projector.Active) {
    Write-Host "Deaktiviere Beamer..."
    Disable-Display -DisplayId $projector.DisplayId -ErrorAction Stop
    Start-Sleep 1
  } else { Write-Host "Beamer bereits aus." }

  try {
    if (Test-Path $AudioStateFile) {
      $prevStored = Get-Content -Path $AudioStateFile -ErrorAction SilentlyContinue
      if ($prevStored) {
        $prevId = $prevStored | Select-Object -First 1
        $prevName = ($prevStored | Select-Object -Skip 1) -join "`n"
        $ok = $false
        if ($prevId) { try { Set-AudioDevice -Id $prevId -ErrorAction Stop; $ok = $true } catch {} }
        if (-not $ok -and $prevName) {
          $cand = (Get-AudioDevice -List | Where-Object { $_.Type -eq 'Playback' -and $_.Name -eq $prevName } | Select-Object -First 1)
          if ($cand) { try { Set-AudioDevice -Id $cand.ID -ErrorAction Stop; $ok = $true } catch {} }
        }
        foreach($role in @('Console','Multimedia','Communications')){
          try { Set-AudioDevice -Id (Get-AudioDevice -Playback).ID -Role $role -ErrorAction SilentlyContinue } catch {}
        }
        if ($ok) { Write-Host "Audio zurueckgesetzt." } else { Write-Warning "Audio-Restore: kein passendes aktiviertes Geraet gefunden." }
      }
      Remove-Item $AudioStateFile -Force -ErrorAction SilentlyContinue
    }
  } catch {
    Write-Warning ("Audio-Restore fehlgeschlagen: {0}" -f $_.Exception.Message)
  }

  $steam = Get-Process -Name steam -ErrorAction SilentlyContinue
  if ($steam) {
    Write-Host "Beende Steam..."
    if ($steamExePath) { Start-Process $steamExePath -ArgumentList "-shutdown" -ErrorAction SilentlyContinue }
    else { $steam | Stop-Process -Force -ErrorAction SilentlyContinue }
    Start-Sleep 5
    if (Get-Process -Name steam -ErrorAction SilentlyContinue) {
      Get-Process -Name steam -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
  }

  Get-DisplayInfo | Format-Table DisplayId,DisplayName,Active,Primary,Position,Mode,ConnectionType
  try { Stop-Transcript | Out-Null } catch {}
  exit 0
}

if ($Enable) {

  if (-not $projector.Active) {
    Write-Host "Aktiviere Beamer..."
    Enable-Display -DisplayId $projector.DisplayId -ErrorAction Stop
    Start-Sleep 1
  }

  $projector = Get-DisplayInfo | Where-Object { $_.DisplayId -eq $projector.DisplayId }
  if (-not $projector.Mode -or $projector.Mode -notlike "$Widthx$Height@*") {
    Write-Host "Setze Aufloesung..."
    Set-DisplayResolution  -DisplayId $projector.DisplayId -Width $Width -Height $Height -ErrorAction SilentlyContinue
    Set-DisplayRefreshRate -DisplayId $projector.DisplayId -RefreshRate $Hz -ErrorAction SilentlyContinue
    Start-Sleep 1
  }

  $projector = Get-DisplayInfo | Where-Object { $_.DisplayId -eq $projector.DisplayId }
  if (-not $projector.Primary) {
    $maxRight = 0
    Get-DisplayInfo | Where-Object { $_.Active -and $_.DisplayId -ne $projector.DisplayId } | ForEach-Object {
      if ($_.Mode -match '(\d+)x(\d+)') {
        $w=[int]$Matches[1]; $h=[int]$Matches[2]
        if ($_.Rotation -in @('Rotate90','Rotate270')) { $t=$w; $w=$h; $h=$t }
        $pos=($_.Position -split '\s+'); $x=[int]$pos[0]
        $r=$x+$w; if ($r -gt $maxRight) { $maxRight=$r }
      }
    }
    Write-Host "Positioniere Beamer rechts..."
    Set-DisplayPosition -DisplayId $projector.DisplayId -X $maxRight -Y 0 -ErrorAction SilentlyContinue
    Start-Sleep 1
  } else {
    Write-Host "Beamer ist aktuell Primaer -> Positionierung uebersprungen."
  }

  try {
    $prev = (Get-AudioDevice -Playback -ErrorAction SilentlyContinue)
    if ($prev) { Set-Content -Path $AudioStateFile -Value @($prev.ID, $prev.Name) -Encoding ASCII -Force }

    $target = Resolve-AudioTarget -NameHint $projector.DisplayName -Id $AudioId -Name $AudioName -Match $AudioMatch
    if ($target) {
      Write-Host ("Audio -> {0}" -f $target.Name)
      $ok = $false
      try { Set-AudioDevice -Id $target.ID -ErrorAction Stop; $ok = $true } catch {}
      if ($ok) {
        foreach($role in @('Console','Multimedia','Communications')){
          try { Set-AudioDevice -Id $target.ID -Role $role -ErrorAction SilentlyContinue } catch {}
        }
      } else {
        Write-Warning "Set-AudioDevice mit -Id fehlgeschlagen. Ist das Geraet aktiviert?"
      }
    } else {
      Write-Warning "Kein passendes Wiedergabegeraet gefunden. Nutze -AudioId oder -AudioName."
      Get-AudioDevice -List | Where-Object Type -eq 'Playback' | Format-Table Index,Name,ID,Type,Default
    }
  } catch {
    Write-Warning ("Audio-Switch fehlgeschlagen: {0}" -f $_.Exception.Message)
  }

  if (-not $NoSteam) {
$steamWasRunning = $false
  if (Get-Process -Name steam -ErrorAction SilentlyContinue) { $steamWasRunning=$true }
  Start-Process "steam://open/bigpicture" -ErrorAction SilentlyContinue
  Start-Sleep 2
  if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue) -and $steamExePath) {
    Start-Process $steamExePath -ArgumentList "-tenfoot -fulldesktopres" -ErrorAction SilentlyContinue
    Start-Sleep 6
    Start-Process "steam://open/bigpicture" -ErrorAction SilentlyContinue
  }

  
}
Get-DisplayInfo | Format-Table DisplayId,DisplayName,Active,Primary,Position,Mode,ConnectionType
  try { Stop-Transcript | Out-Null } catch {}
  exit 0
}

Write-Host "Nutzung:"
Write-Host "  .\zocken.ps1 -Enable [-NoSteam] [-AudioId <ID>] [-AudioName '<Name>'] [-AudioMatch 'regex']"
Write-Host "  .\zocken.ps1 -Disable"
