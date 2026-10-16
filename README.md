# Lan Remote iOS

Aplicativo nativo para **iPhone** e **iPad** desenvolvido em **SwiftUI** para controle remoto de televisores **LG NetCast** (especialmente série LN5700 como 47LN5700, modelos 2012-2013) operando **100% na rede local (LAN)**.

---

## 🚀 Destaques e Funcionalidades

- **Zero Dependências Externas**: Construído puramente sobre o ecossistema Apple (`SwiftUI`, `Network`, `AVFoundation`, `MediaPlayer`).
- **Arquitetura Serverless Local**: O iPhone comunica-se diretamente com a TV pela porta `8080` (HTTP) através da rede Wi-Fi local. Zero nuvem, zero telemetria e latência inferior a 100ms.
- **Feedback Háptico Realista**: Cada botão (D-Pad, volume, ok, numérico, power) aciona vibrações táteis finas (`UIImpactFeedbackGenerator`).
- **Controle com Teclas Físicas de Volume**: Interceptação das teclas físicas laterais de volume do iPhone (`+` e `-`) via `VolumeButtonHandler` para ajustar o volume da TV sem olhar para a tela.
- **D-Pad Circular Ergonômico**: Direcionais táteis com botão central OK e gangorras verticais de volume e canal na zona de alcance do polegar.
- **Descoberta Automática de Rede**: Varredura rápida de rede na porta 8080 para encontrar TVs LG na sub-rede local com um clique.
- **Pareamento Intuitivo**: Solicitação de código PIN de 6 dígitos que aparece na tela da TV e é salvo permanentemente no dispositivo.
- **Conformidade Apple 2026/2027**: Inclui manifesto oficial de privacidade `PrivacyInfo.xcprivacy` e permissões de rede local no `Info.plist`.

---

## 📱 Requisitos do Sistema

- **Dispositivo**: iPhone ou iPad rodando **iOS 17.0+**
- **Desenvolvimento**: macOS com **Xcode 16.0+** (ou 27.0+) e **XcodeGen 2.46+**
- **Rede**: iPhone e TV conectados na mesma rede Wi-Fi local

---

## 🛠️ Como Compilar e Rodar

### 1. Pré-requisitos

Instale o `xcodegen` (caso ainda não possua):
```bash
brew install xcodegen
```

### 2. Gerar o Projeto e Compilar

Basta rodar o script automatizado:
```bash
./build.sh
```

Ou manualmente via terminal:
```bash
# 1. Gera o arquivo LanRemote.xcodeproj a partir de project.yml
xcodegen generate

# 2. Compila o aplicativo para o simulador
xcodebuild \
  -project LanRemote.xcodeproj \
  -scheme LanRemote \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build

# 3. Compila a suíte de testes
xcodebuild \
  -project LanRemote.xcodeproj \
  -scheme LanRemote \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

---

## 📡 Protocolo de Rede (ROAP vs UDAP)

As Smart TVs LG de 2012–2013 utilizam o protocolo **ROAP / UDAP** sobre HTTP na porta `8080`:

| Operação | Método | Endpoint | Content-Type | Corpo XML |
|---|---|---|---|---|
| **Pedir Código na TV** | `POST` | `/roap/api/auth` | `application/atom+xml` | `<auth><type>AuthKeyReq</type></auth>` |
| **Confirmar Pareamento** | `POST` | `/roap/api/auth` | `application/atom+xml` | `<auth><type>AuthReq</type><value>123456</value></auth>` |
| **Enviar Tecla** | `POST` | `/roap/api/command` | `application/atom+xml` | `<command><session>...</session><type>HandleKeyInput</type><value>20</value></command>` |
| **Status de Volume** | `GET` | `/roap/api/data?target=volume_info&session=...` | — | Resposta XML contendo `<level>` e `<mute>` |
| **Canal / Entrada** | `GET` | `/roap/api/data?target=cur_channel&session=...` | — | Resposta XML contendo `<inputSourceName>` |

> [!CRITICAL]
> **Atenção ao cabeçalho User-Agent**: No firmware `05.02.11` da TV 47LN5700, requisições ROAP **não** podem conter `"UDAP/2.0"` no `User-Agent`. O app utiliza `User-Agent: lg_roap_control/1.0.0 (iOS)`.

---

## 🛡️ Segurança e Gates de CI/CD

O repositório possui uma esteira segregada no GitHub Actions (`.github/workflows/ios-ci.yml`):
- **Linux (`ubuntu-latest`)**: Validação de segurança estática (App Transport Security, manifesto de privacidade e ausência de certificados commitados).
- **macOS (`macos-15`)**: Geração determinística do projeto via XcodeGen e compilação do app e testes unitários.

Para rodar os gates de segurança localmente:
```bash
./scripts/ci/gate_ats.sh
./scripts/ci/gate_privacy_manifest.sh
./scripts/ci/gate_sensitive_files.sh
```

---

## 📄 Licença

Uso pessoal e livre para automação residencial e controle local.
