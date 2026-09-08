$ErrorActionPreference = 'Continue'
Set-Location 'C:\Users\rcotta\ID-Logistics---TI'

Remove-Item '.\scripts\patch.ps1' -Force -ErrorAction SilentlyContinue
Remove-Item '.\demo' -Recurse -Force -ErrorAction SilentlyContinue

git init 2>&1
git branch -M main 2>&1
git remote remove origin 2>&1 | Out-Null
git remote add origin https://github.com/raphacotta89/ID-Logistics---TI.git 2>&1
git add -A 2>&1
git -c user.name="Raphael Cotta" -c user.email="raphaeladriano.cotta@gmail.com" commit -m "Central de impressoras: portal, varredura de rede e instalador sem print server" 2>&1
Write-Host "=== STATUS ==="
git status --short 2>&1
Write-Host "=== ARQUIVOS VERSIONADOS ==="
git ls-files 2>&1
Write-Host "=== PUSH ==="
git push -u origin main 2>&1
