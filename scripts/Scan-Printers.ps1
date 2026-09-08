<#
.SYNOPSIS
    Varredura de impressoras de rede - ID Logistics
.DESCRIPTION
    Varre uma faixa de IP procurando dispositivos de impressao (portas 9100/515/631),
    tenta identificar modelo via pagina web embarcada e gera/atualiza o printers.json.
.EXAMPLE
    .\Scan-Printers.ps1 -Subnet 10.215.60,10.215.61,10.215.62 -Manufacturer Epson,HP,Brother
.EXAMPLE
    .\Scan-Printers.ps1 -Subnet 192.168.1 -Merge
.NOTES
    Nao precisa de admin. Rode de qualquer maquina dentro da rede da unidade.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({
        if ($_ -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}$') { throw "Faixa invalida: $_" }
        foreach ($parte in ($_ -split '\.')) {
            if ([int]$parte -gt 255) { throw "Faixa invalida: $_" }
        }
        $true
    })]
    [string[]]$Subnet,

    [ValidateRange(1, 254)]
    [int]$Start = 1,

    [ValidateRange(1, 254)]
    [int]$End = 254,

    [string]$OutFile,

    [int]$TimeoutMs = 500,

    [ValidateSet('Epson', 'HP', 'Brother', 'Canon', 'Lexmark', 'Kyocera', 'Ricoh', 'Samsung', 'Xerox', 'Zebra', 'Sharp', 'Oki', 'Bematech', 'Elgin', 'Argox')]
    [string[]]$Manufacturer,

    [switch]$Merge
)

$ErrorActionPreference = 'Stop'
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $OutFile) { $OutFile = Join-Path $raiz '..\portal\printers.json' }

$PORTS = @(9100, 515, 631)

Write-Host ""
Write-Host "  Varredura de impressoras - ID Logistics" -ForegroundColor Cyan
Write-Host "  Faixas: $(($Subnet | ForEach-Object { "$($_).$Start-$End" }) -join ', ')" -ForegroundColor DarkGray
Write-Host ""

function Invoke-PrinterPage {
    param([string]$Uri)

    $params = @{
        Uri = $Uri
        TimeoutSec = 4
        UseBasicParsing = $true
        ErrorAction = 'Stop'
    }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $params.SkipCertificateCheck = $true
        return Invoke-WebRequest @params
    }

    $callbackAnterior = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    try {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        return Invoke-WebRequest @params
    } finally {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $callbackAnterior
    }
}

function Get-PrinterIdentity {
    param([string]$IPAddress)

    $result = [ordered]@{ modelo = ''; fabricante = ''; hostname = ''; mac = '' }

    try {
        $result.hostname = ([System.Net.Dns]::GetHostEntry($IPAddress)).HostName
    } catch { }

    try {
        $vizinho = Get-NetNeighbor -AddressFamily IPv4 -IPAddress $IPAddress -ErrorAction Stop |
            Where-Object { $_.LinkLayerAddress -and $_.LinkLayerAddress -ne '00-00-00-00-00-00' } |
            Select-Object -First 1
        if ($vizinho) { $result.mac = $vizinho.LinkLayerAddress.ToUpperInvariant() }
    } catch { }

    foreach ($scheme in @('http', 'https')) {
        try {
            $resp = Invoke-PrinterPage -Uri "${scheme}://$IPAddress/"
            $html = $resp.Content

            $server = [string]$resp.Headers['Server']
            if ($server -match '(?i)HP\s+(HP\s+.+?),\s*sn=') {
                $result.fabricante = 'HP'
                $result.modelo = $Matches[1].Trim()
            }

            if ($html -match '<title[^>]*>\s*(.*?)\s*</title>') {
                $title = ($Matches[1] -replace '\s+', ' ').Trim()
                if ($title -and $title -notmatch '^(index|home|login)$') {
                    $result.modelo = $title
                }
            }

            $marcas = [ordered]@{
                Epson = '(?i)\bEpson\b'
                HP = '(?i)\bHP\b|Hewlett[ -]Packard'
                Brother = '(?i)\bBrother\b'
                Canon = '(?i)\bCanon\b'
                Lexmark = '(?i)\bLexmark\b'
                Kyocera = '(?i)\bKyocera\b'
                Ricoh = '(?i)\bRicoh\b'
                Samsung = '(?i)\bSamsung\b'
                Xerox = '(?i)\bXerox\b'
                Zebra = '(?i)\bZebra\b'
                Sharp = '(?i)\bSharp\b'
                Oki = '(?i)\bOki\b'
                Bematech = '(?i)\bBematech\b'
                Elgin = '(?i)\bElgin\b'
                Argox = '(?i)\bArgox\b'
            }
            foreach ($marca in $marcas.Keys) {
                if ($html -match $marcas[$marca]) { $result.fabricante = $marca; break }
            }

            if (-not $result.modelo -and $result.fabricante -eq 'Epson') {
                try {
                    $top = Invoke-PrinterPage -Uri "${scheme}://$IPAddress/PRESENTATION/ADVANCED/COMMON/TOP"
                    if ($top.Content -match '<title[^>]*>\s*(.*?)\s*</title>') {
                        $result.modelo = ($Matches[1] -replace '\s+', ' ').Trim()
                    }
                } catch { }
            }

            if ($result.modelo) { break }
        } catch { }
    }

    # Algumas interfaces web nao informam a marca. Nesse caso, usa o fabricante
    # registrado para o prefixo MAC dos modelos encontrados nesta unidade.
    if (-not $result.fabricante -and $result.mac) {
        $oui = ($result.mac -split '-')[0..2] -join '-'
        $fabricantesPorOui = @{
            '94-DD-F8' = 'Brother'
            'A4-D7-3C' = 'Epson'
            '30-13-8B' = 'HP'
        }
        if ($fabricantesPorOui.ContainsKey($oui)) {
            $result.fabricante = $fabricantesPorOui[$oui]
        }
    }

    # Windows PowerShell 5 pode recusar o certificado autoassinado do equipamento.
    # O curl, presente no Windows atual, serve como segunda tentativa somente de leitura.
    if (-not $result.modelo -and $result.fabricante) {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
            try {
                $uriDetalhe = if ($result.fabricante -eq 'Epson') {
                    "https://$IPAddress/PRESENTATION/ADVANCED/COMMON/TOP"
                } else {
                    "https://$IPAddress/"
                }
                $conteudo = (& $curl.Source -k -L --max-time 5 -s -D - $uriDetalhe 2>$null) -join "`n"
                if ($conteudo -match '(?im)^Server:\s*HP\s+(HP\s+.+?),\s*sn=') {
                    $result.modelo = $Matches[1].Trim()
                } elseif ($conteudo -match '(?is)<title[^>]*>\s*(.*?)\s*</title>') {
                    $titulo = ($Matches[1] -replace '\s+', ' ').Trim()
                    if ($titulo -and $titulo -notmatch '^(index|home|login)$') {
                        $result.modelo = $titulo
                    }
                }
            } catch { }
        }
    }

    if (-not $result.modelo -and $result.fabricante) {
        $result.modelo = "$($result.fabricante) - modelo a confirmar"
    }

    return $result
}

$abertasPorIP = @{}
# --- Varredura paralela por faixa (evita abrir milhares de sockets de uma vez) ---
foreach ($faixa in $Subnet) {
    Write-Host "  Varrendo $faixa.$Start-$End..." -ForegroundColor DarkGray
    $tentativas = [System.Collections.ArrayList]::new()

    foreach ($octeto in $Start..$End) {
        $ip = "$faixa.$octeto"
        foreach ($porta in $PORTS) {
            $client = [System.Net.Sockets.TcpClient]::new()
            try {
                $handle = $client.BeginConnect($ip, $porta, $null, $null)
                [void]$tentativas.Add([pscustomobject]@{
                    IP = $ip; Porta = $porta; Client = $client; Handle = $handle
                })
            } catch {
                $client.Close()
            }
        }
    }

    Start-Sleep -Milliseconds $TimeoutMs

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
}

$hits = foreach ($ip in $abertasPorIP.Keys) {
    [pscustomobject]@{ IP = $ip; Portas = ($abertasPorIP[$ip] | Sort-Object) }
}

Write-Host ""
Write-Host "  $(@($hits).Count) dispositivo(s) respondendo em portas de impressao." -ForegroundColor Green
Write-Host "  Identificando modelos..." -ForegroundColor DarkGray
Write-Host ""

$found = [System.Collections.ArrayList]::new()

foreach ($hit in $hits | Sort-Object { ($_.IP -split '\.' | ForEach-Object { '{0:D3}' -f [int]$_ }) -join '.' }) {
    $id = Get-PrinterIdentity -IPAddress $hit.IP
    if ($Manufacturer -and $id.fabricante -notin $Manufacturer) {
        $motivo = if ($id.fabricante) { "fabricante $($id.fabricante)" } else { 'fabricante nao identificado' }
        Write-Host ("  {0,-16} ignorada ({1})" -f $hit.IP, $motivo) -ForegroundColor DarkGray
        continue
    }
    $slug = ($hit.IP -replace '\.', '-')

    $registro = [ordered]@{
        id         = "impressora-$slug"
        setor      = ''
        local      = ''
        modelo     = $id.modelo
        fabricante = $id.fabricante
        ip         = $hit.IP
        hostname   = $id.hostname
        mac        = $id.mac
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

if ($Merge -and (Test-Path -LiteralPath $OutFile)) {
    $catalogoLido = Get-Content -LiteralPath $OutFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $antigo = @(foreach ($item in $catalogoLido) { $item })
    $mapaAntigo = @{}
    foreach ($p in $antigo) { $mapaAntigo[$p.ip] = $p }

    $mapaNovo = @{}
    foreach ($novo in $found) { $mapaNovo[$novo.ip] = $novo }

    $saida = @(
        foreach ($p in $antigo) {
            if ($mapaNovo.ContainsKey($p.ip)) {
                $p
                $mapaNovo.Remove($p.ip)
            } else {
                $p
            }
        }
        foreach ($novo in $mapaNovo.Values) { $novo }
    )
    if (@($antigo).Count -gt 0) {
        Write-Host "  Merge aplicado: registros existentes foram preservados e novos IPs adicionados." -ForegroundColor Yellow
    }
}

$dir = Split-Path $OutFile -Parent
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

$registrosOrdenados = @($saida | ForEach-Object { $_ } | Sort-Object { [version]$_.ip })
ConvertTo-Json -InputObject $registrosOrdenados -Depth 5 |
    Set-Content -LiteralPath $OutFile -Encoding UTF8

Write-Host ""
Write-Host "  Catalogo gravado em: $OutFile" -ForegroundColor Cyan
if ($Manufacturer) {
    Write-Host "  Filtro aplicado: $($Manufacturer -join ', ') - $($registrosOrdenados.Count) impressora(s) no catalogo." -ForegroundColor Green
}
Write-Host "  Proximo passo: preencha setor, local, fila e driverName no JSON." -ForegroundColor Yellow
Write-Host ""
