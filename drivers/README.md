# Drivers

Esta pasta **não vai para o Git** (limite de 100 MB por arquivo e questão de redistribuição).

Cada impressora tem uma subpasta cujo nome bate com o campo `driverPath` do `printers.json`.
Dentro dela devem estar os arquivos extraídos do driver, incluindo o `.INF`.

```
drivers/
├── epson-wfm5899/
│   ├── E_WF5899.INF
│   └── ...
└── hp-m404/
    ├── hpcu255u.inf
    └── ...
```

## Como descobrir o `driverName` exato

Instale a impressora manualmente uma vez numa máquina e rode:

```powershell
Get-PrinterDriver | Select-Object Name, InfPath
```

O valor da coluna `Name` é o que vai no campo `driverName` do catálogo.

## Onde hospedar

| Opção | Limite | Observação |
|---|---|---|
| GitHub Releases | 2 GB por arquivo | Bom para repo privado |
| Share de rede | ilimitado | Mais rápido na unidade, permissão via AD |
