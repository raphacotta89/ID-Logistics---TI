# Central de Impressoras · TI ID Logistics

Catálogo e instalador de impressoras de rede **sem servidor de impressão**.
O técnico abre uma página, acha a impressora pelo setor e instala com um clique.

---

## Estrutura

```
ID-Logistics---TI/
├── portal/
│   ├── index.html          → a página que o técnico abre
│   ├── printers.json       → FONTE DA VERDADE (edite este arquivo)
│   ├── printers.js         → gerado, permite abrir o portal via file://
│   ├── launchers/*.bat     → gerados, um por impressora
│   ├── idlprint.reg        → gerado, registra o protocolo de clique único
│   └── logo.png            → coloque a logo da ID aqui (opcional)
├── scripts/
│   ├── Scan-Printers.ps1   → varre a rede e monta o catálogo
│   ├── Install-Printer.ps1 → faz a instalação de fato
│   ├── Build-Portal.ps1    → regenera printers.js, .bat e .reg
│   └── Protocol-Handler.ps1→ gerado, recebe o idlprint://
└── drivers/                → NÃO vai pro Git (ver drivers/README.md)
```

---

## Implantação (uma vez)

### 1. Levantar o parque

Rode de qualquer máquina dentro da rede da unidade. Não precisa de admin.

```powershell
cd scripts
.\Scan-Printers.ps1 -Subnet 10.215.60,10.215.61,10.215.62 -Manufacturer Epson,HP,Brother
```

Varre de 1 a 254, testa as portas 9100 / 515 / 631, tenta ler o modelo pela página web
da impressora e grava o `portal\printers.json`. O filtro acima inclui somente Epson, HP e Brother;
equipamentos sem fabricante confirmado ficam de fora.

Rodando de novo depois, use `-Merge` para não perder o que já foi preenchido à mão:

```powershell
.\Scan-Printers.ps1 -Subnet 10.215.60,10.215.61,10.215.62 -Manufacturer Epson,HP,Brother -Merge
```

### 2. Completar o catálogo

| Campo | O que é | Exemplo |
|---|---|---|
| `id` | identificador curto, usado nos links | `expedicao-01` |
| `setor` | agrupa os cards no portal | `Expedição` |
| `local` | referência física | `Doca 3, ao lado da conferência` |
| `fila` | nome que aparece no Windows | `IDL-EXPEDICAO-01` |
| `driverName` | **nome exato** do driver no Windows | `EPSON WF-M5899 Series` |
| `driverPath` | subpasta dentro de `drivers\` | `epson-wfm5899` |

Para descobrir o `driverName`, instale a impressora manualmente uma vez e rode:

```powershell
Get-PrinterDriver | Select-Object Name
```

### 3. Colocar os drivers

Uma subpasta por driver dentro de `drivers\`, com o `.INF` dentro. Ver `drivers/README.md`.

### 4. Gerar o portal

```powershell
.\Build-Portal.ps1
```

### 5. Habilitar o clique único

Em cada máquina da equipe de TI, duplo clique no `portal\idlprint.reg` e aceitar.
A partir daí o botão **Instalar** do portal executa direto, sem download.

> O `.reg` guarda o caminho absoluto do `Protocol-Handler.ps1`. Se mover a pasta,
> rode o `Build-Portal.ps1` de novo e reaplique o `.reg`.

---

## Uso no dia a dia

**Pelo portal:** abre o `index.html`, busca o setor, clica em **Instalar**.

**Pela linha de comando:**

```powershell
.\Install-Printer.ps1 -Id expedicao-01
.\Install-Printer.ps1 -Id expedicao-01 -SetDefault
.\Install-Printer.ps1 -List
.\Install-Printer.ps1 -Id expedicao-01 -Force   # reinstala por cima
```

O script se auto-eleva para administrador, testa se a impressora responde antes de tentar
qualquer coisa, injeta o driver via `pnputil`, cria a porta TCP/IP e a fila.

---

## Sobre segurança

**O que protege de verdade:** o repositório ser privado e a pasta de rede ter permissão
NTFS restrita ao grupo de TI no AD.

**O que NÃO protege:** qualquer senha em JavaScript dentro do `index.html`. Página estática
não tem backend, então a senha fica visível em `Ctrl+U`. Serve contra curioso, não contra
invasor. Por isso não foi colocada nenhuma.

**GitHub Pages em repo privado:** nos planos Free e Pro, ativar Pages num repo privado deixa
**o site público**. Pages privado só existe no Enterprise Cloud. Por isso o portal foi feito
para abrir localmente (clone do repo ou pasta no share), não como Pages.

### Modelo recomendado

```
GitHub (repo privado)  →  fonte da verdade, versionamento
        ↓ git pull
\\SERVIDOR\ti$\impressoras  →  onde os técnicos acessam (permissão de AD)
```

---

## Manutenção

| Situação | O que fazer |
|---|---|
| Impressora nova | Adicionar no `printers.json` + `.\Build-Portal.ps1` |
| Impressora trocou de IP | Editar o `ip` no JSON + `.\Build-Portal.ps1` |
| Impressora removida | Apagar do JSON + `.\Build-Portal.ps1` |
| Auditoria do parque | `.\Scan-Printers.ps1 -Subnet 10.215.60,10.215.61,10.215.62 -Manufacturer Epson,HP,Brother -Merge` |

---

## Pendências de segurança do parque

A varredura lista as impressoras acessíveis. Vale checar em cada uma:

- Senha de administrador padrão (na Epson WF-M5899 a senha inicial é o número de série)
- Interface web exposta sem HTTPS
- Protocolos desnecessários habilitados (FTP, Telnet, SNMP v1 com community `public`)
- Firmware desatualizado
