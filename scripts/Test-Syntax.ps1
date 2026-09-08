$erros = 0
Get-ChildItem -Path $PSScriptRoot -Filter *.ps1 | ForEach-Object {
    $t = $null; $e = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$t, [ref]$e) | Out-Null
    if ($e -and $e.Count) {
        $erros++
        Write-Host "ERRO em $($_.Name):" -ForegroundColor Red
        $e | ForEach-Object { Write-Host ("  linha {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) }
    } else {
        Write-Host "OK  $($_.Name)" -ForegroundColor Green
    }
}
Write-Host "Arquivos com erro: $erros"
