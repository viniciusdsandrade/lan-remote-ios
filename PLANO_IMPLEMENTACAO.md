# Plano de Arquitetura e Implementação: iOS (SwiftUI + Native Network)

> **Projeto:** `lan-remote-ios`  
> **Objetivo:** Aplicativo nativo para iPhone e iPad para controle remoto via rede local (LAN) da TV LG NetCast (47LN5700 e compatíveis), operando 100% offline na sub-rede Wi-Fi, sem intermediários, sem nuvem, com latência mínima e feedback tátil háptico realista.

---

## 1. Stack Tecnológica

| Camada | Tecnologia | Justificativa |
|---|---|---|
| **Linguagem** | Swift 6.4 (Swift 5.0/6.0 compatível) | Concorrência moderna (`async/await`, `@MainActor`, `Task`), tipagem estrita e segurança de memória. |
| **Interface (UI)** | SwiftUI nativo | Design adaptativo moderno (iPhone SE ao 17 Pro Max), suporte a Safe Areas, Dark OLED. |
| **Cliente HTTP** | `URLSession` nativo | Conexões HTTP assíncronas com timeout granular (3.5s) e zero dependências externas. |
| **Descoberta de Rede** | Network framework (`NWConnection` / UDP Multicast SSDP) + Port Scanner TCP | Descoberta automática de TVs na LAN com fallback de varredura rápida na porta 8080. |
| **Persistência Local** | `UserDefaults` com codificação JSON | Persistência atômica, segura e imediata de IP, porta, credenciais e sessão. |
| **Feedback Tátil** | `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` | Haptics táteis refinados em cada clique de botão e navegação. |
| **Integração com Hardware** | `AVAudioSession` / `MPVolumeView` | Interceptação das teclas físicas de volume do iPhone para comando direto na TV. |
| **Gerenciamento de Projeto** | XcodeGen 2.46.0 (`project.yml`) | Reprodutibilidade determinística do `.xcodeproj` sem conflitos de merge Git. |

---

## 2. Requisitos Críticos de Rede & Segurança no iOS

### 2.1. App Transport Security (ATS)
A TV LG NetCast opera exclusivamente em HTTP puro (sem TLS/HTTPS) na porta `8080`.
Configuração no `Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

### 2.2. Permissão de Rede Local (iOS 14+)
A Apple exige aviso explicativo para envio de pacotes na sub-rede local:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>O LanRemote necessita de acesso à rede local para descobrir e controlar sua TV LG NetCast via Wi-Fi.</string>
<key>NSBonjourServices</key>
<array>
    <string>_roap._tcp</string>
    <string>_udap._tcp</string>
</array>
```

### 2.3. Regra Mandatória do Protocolo ROAP
- O cabeçalho `User-Agent` **NÃO DEVE** conter `"UDAP/2.0"` ao enviar comandos ROAP (`/roap/api/command`). Caso contrário, a TV retorna `HTTP 400 Bad Request`.
- Padrão utilizado: `User-Agent: lg_roap_control/1.0.0 (iOS)`
- `Content-Type: application/atom+xml`

---

## 3. Estrutura do Projeto

```
lan-remote-ios/
├── project.yml                          # Configuração do XcodeGen
├── .gitignore
├── build.sh                             # Script de compilação e teste local
├── .github/
│   └── workflows/
│       └── ios-ci.yml                   # Pipeline de CI (Linux preflight + macOS build)
├── LanRemote/
│   ├── App/
│   │   ├── LanRemoteApp.swift           # Ponto de entrada @main do app
│   │   └── Info.plist                   # Metadados e permissões de rede
│   ├── Model/
│   │   ├── TVKey.swift                  # Enum de códigos e descrições do protocolo ROAP
│   │   └── TVConfig.swift               # Modelo de dados de conexão e autenticação
│   ├── Services/
│   │   ├── LGTVClient.swift             # Motor de rede, fila serial, debounce e sessão
│   │   ├── NetworkDiscovery.swift       # Busca SSDP e varredura TCP de rede
│   │   ├── HapticManager.swift          # Controlador de vibrações táteis
│   │   └── VolumeButtonHandler.swift    # Interceptador de teclas físicas de volume
│   ├── Views/
│   │   ├── RemoteView.swift             # Tela principal com controles em zona de polegar
│   │   ├── RemoteComponents.swift       # D-Pad circular, botões de comando e rockers
│   │   ├── SettingsView.swift           # Configuração de IP, porta e pareamento de 6 dígitos
│   │   └── DiscoveryView.swift          # Varredura visual de dispositivos na rede
│   └── Resources/
│       ├── Assets.xcassets/             # Cores e ícone do aplicativo
│       └── PrivacyInfo.xcprivacy        # Manifesto de privacidade exigido pela Apple
└── LanRemoteTests/
    └── LanRemoteTests.swift             # Testes unitários do cliente, parser XML e keys
```

---

## 4. Fases de Execução

1. **Fase 1: Configuração do Projeto e Metadados**
   - Criação da árvore de arquivos, `project.yml`, `Info.plist` e `PrivacyInfo.xcprivacy`.
   - Geração do projeto Xcode via `xcodegen`.
2. **Fase 2: Motor de Rede e Protocolo ROAP**
   - Implementação de `TVKey`, `TVConfig`, `LGTVClient`.
   - Implementação de `NetworkDiscovery` com SSDP UDP Multicast e Port Scanner TCP.
   - Implementação de `HapticManager` e `VolumeButtonHandler`.
3. **Fase 3: Interface de Usuário Mobile SwiftUI**
   - Telas ergonômicas `RemoteView`, `RemoteComponents`, `SettingsView`, `DiscoveryView`.
   - Suporte a Dark Mode OLED e haptics em todos os botões.
4. **Fase 4: Testes Unitários e Validação de Compilação**
   - Implementação de suite de testes unitários `LanRemoteTests`.
   - Execução e validação de compilação limpa com `xcodebuild`.
5. **Fase 5: Automação CI/CD**
   - Workflow do GitHub Actions `.github/workflows/ios-ci.yml`.
   - Script de compilação determinístico `build.sh`.
