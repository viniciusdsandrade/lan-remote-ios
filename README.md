# Lan Remote iOS

Aplicativo nativo para **iPhone** e **iPad** desenvolvido em **SwiftUI** para controle remoto de televisores **LG NetCast** (especialmente série LN5700 como 47LN5700, modelos 2012-2013) operando **100% na rede local (LAN)**.

---

## 🚀 Destaques e Funcionalidades

- **Liga a TV sem levantar do sofá**: em standby a LG NetCast desliga a rede, então o app acorda a **TV Box** (Android TV) ligada no HDMI e ela liga a TV pelo **HDMI-CEC (SIMPLINK)**. Detalhes em [Ligar a TV pelo app](#-ligar-a-tv-pelo-app).
- **Botões que se explicam**: ícone + nome em português em cada botão, agrupados por função (Navegação, Volume e canal, Recursos da TV, Reprodução, Botões coloridos). **Segurar** um botão mostra no rodapé o que ele faz, sem enviar nada à TV; o **?** abre o **Guia dos botões** completo. Os mesmos textos alimentam o VoiceOver.
- **Estado da TV à vista**: `Ligada`, `Desligada` ou `Ligando…` no topo, com volume e entrada atual. Com a TV desligada o controle fica esmaecido e um cartão mostra o botão **Ligar**.
- **Zero Dependências Externas**: Construído puramente sobre o ecossistema Apple (`SwiftUI`, `Network`, `Security`, `CryptoKit`, `AVFoundation`, `MediaPlayer`).
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

# 4. Roda os testes num simulador (assinado ad-hoc: o teste do Keychain precisa de entitlements)
xcodebuild test \
  -project LanRemote.xcodeproj \
  -scheme LanRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="-"
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

## 🔌 Ligar a TV pelo app

A TV não liga pela rede (em standby o controlador de rede dela desliga; Wake-on-LAN não tem efeito).
O caminho é a **TV Box Xiaomi** (Android TV / Google TV) ligada no HDMI, que acorda a TV pelo CEC:

1. O app manda **Wake-on-LAN** para o endereço da TV Box. Ela também dorme fundo, mas acorda a rede
   por alguns segundos (a porta do controle responde em ~1 s). Os pacotes vão em **unicast** para o
   último IP conhecido: broadcast no iOS exige um entitlement especial da Apple, e unicast funciona.
2. Nessa janela o app aperta **POWER** pelo protocolo do controle remoto do Android TV (o mesmo do app
   Google TV: portas 6466/6467, TLS com certificado próprio, mensagens protobuf).
3. Ao acordar, a TV Box manda **One Touch Play** pelo HDMI-CEC: a TV liga, já na entrada dela. A imagem
   volta em segundos; a rede da TV, em ~40–55 s, e aí o controle volta a responder.

Uma vez só, em **Ajustes › Ligar a TV pelo app**: com a TV ligada na entrada da TV Box, toque em
**Parear** e digite o código de 6 caracteres que aparece na tela. O app gera um certificado RSA e o
guarda no Keychain (`AndroidTVIdentity.swift`); a TV Box passa a reconhecê-lo. Requisitos:

- **SIMPLINK ligado na TV** (botão SIMPLINK do app → "SIMPLINK Ligado"). Sem ele a TV ignora o CEC.
- **HDMI-CEC ativo na TV Box** (Configurações › Sistema › Entradas).
- **MAC do Wi-Fi da TV Box**: o iPhone não lê a tabela ARP, então o app tenta os endereços vizinhos ao
  MAC Bluetooth anunciado no Bonjour (`bt=`; os dois costumam ser consecutivos). Se não acordar, digite
  o MAC em Ajustes (na TV Box: Configurações › Sistema › Sobre › Status).
- **IP fixo para a TV Box** (reserva DHCP no roteador): dormindo, ela só acorda pelo último endereço
  conhecido. Enquanto a TV está ligada o app atualiza esse endereço pelo Bonjour a cada 5 min.

Não adianta usar `KEYCODE_TV_POWER` (177) nem `KEYCODE_WAKEUP` (224): a TV Box Xiaomi ignora os dois.
A sequência acima foi validada de ponta a ponta no app para Mac do projeto irmão (`lan-remote-mac`):
TV em standby e TV Box em repouso profundo → TV ligada e respondendo em ~42 s. No iPhone, o que falta
validar em aparelho real é o pareamento e o Wake-on-LAN saindo do iOS.

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
