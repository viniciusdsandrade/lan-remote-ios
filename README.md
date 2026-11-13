# Lan Remote iOS

Aplicativo nativo para **iPhone** e **iPad** desenvolvido em **SwiftUI** para controle remoto de televisores **LG NetCast** (série LN5700, modelos 2012-2013) operando **100% na rede local (LAN)**.

---

## 🚀 Destaques e Funcionalidades

- **Liga a TV sem levantar do sofá**: em standby a LG NetCast desliga a rede, então o app acorda a **TV Box** (Android TV) ligada no HDMI e ela liga a TV pelo **HDMI-CEC (SIMPLINK)**. Detalhes em [Ligar a TV pelo app](#-ligar-a-tv-pelo-app).
- **Botões que se explicam**: ícone + nome em português em cada botão, agrupados por função (Navegação, Volume e canal, Recursos da TV, Reprodução, Botões coloridos). **Segurar** um botão mostra no rodapé o que ele faz, sem enviar nada à TV; o **?** abre o **Guia dos botões** completo. Os mesmos textos alimentam o VoiceOver.
- **Estado da TV à vista**: `Ligada`, `Ligada · sem resposta` (quando a TV responde ao ping na rede mas a porta 8080 oscila; um toque que não chega na hora é descartado, nunca enviado depois), `Ligada · conflito de IP` (quando outro equipamento responde no mesmo IP logo após a TV), `Ligada · falta parear` (quando a TV responde mas recusa o app: um cartão leva ao pareamento), `Desligada` ou `Ligando…` no topo, com volume e entrada atual. Com a TV desligada o controle fica esmaecido e um cartão mostra o botão **Ligar**. Quando o problema é o iPhone, e não a TV, o topo diz `iPhone fora do Wi-Fi` ou `Sem acesso à rede local` (permissão de Rede Local negada pelo iOS) e um cartão abre os Ajustes, em vez de mostrar a TV como desligada.
- **Zero Dependências Externas**: Construído puramente sobre o ecossistema Apple (`SwiftUI`, `Network`, `Security`, `CryptoKit`, `Vision`).
- **Arquitetura Serverless Local**: O iPhone comunica-se diretamente com a TV pela porta `8080` (HTTP) através da rede Wi-Fi local. Zero nuvem, zero telemetria e latência inferior a 100ms.
- **Toque na hora ou nunca**: cada toque chega à TV em dezenas de milissegundos ou é descartado; nada fica guardado para sair depois. Toques de volume em sequência saem a cada 0,15 s e o volume para de mexer quando o dedo para. Detalhes em [Teclas: na hora ou nunca](#-teclas-na-hora-ou-nunca).
- **Feedback Háptico Realista**: Cada botão (D-Pad, volume, ok, numérico, power) aciona vibrações táteis finas (`UIImpactFeedbackGenerator`).
- **D-Pad Circular Ergonômico**: Direcionais táteis com botão central OK e gangorras verticais de volume e canal na zona de alcance do polegar.
- **Descoberta Automática de Rede**: varredura da sub-rede **do próprio iPhone** (lida da interface Wi-Fi) na porta 8080, confirmando cada aparelho pelo ROAP; acha a TV em poucos segundos mesmo numa instalação nova ou depois de o roteador trocar o IP dela. No iPhone a busca SSDP/DLNA não recebe resposta: o iOS só deixa enviar multicast e broadcast a apps com o entitlement `com.apple.developer.networking.multicast`, que a Apple concede só a pedido e nunca a uma conta gratuita.
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

# (opcional) Regenera o ícone do app: mesmo controle do ícone do Mac, nas aparências padrão, escura e tinted
swift scripts/make_app_icon.swift LanRemote/Resources/Assets.xcassets/AppIcon.appiconset

# 4. Roda os testes num simulador (assinado ad-hoc: o teste do Keychain precisa de entitlements)
xcodebuild test \
  -project LanRemote.xcodeproj \
  -scheme LanRemote \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="-"
```

---

## 📲 Instalar no iPhone

É um app pessoal, instalado direto pelo Mac (sem App Store nem TestFlight). Com uma conta Apple
gratuita a assinatura vale **7 dias**: depois disso o iPhone se recusa a abrir o app ("perfil não
confiável") até ele ser instalado de novo.

1. No Xcode, entre com o seu Apple ID (Settings > Accounts).
2. Pareie o iPhone com o Mac uma vez pelo cabo ("Confiar neste computador") e ligue o Modo de
   Desenvolvedor no iPhone (Ajustes > Privacidade e Segurança).
3. Prepare a configuração local (time de assinatura e iPhone, guardados em
   `~/.config/lan-remote/ios.env`, fora do repositório):

   ```bash
   ./scripts/preparar_ios_env.sh
   ```

4. Instale (e repita a cada 7 dias):

   ```bash
   ./scripts/instalar_iphone.sh              # instala e abre o app
   ./scripts/instalar_iphone.sh --sem-abrir  # só instala
   ```

O script diz até quando a assinatura vale. Na primeira instalação, confie no desenvolvedor no iPhone
(Ajustes > Geral > Gerenciamento de VPN e Dispositivo). Se o iPhone já tem o app com outro identificador
(uma instalação antiga), ponha `BUNDLE_ID=` com ele em `~/.config/lan-remote/ios.env`: instalar por cima
mantém os pareamentos com a TV e a TV Box, que somem se o app for desinstalado.

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
> **Atenção ao cabeçalho User-Agent**: No firmware `05.02.11` da TV xxLN5700, requisições ROAP **não** podem conter `"UDAP/2.0"` no `User-Agent`. O app utiliza `User-Agent: lg_roap_control/1.0.0 (iOS)`.

### ⚡ Teclas: na hora ou nunca

Um toque vale na hora em que é dado. Se a TV não puder recebê-lo logo, ele é descartado: um passo de
volume que chega segundos depois de o dedo sair do botão é pior do que um toque sem efeito.

- **Sem fila que escorre.** Antes, cada toque entrava numa fila e saía a cada 0,3 s: dez toques em 1,2 s
  faziam o volume continuar subindo por 2 s depois do último (medido na TV: 1,95 s). Agora só um toque
  espera a vez; outro toque da mesma tecla nesse intervalo se junta a ele (e não vibra, porque não vira
  outra tecla). Teclas diferentes, como os dígitos de um canal, continuam saindo todas, em ordem.
- **Validade de 0,8 s.** Uma tecla que não saiu do iPhone até 0,8 s depois do toque é descartada; quando
  é a TV que não aceita a conexão, o iPhone vibra em aviso. Com a TV `Ligada · sem resposta` os toques
  não são guardados para depois.
- **Descanso da TV.** A TV descarta uma tecla que chega cedo demais depois de outra. Entre passos de
  volume o app espera 0,15 s a partir da resposta da tecla anterior (medido na xxLN5700: passos a 90 ms
  ou mais registraram todos, a 55 ms um se perdeu); entre as demais teclas, os 0,3 s de sempre.
- **Conexão própria, no máximo uma entrega.** As teclas não passam pelo `URLSession`
  (`TVKeyLink.swift`). A TV perde um pedido de conexão (SYN) de vez em quando (2 em 474 numa medição) e
  o sistema só o repete 1 s depois; o app abre outra tentativa a cada 0,25 s e a primeira que conectar
  leva a tecla. Depois que a requisição saiu, ela nunca é reenviada: a TV poderia executar a tecla duas vezes.
- **Volume no topo.** O número acompanha cada passo que a TV aceitou, e o app só pergunta o volume à TV
  quando os toques param (as consultas usam o mesmo servidor da TV que as teclas).

Conferido na TV real com `testLiveVolumeTapsStopWhenTheFingerStops` (opcional, veja o comentário do
teste; ele nunca passa do volume 9, a não ser que se peça): 10 toques em 1,16 s viraram 8 teclas, a
primeira respondida em 0,02 s e a última 0,11 s depois do último toque, e o volume da TV não mexeu mais.

---

## 🔌 Ligar a TV pelo app

A TV não liga pela rede (em standby o controlador de rede dela desliga; Wake-on-LAN não tem efeito).
O caminho é a **TV Box da sala** (Android TV / Google TV) ligada no HDMI, que acorda a TV pelo CEC:

1. O app manda **Wake-on-LAN** para a TV Box (unicast + broadcast de sub-rede, reenviando a cada ciclo
   de sondagem para que mesmo com o cache ARP frio a resolução ARP ocorra na primeira tentativa e o
   pacote mágico chegue em seguida). A rede da TV Box responde na porta do controle em ~1–2 s.
2. Nessa janela o app aperta **POWER** pelo protocolo do controle remoto do Android TV (o mesmo do app
   Google TV: portas 6466/6467, TLS com certificado próprio, mensagens protobuf).
3. Ao acordar, a TV Box manda **One Touch Play** pelo HDMI-CEC: a TV liga, já na entrada dela. A imagem
   volta em segundos; a rede da TV, em ~40–55 s, e aí o controle volta a responder.

Uma vez só, em **Ajustes › Ligar a TV pelo app**: com a TV ligada na entrada da TV Box, toque em
**Parear**. A TV Box mostra um código de 6 caracteres na TV e o app o lê sozinho: fotografa a tela da
TV (consulta `screen_image` do ROAP), lê o código por OCR (Vision, `ScreenText.swift`) e confere o
dígito verificador dele antes de enviar, o que separa as confusões do OCR (0/D, 8/B). Se não
conseguir, o campo para digitar fica na tela. O app gera um certificado RSA, válido por 20 anos, e o
guarda no Keychain (`AndroidTVIdentity.swift`); a TV Box passa a reconhecê-lo, e o pareamento dura
enquanto esse certificado existir (ele some ao desinstalar o app ou em **Esquecer**; um
certificado novo exige parear de novo). Requisitos:

- **SIMPLINK ligado na TV** (botão SIMPLINK do app → "SIMPLINK Ligado"). Sem ele a TV ignora o CEC.
- **HDMI-CEC na TV Box** (Configurações › Tela e som ou Sistema › Entradas › HDMI-CEC): mantenha o
  **HDMI-CEC ativado** e desative **"Desligar automaticamente"**.
- **Modo de energia na TV Box** (Configurações › Sistema › Energia e alimentação): selecione
  **Modo de consumo elevado (Sempre conectado)** e timer de desligamento em **Nunca**, para a TV Box
  não desconectar do Wi-Fi nem parar de responder ARP após horas em repouso.
- **MAC do Wi-Fi da TV Box**: o iPhone não lê a tabela ARP, então o app tenta os endereços vizinhos ao
  MAC Bluetooth anunciado no Bonjour (`bt=`; os dois costumam ser consecutivos). Se não acordar, digite
  o MAC em Ajustes (na TV Box: Configurações › Sistema › Sobre › Status).
- **IP fixo para a TV Box** (reserva DHCP no roteador): o app também atualiza o endereço pelo Bonjour
  automaticamente a cada 5 min.

Não adianta usar `KEYCODE_TV_POWER` (177) nem `KEYCODE_WAKEUP` (224): a TV Box da sala ignora os dois.
A sequência acima foi validada de ponta a ponta tanto no app para Mac (`lan-remote-mac`) quanto no
app para iPhone (`LanRemote`): TV em standby e TV Box em repouso → TV ligada e respondendo em ~43 s.

Só o app para Mac tem uma reserva quando a TV Box sai do Wi-Fi: o PS5. Acordado pela rede o PS5 não
manda o One Touch Play, então o app do Mac o reinicia por uma sessão do Uso remoto, o que não existe
no iPhone. Se o botão Ligar não achar a TV Box, confira o modo de energia dela (acima) e o Wi-Fi.

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
