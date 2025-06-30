# QualitySetup2025 🚀

Instalador automatizado para PostgreSQL 12 e QualityPDV com configuração integrada.

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-12-blue)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blueviolet)
![Inno Setup](https://img.shields.io/badge/Inno_Setup-6.2-yellowgreen)

## 📦 Conteúdo do Projeto

```plaintext
QualitySetup2025/
├── installPostgreSQL.ps1     - Script de instalação postgres 12
├── clean_postgres.ps1        - Limpeza de instalações anteriores
├── UpdateChecker.ps1         - Verificador de atualizações
├── QualitySetup2025.iss      - Script de instalação Inno Setup
└── README_INSTALACAO.txt     - Instruções complementares
```

## 🔄 Fluxo de Instalação

01. Verifica atualizações

02. Remove instalações anteriores (opcional)

03. Instala PostgreSQL 12

04. Configura firewall

05. Cria banco de dados

06. Restaura backup inicial

## 🛠️ Pré-requisitos

- Windows 10/11

- PowerShell 5.1+

- .NET Framework 4.8+

## 🌟 Recursos

- Instalação silenciosa do PostgreSQL 12

- Configuração automática de firewall

- Restauração de banco de dados padrão

- Verificação de integridade por SHA256

- Atualização automática

## 📄 Licença
Este projeto está licenciado sob a Licença MIT.