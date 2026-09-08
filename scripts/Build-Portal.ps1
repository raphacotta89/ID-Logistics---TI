<#
.SYNOPSIS
    Gera os arquivos de apoio do portal a partir do printers.json.
.DESCRIPTION
    - printers.js     : catalogo embutido (permite abrir o portal via file://)
    - launchers\*.bat : um instalador por impressora
    - idlprint.reg    : registra o protocolo idlprint:// para o clique unico
#>

[CmdletBinding()]
param(
    [string]$CatalogPath,
    [string]$PortalDir
)

$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $PortalDir)   { $PortalDir   = Join-Path $raiz '..\portal' }
if (-not $CatalogPath) { $CatalogPath = Join-Path $PortalDir 'printers.json' }

if (-not (Test-Path $CatalogPath)) { throw "Catalogo nao encontrado: $CatalogPath" }

$catalogoLido = Get-Content $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$catalogo = @(foreach ($item in $catalogoLido) { $item })
$catalogoPortal = @(
    foreach ($p in $catalogo) {
        [ordered]@{
            id         = $p.id
            setor      = $p.setor
            local      = $p.local
            modelo     = $p.modelo
            fabricante = $p.fabricante
            ip         = $p.ip
            fila       = $p.fila
            colorido   = [bool]$p.colorido
            duplex     = [bool]$p.duplex
            pronto     = [bool]($p.ip -and $p.fila -and $p.driverName)
        }
    }
)
$json = $catalogoPortal | ConvertTo-Json -Depth 5 -Compress

# --- 1. printers.js ---
"window.PRINTERS = $json;" | Set-Content -Path (Join-Path $PortalDir 'printers.js') -Encoding UTF8
Write-Host "  [OK] printers.js gerado ($($catalogo.Count) impressoras)" -ForegroundColor Green

# --- 2. Launchers .bat ---
$launchersDir = Join-Path $PortalDir 'launchers'
if (-not (Test-Path $launchersDir)) { New-Item -ItemType Directory -Path $launchersDir -Force | Out-Null }
Get-ChildItem $launchersDir -Filter *.bat -ErrorAction SilentlyContinue | Remove-Item -Force

foreach ($p in $catalogo) {
    if (-not $p.id) { continue }
    $linhas = @(
        '@echo off'
        "title Instalar impressora - $($p.setor)"
        'echo.'
        "echo   Instalando: $($p.modelo)"
        "echo   Setor.....: $($p.setor)"
        "echo   IP........: $($p.ip)"
        'echo.'
        "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0..\..\scripts\Install-Printer.ps1`" -Id `"$($p.id)`""
    )
    $linhas | Set-Content -Path (Join-Path $launchersDir "$($p.id).bat") -Encoding OEM
}
Write-Host "  [OK] $($catalogo.Count) launcher(s) .bat gerados" -ForegroundColor Green

# --- 3. Handler do protocolo idlprint:// ---
$handlerPs1 = Join-Path $raiz 'Protocol-Handler.ps1'

$handlerLinhas = @(
    '# Recebe uma URL no formato idlprint://<id> e dispara a instalacao.'
    'param([string]$Url)'
    ''
    '$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path'
    "`$id = `$Url -replace '^idlprint:/*', '' -replace '/+`$', ''"
    '$id = [System.Uri]::UnescapeDataString($id).Trim()'
    ''
    "if (`$id -notmatch '^[A-Za-z0-9._-]+`$') {"
    '    Write-Host "  Id invalido recebido pelo protocolo: $id" -ForegroundColor Red'
    '    Start-Sleep -Seconds 4'
    '    exit 1'
    '}'
    ''
    '& (Join-Path $raiz ''Install-Printer.ps1'') -Id $id'
)
$handlerLinhas | Set-Content -Path $handlerPs1 -Encoding UTF8

$handlerEscapado = $handlerPs1 -replace '\\', '\\'
$comandoReg = '@="powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"' + $handlerEscapado + '\" \"%1\""'

$regLinhas = @(
    'Windows Registry Editor Version 5.00'
    ''
    '; Protocolo idlprint:// - ID Logistics'
    '; Rodar UMA VEZ em cada maquina da equipe de TI (duplo clique, aceitar o aviso).'
    ''
    '[HKEY_CLASSES_ROOT\idlprint]'
    '@="URL:ID Logistics Printer Install"'
    '"URL Protocol"=""'
    ''
    '[HKEY_CLASSES_ROOT\idlprint\shell]'
    ''
    '[HKEY_CLASSES_ROOT\idlprint\shell\open]'
    ''
    '[HKEY_CLASSES_ROOT\idlprint\shell\open\command]'
    $comandoReg
)
$regLinhas | Set-Content -Path (Join-Path $PortalDir 'idlprint.reg') -Encoding Unicode

Write-Host "  [OK] idlprint.reg gerado" -ForegroundColor Green
Write-Host ""
Write-Host "  Portal pronto. Abra portal\index.html" -ForegroundColor Cyan
