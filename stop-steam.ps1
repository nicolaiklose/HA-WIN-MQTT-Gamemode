$ErrorActionPreference = 'Stop'
Get-Process steam -ErrorAction SilentlyContinue | Stop-Process -Force
