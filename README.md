# Cuidar+ — protótipo de apoio à adesão medicamentosa

Aplicativo Flutter demonstrativo inspirado na proposta do artigo
“Desenvolvimento de um Aplicativo para Auxílio na Adesão Medicamentosa de
Idosos com Notificação a Familiares”.

## Organização do código

```text
lib/
├── main.dart
├── app.dart
├── models/
│   └── medication.dart
├── features/
│   ├── home/presentation/
│   │   ├── medication_prototype_app.dart
│   │   └── home_page.dart
│   ├── medication/presentation/
│   │   ├── medications_page.dart
│   │   └── medication_form_sheet.dart
│   ├── history/presentation/
│   │   └── history_page.dart
│   ├── auth/
│   │   ├── data/
│   │   ├── models/
│   │   └── presentation/
│   └── family/presentation/
│       ├── family_page.dart
│       └── family_form_sheet.dart
└── shared/
    └── widgets/
        └── prototype_widgets.dart
```

- `app.dart` configura o tema e inicializa o aplicativo.
- `models/` contém os modelos da rotina e do registro das doses.
- `features/` separa as telas e formulários por funcionalidade.
- `features/auth/` contém o login, cadastro e armazenamento local das contas.
- `shared/widgets/` reúne componentes reutilizados entre as telas.

## Contas e vínculo remoto

O aplicativo usa Firebase Authentication (e-mail e senha) e Cloud Firestore
para contas e sincronização entre dispositivos Android. Escolha **Cuidador**
ou **Pessoa cuidada** ao criar a conta e entre usando o mesmo perfil escolhido
no cadastro.

A pessoa cuidada gera um token temporário, válido por 15 minutos e para uma
única conexão. O cuidador informa esse token para iniciar o vínculo e pode
acompanhar até quatro pessoas, selecionando qual deseja ver ou desconectar.
Depois da conexão, o cuidador pode consultar os medicamentos e o status das
doses do dia; somente a pessoa cuidada pode alterar a rotina e registrar doses.

Antes do primeiro cadastro, habilite o provedor **E-mail/senha** em Firebase
Authentication, crie o banco Cloud Firestore e publique as regras do projeto a
partir da raiz do repositório:

```powershell
firebase.cmd deploy --only firestore:rules --project <ID_DO_PROJETO>
```

O aplicativo está configurado para Android com `lib/firebase_options.dart` e
`android/app/google-services.json`. Para usar outra plataforma, gere a
configuração correspondente com FlutterFire.

## Funcionalidades do protótipo

- Tela de entrada inicial com login e criação de conta para os dois perfis.
- Rotina diária com horários, dosagens prescritas e confirmação de doses.
- Cadastro, edição e remoção de medicamentos, incluindo horários e estoque.
- Registro local de doses confirmadas e atrasadas e resumo demonstrativo por
período (hoje, últimos 7 dias e últimos 30 dias).
- Vínculo remoto entre cuidador e pessoa cuidada usando token temporário.
- Sincronização pelo Firestore dos medicamentos e das doses do dia.
- Alarmes locais para os horários dos medicamentos e aviso local ao cuidador
  quando uma dose segue sem confirmação por 15 minutos. Se o app sincronizar
  depois desse prazo, exibe o aviso pendente imediatamente e agenda a próxima
  ocorrência diária. Com o app do cuidador aberto, doses pendentes também são
  verificadas a cada 30 segundos e geram um aviso em primeiro plano.
- Lembrete adiado e opção para ampliar os textos.
- Interface em português com botões grandes, contraste reforçado e linguagem
simples.

## Limites importantes

Este é um protótipo. Os alarmes e avisos são agendados localmente nos aparelhos
que têm o app instalado; o envio remoto por push quando o cuidador não tiver o
app configurado neste aparelho requer uma Cloud Function adicional. O Android
pode atrasar alarmes se a permissão de notificações ou de alarmes exatos estiver
bloqueada; habilite-as em **Configurações > Notificações** no app e nas
configurações do sistema. O histórico de períodos anteriores continua
demonstrativo. Antes de qualquer uso real, revise as regras, políticas de
privacidade e requisitos aplicáveis. Não use dados reais de saúde ou senhas
reutilizadas. O indicador de adesão não é recomendação clínica. O artigo
apresenta resultados esperados e planeja avaliar a usabilidade com 5 a 10
participantes, usando SUS, tempo de execução, erros, sucesso das tarefas e
satisfação; não reporta resultados empíricos dessa avaliação.

O aplicativo não substitui prescrição nem orientação de profissionais de saúde.
Os dados de exemplo não devem ser usados para orientar tratamentos.

## Executar

Com Flutter instalado e um dispositivo Android conectado, execute:

```powershell
flutter pub get
flutter run
```

As opções Firebase geradas atualmente incluem apenas Android. Os testes de
widget usam serviços locais injetados e não precisam de acesso ao Firebase.

Para compilar ou executar como aplicativo Windows desktop, o Flutter exige uma
instalação compatível do Visual Studio com a carga de trabalho **Desenvolvimento
para desktop com C++**, incluindo MSVC v142 (ou a versão mais recente oferecida
pelo instalador), ferramentas C++ CMake e Windows 10 SDK. Depois da instalação,
confirme a configuração com `flutter doctor -v` e execute `flutter run -d windows`.

Para analisar e testar:

```powershell
flutter analyze
flutter test
```
