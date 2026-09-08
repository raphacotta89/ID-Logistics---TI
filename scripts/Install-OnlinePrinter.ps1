<#
.SYNOPSIS
    Prepara e inicia a instalacao de uma impressora a partir do portal online.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Id
)

$ErrorActionPreference = 'Stop'
$baseUrl = 'https://raw.githubusercontent.com/raphacotta89/ID-Logistics---TI/main'
$pasta = Join-Path $env:TEMP 'IDL-Print'
$instalador = Join-Path $pasta 'Install-Printer.ps1'
$catalogo = Join-Path $pasta 'printers.json'

try {
    New-Item -ItemType Directory -Path $pasta -Force | Out-Null
    Invoke-WebRequest -UseBasicParsing "$baseUrl/scripts/Install-Printer.ps1" -OutFile $instalador
    Invoke-WebRequest -UseBasicParsing "$baseUrl/portal/printers.json" -OutFile $catalogo
    & $instalador -Id $Id -CatalogPath $catalogo -DriverRoot (Join-Path $pasta 'drivers')
} catch {
    Write-Host ""
    Write-Host "  Nao foi possivel preparar a instalacao online." -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Pressione qualquer tecla para fechar..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}
