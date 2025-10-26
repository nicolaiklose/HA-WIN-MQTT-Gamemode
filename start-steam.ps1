$ErrorActionPreference = 'Stop'

$steamExePath = "C:\Spiele\Steam\steam.exe"

if (-not (Get-Process steam -ErrorAction SilentlyContinue)) {
  Start-Process $steamExePath -ArgumentList "-tenfoot","-fulldesktopres"
  Start-Sleep 2
  Start-Process "steam://open/bigpicture"
}
