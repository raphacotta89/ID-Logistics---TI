<#
.SYNOPSIS
    Varredura de impressoras de rede - ID Logistics
.DESCRIPTION
    Varre uma faixa de IP procurando dispositivos de impressao (portas 9100/515/631),
    tenta identificar modelo via pagina web embarcada e gera/atualiza o printers.json.
.EXAMPLE
    .\Scan-Printers.ps1 -Subnet 10.20.30
.EXAMPLE
    .\Scan-Printers.ps1 -Subnet 192.168.1 -Merge
.NOTES
    Nao precisa de admin. Rode de qualquer maquina dentro da rede da unidade.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}$')]
    [string]$Subnet,

    [ValidateRange(1, 254)]
    [int]$Start = 1,

    [ValidateRange(1, 254)]
    [int]$End = 254,

    [string]$OutFile = "$PSScriptRoot\..\portal\printers.json",

    [int]$TimeoutMs = 500,

    [switch]$Merge
)

$ErrorActionPreference = 'Stop'
# --- resolucao de caminhos (compativel com execucao via -File e via duplo clique) ---
$__raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $CatalogPath -or $CatalogPath -notmatch '^[A-Za-z]:\\|^\\\\') { $CatalogPath = Join-Path $__raiz '..\portal\printers.json' }
if ($PSBoundParameters.ContainsKey('DriverRoot') -eq $false -and (Get-Variable DriverRoot -EA SilentlyContinue)) { if ($DriverRoot -notmatch '^[A-Za-z]:\\|^\\\\') { $DriverRoot = Join-Path $__raiz '..\drivers' } }
if ((Get-Variable PortalDir -EA SilentlyContinue) -and $PortalDir -notmatch '^[A-Za-z]:\\|^\\\\') { $PortalDir = Join-Path $__raiz '..\portal' }
if ((Get-Variable OutFile -EA SilentlyContinue) -and $OutFile -notmatch '^[A-Za-z]:\\|^\\\\') { $OutFile = Join-Path $__raiz '..\portal\printers.json' }
$PSScriptRoot2 = $__raiz

$PORTS = @(9100, 515, 631)

Write-Host ""
Write-Host "  Varredura de impressoras - ID Logistics" -ForegroundColor Cyan
Write-Host "  Faixa: $Subnet.$Start - $Subnet.$End" -ForegroundColor DarkGray
Write-Host ""

function Get-PrinterIdentity {
    param([string]$IPAddress)

    $result = [ordered]@{ modelo = ''; fabricante = ''; hostname = '' }

    try {
        $result.hostname = ([System.Net.Dns]::GetHostEntry($IPAddress)).HostName
    } catch { }

    foreach ($scheme in @('http', 'https')) {
        try {
            $params = @{
                Uri             = "${scheme}://$IPAddress/"
                TimeoutSec      = 4
                UseBasicParsing = $true
                ErrorAction     = 'Stop'
            }
            if ($PSVersionTable.PSVersion.Major -ge 6) { $params.SkipCertificateCheck = $true }

            $resp = Invoke-WebRequest @params
            $html = $resp.Content

            if ($html -match '<title[^>]*>\s*(.*?)\s*</title>') {
                $title = ($Matches[1] -replace '\s+', ' ').Trim()
                if ($title -and $title -notmatch '^(index|home|login)$') {
                    $result.modelo = $title
                }
            }

            foreach ($marca in 'Epson','HP','Hewlett','Brother','Canon','Lexmark','Kyocera','Ricoh','Samsung','Xerox','Zebra','Sharp','Oki','Bematech','Elgin','Argox') {
                if ($html -match $marca) { $result.fabricante = $marca; break }
            }

            if ($result.modelo) { break }
        } catch { }
    }

    return $result
}

# --- Varredura paralela (async TCP, sem dependencia de modulo) ---
Write-Host "  Varrendo $($End - $Start + 1) enderecos..." -ForegroundColor DarkGray

$tentativas = [System.Collections.ArrayList]::new()

foreach ($octeto in $Start..$End) {
    $ip = "$Subnet.$octeto"
    foreach ($porta in $PORTS) {
        $client = [System.Net.Sockets.TcpClient]::new()
        try {
            $handle = $client.BeginConnect($ip, $porta, $null, $null)
            [void]$tentativas.Add([pscustomobject]@{
                IP     = $ip
                Porta  = $porta
                Client = $client
                Handle = $handle
            })
        } catch {
            $client.Close()
        }
    }
}

Start-Sleep -Milliseconds $TimeoutMs

$abertasPorIP = @{}
foreach ($t in $tentativas) {
    try {
        if ($t.Handle.IsCompleted -and $t.Client.Connected) {
            $t.Client.EndConnect($t.Handle)
            if (-not $abertasPorIP.ContainsKey($t.IP)) { $abertasPorIP[$t.IP] = @() }
            $abertasPorIP[$t.IP] += $t.Porta
        }
    } catch {
    } finally {
        $t.Client.Close()
    }
}

$hits = foreach ($ip in $abertasPorIP.Keys) {
    [pscustomobject]@{ IP = $ip; Portas = ($abertasPorIP[$ip] | Sort-Object) }
}

Write-Host ""
Write-Host "  $(@($hits).Count) dispositivo(s) respondendo em portas de impressao." -ForegroundColor Green
Write-Host "  Identificando modelos..." -ForegroundColor DarkGray
Write-Host ""

$found = [System.Collections.ArrayList]::new()

foreach ($hit in $hits | Sort-Object { [int]($_.IP -split '\.')[-1] }) {
    $id = Get-PrinterIdentity -IPAddress $hit.IP
    $slug = ($hit.IP -replace '\.', '-')

    $registro = [ordered]@{
        id         = "impressora-$slug"
        setor      = ''
        local      = ''
        modelo     = $id.modelo
        fabricante = $id.fabricante
        ip         = $hit.IP
        hostname   = $id.hostname
        fila       = ''
        driverName = ''
        driverPath = ''
        portas     = $hit.Portas
        colorido   = $false
        duplex     = $true
        observacao = ''
    }

    [void]$found.Add($registro)

    $label = if ($id.modelo) { $id.modelo } else { '(modelo nao identificado)' }
    Write-Host ("  {0,-16} {1}" -f $hit.IP, $label) -ForegroundColor White
}

$saida = $found

if ($Merge -and (Test-Path $OutFile)) {
    $antigo = Get-Content $OutFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $mapaAntigo = @{}
    foreach ($p in $antigo) { $mapaAntigo[$p.ip] = $p }

    $saida = foreach ($novo in $found) {
        if ($mapaAntigo.ContainsKey($novo.ip)) { $mapaAntigo[$novo.ip] } else { $novo }
    }
    Write-Host ""
    Write-Host "  Merge aplicado: registros ja catalogados foram preservados." -ForegroundColor Yellow
}

$dir = Split-Path $OutFile -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$saida | ConvertTo-Json -Depth 5 | Set-Content -Path $OutFile -Encoding UTF8

Write-Host ""
Write-Host "  Catalogo gravado em: $OutFile" -ForegroundColor Cyan
Write-Host "  Proximo passo: preencha setor, local, fila e driverName no JSON." -ForegroundColor Yellow
Write-Host ""
