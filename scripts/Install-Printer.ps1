<#
.SYNOPSIS
    Instalador de impressoras de rede - ID Logistics
.DESCRIPTION
    Le o catalogo printers.json, injeta o driver, cria a porta TCP/IP e a fila.
    Nao depende de servidor de impressao. Auto-eleva para administrador.
.EXAMPLE
    .\Install-Printer.ps1 -Id expedicao-01
.EXAMPLE
    .\Install-Printer.ps1 -List
#>

[CmdletBinding()]
param(
    [string]$Id,
    [string]$CatalogPath = "$PSScriptRoot\..\portal\printers.json",
    [string]$DriverRoot  = "$PSScriptRoot\..\drivers",
    [switch]$SetDefault,
    [switch]$List,
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
# --- resolucao de caminhos (compativel com execucao via -File e via duplo clique) ---
$__raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $CatalogPath -or $CatalogPath -notmatch '^[A-Za-z]:\\|^\\\\') { $CatalogPath = Join-Path $__raiz '..\portal\printers.json' }
if ($PSBoundParameters.ContainsKey('DriverRoot') -eq $false -and (Get-Variable DriverRoot -EA SilentlyContinue)) { if ($DriverRoot -notmatch '^[A-Za-z]:\\|^\\\\') { $DriverRoot = Join-Path $__raiz '..\drivers' } }
if ((Get-Variable PortalDir -EA SilentlyContinue) -and $PortalDir -notmatch '^[A-Za-z]:\\|^\\\\') { $PortalDir = Join-Path $__raiz '..\portal' }
if ((Get-Variable OutFile -EA SilentlyContinue) -and $OutFile -notmatch '^[A-Za-z]:\\|^\\\\') { $OutFile = Join-Path $__raiz '..\portal\printers.json' }
$PSScriptRoot2 = $__raiz


function Write-Step  { param($m) Write-Host "  [>] $m" -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Warn2 { param($m) Write-Host "  [!] $m" -ForegroundColor Yellow }
function Write-Err   { param($m) Write-Host "  [X] $m" -ForegroundColor Red }

function Stop-Script {
    param([int]$Code = 0)
    if (-not $NoPause) {
        Write-Host ""
        Write-Host "  Pressione qualquer tecla para fechar..." -ForegroundColor DarkGray
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
    exit $Code
}

Write-Host ""
Write-Host "  ============================================" -ForegroundColor DarkCyan
Write-Host "   ID LOGISTICS - Instalador de Impressoras" -ForegroundColor White
Write-Host "  ============================================" -ForegroundColor DarkCyan
Write-Host ""

if (-not (Test-Path $CatalogPath)) {
    Write-Err "Catalogo nao encontrado: $CatalogPath"
    Stop-Script 1
}

$catalogo = Get-Content $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($List -or -not $Id) {
    Write-Host "  Impressoras disponiveis:" -ForegroundColor White
    Write-Host ""
    $catalogo | Sort-Object setor | ForEach-Object {
        Write-Host ("   {0,-22} {1,-20} {2,-16} {3}" -f $_.id, $_.setor, $_.ip, $_.modelo)
    }
    Write-Host ""
    Write-Host "  Uso: .\Install-Printer.ps1 -Id <id>" -ForegroundColor DarkGray
    Stop-Script 0
}

$p = $catalogo | Where-Object { $_.id -eq $Id }

if (-not $p) {
    Write-Err "Id '$Id' nao existe no catalogo."
    Write-Host "  Rode com -List para ver os ids validos." -ForegroundColor DarkGray
    Stop-Script 1
}
if ($p -is [array]) {
    Write-Err "Id '$Id' esta duplicado no catalogo. Corrija o printers.json."
    Stop-Script 1
}

$camposPendentes = @()
foreach ($campo in 'ip', 'fila', 'driverName') {
    if (-not $p.$campo) { $camposPendentes += $campo }
}
if ($camposPendentes.Count) {
    Write-Err "Cadastro incompleto para '$Id': $($camposPendentes -join ', ')."
    Write-Host "  Complete esses campos no portal\printers.json antes de instalar." -ForegroundColor DarkGray
    Stop-Script 4
}

Write-Host "   Impressora : $($p.modelo)"
Write-Host "   Setor      : $($p.setor)"
Write-Host "   Local      : $($p.local)"
Write-Host "   Endereco   : $($p.ip)"
Write-Host "   Fila       : $($p.fila)"
Write-Host ""

$souAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $souAdmin) {
    Write-Warn2 "Elevando para administrador..."
    $argumentos = @(
        '-NoProfile'
        '-ExecutionPolicy','Bypass'
        '-File', "`"$PSCommandPath`""
        '-Id', "`"$Id`""
        '-CatalogPath', "`"$CatalogPath`""
        '-DriverRoot', "`"$DriverRoot`""
    )
    if ($SetDefault) { $argumentos += '-SetDefault' }
    if ($Force)      { $argumentos += '-Force' }

    Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentos -Verb RunAs
    exit 0
}

# --- 1. Conectividade ---
Write-Step "Testando conectividade com $($p.ip)..."
$socket = [System.Net.Sockets.TcpClient]::new()
$vivo = $false
try {
    $h = $socket.BeginConnect($p.ip, 9100, $null, $null)
    if ($h.AsyncWaitHandle.WaitOne(2500, $false) -and $socket.Connected) {
        $socket.EndConnect($h); $vivo = $true
    }
} catch { } finally { $socket.Close() }

if (-not $vivo) {
    Write-Err "Sem resposta na porta 9100. A impressora esta ligada e na rede?"
    if (-not $Force) {
        Write-Host "  Use -Force para instalar mesmo assim." -ForegroundColor DarkGray
        Stop-Script 2
    }
    Write-Warn2 "Continuando por causa do -Force."
} else {
    Write-Ok "Impressora respondendo."
}

# --- 2. Fila ja existe? ---
$existente = Get-Printer -Name $p.fila -ErrorAction SilentlyContinue
if ($existente) {
    if (-not $Force) {
        Write-Warn2 "A fila '$($p.fila)' ja esta instalada nesta maquina."
        if ($SetDefault) {
            (Get-CimInstance -Class Win32_Printer -Filter "Name='$($p.fila)'").SetDefaultPrinter() | Out-Null
            Write-Ok "Definida como padrao."
        }
        Stop-Script 0
    }
    Write-Warn2 "Removendo instalacao anterior (-Force)..."
    Remove-Printer -Name $p.fila -ErrorAction SilentlyContinue
}

# --- 3. Driver ---
Write-Step "Verificando driver '$($p.driverName)'..."

$driverInstalado = Get-PrinterDriver -Name $p.driverName -ErrorAction SilentlyContinue
$usarIpp = $false

if (-not $driverInstalado) {
    $pasta = if ($p.driverPath) { Join-Path $DriverRoot $p.driverPath } else { $null }

    if ($pasta -and (Test-Path $pasta)) {
        Write-Step "Injetando driver no Windows (pnputil)..."
        $infs = Get-ChildItem -Path $pasta -Filter *.inf -Recurse -ErrorAction SilentlyContinue

        if (-not $infs) {
            Write-Err "Nenhum arquivo .INF encontrado em $pasta"
            Stop-Script 3
        }

        foreach ($inf in $infs) {
            & pnputil.exe /add-driver "$($inf.FullName)" /install | Out-Null
        }

        Start-Sleep -Seconds 2
        Add-PrinterDriver -Name $p.driverName -ErrorAction Stop
        Write-Ok "Driver instalado."
    } else {
        $usarIpp = $true
        Write-Warn2 "Driver especifico nao encontrado. Usando o driver padrao do Windows (IPP)."
    }
} else {
    Write-Ok "Driver ja presente no sistema."
}

# --- 4 e 5. Porta e fila ---
if ($usarIpp) {
    Write-Step "Criando a fila '$($p.fila)' pelo IPP..."
    Add-Printer -Name $p.fila -IppURL "http://$($p.ip):631/ipp/print" -ErrorAction Stop
    Write-Ok "Fila criada com o driver padrao do Windows."
} else {
    $nomePorta = "IP_$($p.ip)"
    Write-Step "Configurando porta $nomePorta..."

    if (-not (Get-PrinterPort -Name $nomePorta -ErrorAction SilentlyContinue)) {
        Add-PrinterPort -Name $nomePorta -PrinterHostAddress $p.ip -PortNumber 9100 -ErrorAction Stop
        Write-Ok "Porta criada."
    } else {
        Write-Ok "Porta ja existia."
    }

    Write-Step "Criando a fila '$($p.fila)'..."
    Add-Printer -Name $p.fila -DriverName $p.driverName -PortName $nomePorta -ErrorAction Stop
    Write-Ok "Fila criada."
}

# --- 6. Ajustes ---
try {
    if ($p.duplex)        { Set-PrintConfiguration -PrinterName $p.fila -DuplexingMode TwoSidedLongEdge -ErrorAction SilentlyContinue }
    if (-not $p.colorido) { Set-PrintConfiguration -PrinterName $p.fila -Color $false -ErrorAction SilentlyContinue }
    Set-Printer -Name $p.fila -Comment "$($p.setor) - $($p.local)" -Location $p.local -ErrorAction SilentlyContinue
} catch {
    Write-Warn2 "Nao consegui aplicar todas as preferencias (nao impede o uso)."
}

if ($SetDefault) {
    (Get-CimInstance -Class Win32_Printer -Filter "Name='$($p.fila)'").SetDefaultPrinter() | Out-Null
    Write-Ok "Definida como impressora padrao."
}

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "   INSTALADO COM SUCESSO" -ForegroundColor Green
Write-Host "   $($p.fila) -> $($p.ip)" -ForegroundColor White
Write-Host "  ============================================" -ForegroundColor Green
Stop-Script 0
