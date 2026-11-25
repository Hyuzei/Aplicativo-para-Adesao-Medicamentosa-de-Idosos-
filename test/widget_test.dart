import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:med_app/app.dart';
import 'package:med_app/features/auth/data/local_account_repository.dart';
import 'package:med_app/features/auth/data/local_auth_service.dart';
import 'package:med_app/features/auth/models/user_account.dart';
import 'package:med_app/features/family/data/firebase_care_service.dart';
import 'package:med_app/models/medication.dart';

const _testEmail = 'ana@example.com';
const _testPassword = 'senha-teste-123';

Future<InMemoryAccountRepository> _createTestRepository({
  required WidgetTester tester,
  AccountRole role = AccountRole.caredFor,
}) async {
  final repository = InMemoryAccountRepository();
  await tester.runAsync(
    () => LocalAuthService(repository).register(
      name: 'Ana Exemplo',
      email: _testEmail,
      password: _testPassword,
      role: role,
    ),
  );
  return repository;
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('auth-email-field')), _testEmail);
  await tester.enterText(
    find.byKey(const Key('auth-password-field')),
    _testPassword,
  );
  final submitButton = find.byKey(const Key('auth-submit-button'));
  await tester.ensureVisible(submitButton);
  await tester.tap(submitButton);
  await tester.pumpAndSettle();
}

Future<void> _fillMedicationForm(
  WidgetTester tester, {
  required String name,
  required String time,
  String? stock,
}) async {
  await tester.enterText(find.byKey(const Key('medication-name-field')), name);
  await tester.enterText(
    find.byKey(const Key('medication-dosage-field')),
    '1 comprimido',
  );
  await tester.enterText(find.byKey(const Key('medication-times-field')), time);
  if (stock != null) {
    await tester.enterText(
      find.byKey(const Key('medication-stock-field')),
      stock,
    );
  }
  await tester.tap(find.byKey(const Key('save-medication-button')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('theme text pairs meet the 4.5 to 1 contrast target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = await _createTestRepository(tester: tester);
    await tester.pumpWidget(MyApp(accountRepository: repository));
    await tester.pumpAndSettle();
    _expectThemeContrast(Theme.of(tester.element(find.byType(Scaffold).first)));

    await _signIn(tester);
    await tester.tap(find.text('Configurações').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dark-mode-switch')));
    await tester.pumpAndSettle();
    _expectThemeContrast(Theme.of(tester.element(find.byType(Scaffold).first)));
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byKey(const Key('dark-mode-switch'))))
        .pop();
    await tester.pumpAndSettle();
    expect(find.text('Notificações'), findsNothing);
  });

  testWidgets('creates an account with the caregiver role and signs out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = InMemoryAccountRepository();
    await tester.pumpWidget(MyApp(accountRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Entrar na sua conta'), findsOneWidget);
    expect(find.text('Criar conta'), findsOneWidget);
    await tester.tap(find.text('Criar conta').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuidador'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('auth-name-field')),
      'Maria da Silva',
    );
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'MARIA@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      _testPassword,
    );
    await tester.enterText(
      find.byKey(const Key('auth-confirm-password-field')),
      _testPassword,
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Olá, Maria'), findsOneWidget);
    expect(find.text('Painel do cuidador'), findsOneWidget);
    expect(find.text('Nenhuma pessoa idosa conectada'), findsOneWidget);
    expect(find.text('Medicamento de exemplo A'), findsNothing);
    expect((await repository.loadAccounts()).single.email, 'maria@example.com');

    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();
    final signOutButton = find.byKey(const Key('sign-out-button'));
    await tester.ensureVisible(signOutButton);
    await tester.pumpAndSettle();
    await tester.tap(signOutButton);
    await tester.pumpAndSettle();
    expect(find.text('Entrar na sua conta'), findsOneWidget);

    await tester.tap(find.text('Pessoa cuidada'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'maria@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      _testPassword,
    );
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('E-mail, senha ou perfil incorretos.'), findsOneWidget);

    await tester.tap(find.text('Cuidador'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auth-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('Olá, Maria'), findsOneWidget);
    expect(find.text('Painel do cuidador'), findsOneWidget);
  });

  testWidgets('restores an authenticated account when the app starts', (
    tester,
  ) async {
    final account = UserAccount(
      id: 'restored-user',
      name: 'Ana Exemplo',
      email: _testEmail,
      role: AccountRole.caredFor,
      passwordSalt: '',
      passwordHash: '',
    );
    await tester.pumpWidget(
      MyApp(
        accountRepository: InMemoryAccountRepository(),
        authenticationService: _RestoringAuthenticationService(account),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Olá, Ana'), findsOneWidget);
    expect(find.text('Entrar na sua conta'), findsNothing);
  });

  testWidgets('account creation is reachable on a phone-sized screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final repository = InMemoryAccountRepository();
    await tester.pumpWidget(MyApp(accountRepository: repository));
    await tester.pumpAndSettle();

    final createAccountButton = find.text('Criar conta').first;
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth-name-field')), findsOneWidget);

    await tester.tap(find.text('Cuidador'));
    await tester.enterText(
      find.byKey(const Key('auth-name-field')),
      'João Cuidador',
    );
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'joao@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      _testPassword,
    );
    await tester.enterText(
      find.byKey(const Key('auth-confirm-password-field')),
      _testPassword,
    );

    final submitButton = find.byKey(const Key('auth-submit-button'));
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Painel do cuidador'), findsOneWidget);
    expect(find.text('Nenhuma pessoa idosa conectada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caregiver sees no demo data before connecting a person', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await _createTestRepository(
      tester: tester,
      role: AccountRole.caregiver,
    );
    await tester.pumpWidget(MyApp(accountRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuidador'));
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(find.text('Painel do cuidador'), findsOneWidget);
    expect(find.text('Nenhuma pessoa idosa conectada'), findsOneWidget);
    expect(find.text('Medicamento de exemplo A'), findsNothing);
    expect(find.text('Já tomei'), findsNothing);
    expect(find.text('Acompanhar'), findsOneWidget);
    expect(find.text('Família'), findsNothing);

    await tester.tap(find.text('Medicamentos'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma pessoa idosa conectada'), findsOneWidget);
    expect(find.text('Medicamento de exemplo A'), findsNothing);

    await tester.tap(find.text('Histórico'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma pessoa idosa conectada'), findsOneWidget);
    expect(find.text('Medicamento de exemplo A'), findsNothing);

    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma pessoa idosa está conectada.'), findsOneWidget);
  });

  testWidgets('dark mode can be toggled from the settings sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await _createTestRepository(tester: tester);
    await tester.pumpWidget(MyApp(accountRepository: repository));
    await tester.pumpAndSettle();
    await _signIn(tester);

    await tester.tap(find.text('Configurações').first);
    await tester.pumpAndSettle();
    expect(find.text('Modo escuro'), findsOneWidget);
    expect(find.text('Ampliar texto para 200%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dark-mode-switch')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byKey(const Key('large-text-switch')));
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first))
          .scale(1),
      greaterThan(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('assisted account starts empty and can record a dose', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await _createTestRepository(tester: tester);
    await tester.pumpWidget(MyApp(accountRepository: repository));
    await tester.pumpAndSettle();
    await _signIn(tester);

    expect(find.text('Medicamento de exemplo A'), findsNothing);
    expect(find.text('Nenhum medicamento cadastrado'), findsOneWidget);

    final addButton = find.text('Adicionar medicamento');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    await _fillMedicationForm(
      tester,
      name: 'Remédio de teste',
      time: '13:00',
      stock: '4',
    );

    await tester.tap(find.text('Remédios'));
    await tester.pumpAndSettle();
    expect(find.text('Estoque: 4'), findsOneWidget);
    await tester.tap(find.text('Início'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Já tomei'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 1 doses confirmadas'), findsOneWidget);
    expect(
      find.textContaining(
        'Estoque baixo: restam 3 unidades de Remédio de teste.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Remédios'));
    await tester.pumpAndSettle();
    expect(find.text('Estoque: 3'), findsOneWidget);
  });

  testWidgets('adds a medication with a valid time', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await _createTestRepository(tester: tester);
    await tester.pumpWidget(MyApp(accountRepository: repository));
    await tester.pumpAndSettle();
    await _signIn(tester);
    await tester.tap(find.text('Remédios'));
    await tester.pumpAndSettle();
    final addButton = find.text('Cadastrar medicamento');
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    await _fillMedicationForm(
      tester,
      name: 'Vitamina de teste',
      time: '09:30',
      stock: '2',
    );

    expect(find.text('Vitamina de teste'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
    expect(
      find.textContaining(
        'Estoque baixo: restam 2 unidades de Vitamina de teste.',
      ),
      findsOneWidget,
    );
    expect(find.text('Estoque: 2'), findsOneWidget);
  });

  testWidgets('records a delayed dose for the linked family member', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await _createTestRepository(tester: tester);
    await tester.pumpWidget(MyApp(accountRepository: repository));
    await tester.pumpAndSettle();
    await _signIn(tester);
    await tester.tap(find.text('Remédios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadastrar medicamento'));
    await tester.pumpAndSettle();
    await _fillMedicationForm(tester, name: 'Remédio atrasado', time: '13:00');
    await tester.tap(find.text('Início'));
    await tester.pumpAndSettle();

    final doseActions = find.byTooltip('Mais opções');
    await tester.ensureVisible(doseActions);
    await tester.tap(doseActions);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar como atrasada'));
    await tester.pumpAndSettle();

    expect(
      find.text('Atraso registrado e aviso demonstrativo enviado à família.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Família'));
    await tester.pumpAndSettle();
    expect(find.textContaining('registrada como atrasada'), findsWidgets);
  });

  testWidgets('caregiver connects to a person using the one-time token', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await _createTestRepository(
      tester: tester,
      role: AccountRole.caregiver,
    );
    final careService = _FakeCareService();
    await tester.pumpWidget(
      MyApp(accountRepository: repository, careService: careService),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuidador'));
    await tester.pumpAndSettle();
    await _signIn(tester);

    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-care-link-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('care-link-token-field')),
      'abcd-efgh-jklm',
    );
    await tester.tap(find.byKey(const Key('connect-caregiver-button')));
    await tester.pumpAndSettle();

    expect(careService.lastToken, 'abcd-efgh-jklm');
    expect(find.textContaining('Pessoa de Teste'), findsWidgets);
    expect(find.text('Nenhuma pessoa idosa conectada'), findsNothing);
    await tester.tap(find.text('Acompanhar'));
    await tester.pumpAndSettle();
    expect(find.text('Pessoa de Teste'), findsOneWidget);
    await tester.tap(find.text('Medicamentos'));
    await tester.pumpAndSettle();
    expect(find.text('Cadastrar medicamento'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caregiver is alerted when an assisted dose is marked missed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = await _createTestRepository(
      tester: tester,
      role: AccountRole.caregiver,
    );
    final careService = _FakeCareService()
      ..linkedPerson = const LinkedPerson(
        id: 'assisted-id',
        name: 'Pessoa de Teste',
        email: 'pessoa@example.com',
      );
    await tester.pumpWidget(
      MyApp(accountRepository: repository, careService: careService),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuidador'));
    await tester.pumpAndSettle();
    await _signIn(tester);

    careService.emitDoseStatuses('assisted-id', {
      'medicine-id|08:00': DoseStatus.missed,
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();

    expect(find.textContaining('registrada como atrasada'), findsWidgets);
    expect(find.textContaining('Pessoa de Teste'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caregiver can disconnect and reconnect with a new token', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = await _createTestRepository(
      tester: tester,
      role: AccountRole.caregiver,
    );
    final careService = _FakeCareService()
      ..linkedPerson = const LinkedPerson(
        id: 'assisted-id',
        name: 'Pessoa de Teste',
        email: 'pessoa@example.com',
      );
    await tester.pumpWidget(
      MyApp(accountRepository: repository, careService: careService),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuidador'));
    await tester.pumpAndSettle();
    await _signIn(tester);

    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('disconnect-care-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('disconnect-care-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-disconnect-button')));
    await tester.pumpAndSettle();

    expect(careService.disconnectCalls, 1);
    expect(find.text('Nenhuma pessoa idosa está conectada.'), findsOneWidget);
    expect(find.byKey(const Key('open-care-link-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-care-link-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('care-link-token-field')),
      'WXYZ-2345-ABCD',
    );
    await tester.tap(find.byKey(const Key('connect-caregiver-button')));
    await tester.pumpAndSettle();

    expect(careService.lastToken, 'WXYZ-2345-ABCD');
    expect(find.textContaining('Pessoa de Teste'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caregiver can add and disconnect multiple assisted people', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = await _createTestRepository(
      tester: tester,
      role: AccountRole.caregiver,
    );
    final careService = _FakeCareService()
      ..linkedPerson = const LinkedPerson(
        id: 'assisted-one',
        name: 'Pessoa Um',
        email: 'um@example.com',
      )
      ..peopleToConnect.add(
        const LinkedPerson(
          id: 'assisted-two',
          name: 'Pessoa Dois',
          email: 'dois@example.com',
        ),
      );
    await tester.pumpWidget(
      MyApp(accountRepository: repository, careService: careService),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuidador'));
    await tester.pumpAndSettle();
    await _signIn(tester);

    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-care-link-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('care-link-token-field')),
      'wxyz-2345-abcd',
    );
    await tester.tap(find.byKey(const Key('connect-caregiver-button')));
    await tester.pumpAndSettle();

    expect(careService.lastToken, 'wxyz-2345-abcd');
    expect(find.byKey(const Key('caregiver-person-selector')), findsOneWidget);
    expect(find.text('Pessoa Dois'), findsWidgets);
    await tester.tap(find.byKey(const Key('caregiver-person-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pessoa Um').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pessoa Um'), findsWidgets);

    await tester.tap(find.byKey(const Key('disconnect-care-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-disconnect-button')));
    await tester.pumpAndSettle();

    expect(careService.disconnectCalls, 1);
    expect(find.textContaining('Pessoa Dois'), findsOneWidget);
    expect(find.byKey(const Key('caregiver-person-selector')), findsNothing);
    expect(find.byKey(const Key('add-care-link-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caregiver cannot connect a fifth assisted person', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = await _createTestRepository(
      tester: tester,
      role: AccountRole.caregiver,
    );
    final careService = _FakeCareService()
      ..linkedPeople.addAll([
        for (var index = 1; index <= CareService.maxCaregiverPatients; index++)
          LinkedPerson(
            id: 'assisted-$index',
            name: 'Pessoa $index',
            email: 'pessoa$index@example.com',
          ),
      ])
      ..linkedPerson = const LinkedPerson(
        id: 'assisted-1',
        name: 'Pessoa 1',
        email: 'pessoa1@example.com',
      );
    await tester.pumpWidget(
      MyApp(accountRepository: repository, careService: careService),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuidador'));
    await tester.pumpAndSettle();
    await _signIn(tester);
    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Limite de 4 pessoas acompanhadas atingido.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('add-care-link-button')), findsNothing);
    expect(find.byKey(const Key('caregiver-person-selector')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assisted person can generate and view a connection token', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = await _createTestRepository(tester: tester);
    final careService = _FakeCareService();
    await tester.pumpWidget(
      MyApp(accountRepository: repository, careService: careService),
    );
    await tester.pumpAndSettle();
    await _signIn(tester);
    await tester.tap(find.text('Família'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('generate-care-token-button')));
    await tester.pumpAndSettle();

    expect(find.text('ABCD-EFGH-JKLM'), findsWidgets);
    expect(
      find.textContaining(' (15 minutos) e para uma única conexão.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('care-token-text')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MyApp(accountRepository: repository, careService: careService),
    );
    await tester.pumpAndSettle();
    await _signIn(tester);
    await tester.tap(find.text('Família'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('care-token-text')), findsOneWidget);
    expect(find.text('ABCD-EFGH-JKLM'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('200 percent text mode keeps phone screens usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = await _createTestRepository(tester: tester);
    await tester.pumpWidget(MyApp(accountRepository: repository));
    await tester.pumpAndSettle();
    await _signIn(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Configurações').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('large-text-switch')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first))
          .scale(1),
      2,
    );

    await tester.tap(find.text('Remédios'));
    await tester.pumpAndSettle();
    final addButton = find.text('Cadastrar medicamento');
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('medication-stock-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(
      tester.element(find.byKey(const Key('medication-stock-field'))),
    ).pop();
    await tester.pumpAndSettle();
  });
}

void _expectThemeContrast(ThemeData theme) {
  final colors = theme.colorScheme;
  final pairs = <(Color, Color, String)>[
    (colors.onSurface, colors.surface, 'surface text'),
    (colors.onSurfaceVariant, colors.surface, 'secondary surface text'),
    (colors.onSurface, colors.surfaceContainerLow, 'card text'),
    (
      colors.onSurfaceVariant,
      colors.surfaceContainerLow,
      'secondary card text',
    ),
    (colors.onPrimary, colors.primary, 'primary button text'),
    (colors.onPrimaryContainer, colors.primaryContainer, 'primary container'),
    (
      colors.onSecondaryContainer,
      colors.secondaryContainer,
      'secondary container',
    ),
    (
      colors.onTertiaryContainer,
      colors.tertiaryContainer,
      'tertiary container',
    ),
    (colors.onErrorContainer, colors.errorContainer, 'error container'),
    (colors.error, colors.surfaceContainerLow, 'error text'),
  ];

  for (final (foreground, background, label) in pairs) {
    expect(
      _contrastRatio(foreground, background),
      greaterThanOrEqualTo(4.5),
      reason: '$label contrast in ${theme.brightness} theme',
    );
  }

  final statusColors = theme.brightness == Brightness.dark
      ? const [Color(0xFF80D8B5), Color(0xFFFF9C8E), Color(0xFFFFD166)]
      : const [Color(0xFF176B52), Color(0xFFB33D2D), Color(0xFF7B5710)];
  for (final statusColor in statusColors) {
    final statusBackground = Color.alphaBlend(
      statusColor.withValues(alpha: 0.12),
      colors.surfaceContainerLow,
    );
    expect(
      _contrastRatio(statusColor, statusBackground),
      greaterThanOrEqualTo(4.5),
      reason: 'dose status label contrast in ${theme.brightness} theme',
    );
  }
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

class _FakeCareService implements CareService {
  LinkedPerson? linkedPerson;
  final List<LinkedPerson> linkedPeople = [];
  final List<LinkedPerson> peopleToConnect = [];
  final StreamController<List<LinkedPerson>> _peopleChanges =
      StreamController<List<LinkedPerson>>.broadcast();
  final Map<String, StreamController<Map<String, DoseStatus>>>
  _doseStatusChanges = {};
  CareLinkToken? activeToken;
  String? lastToken;
  int disconnectCalls = 0;

  @override
  Future<CareLinkToken> createOneTimeToken(UserAccount assisted) async {
    final token = CareLinkToken(
      code: 'ABCDEFGHJKLM',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
    activeToken = token;
    return token;
  }

  @override
  Future<CareLinkToken?> getActiveToken(UserAccount assisted) async =>
      activeToken?.isExpired == true ? null : activeToken;

  @override
  Future<void> revokeToken(UserAccount assisted, String code) async {
    if (activeToken?.code == code.replaceAll('-', '').toUpperCase()) {
      activeToken = null;
    }
  }

  @override
  Future<LinkedPerson?> getConnectedPerson(UserAccount account) async =>
      linkedPerson;

  @override
  Future<List<LinkedPerson>> getConnectedPeople(UserAccount caregiver) async =>
      List<LinkedPerson>.of(_currentLinkedPeople);

  @override
  Stream<LinkedPerson?> watchConnectedPerson(UserAccount account) =>
      Stream.value(linkedPerson);

  @override
  Stream<List<LinkedPerson>> watchConnectedPeople(
    UserAccount caregiver,
  ) async* {
    yield List<LinkedPerson>.of(_currentLinkedPeople);
    yield* _peopleChanges.stream;
  }

  @override
  Future<LinkedPerson> connectCaregiverWithToken(
    UserAccount caregiver,
    String token,
  ) async {
    lastToken = token;
    if (linkedPeople.isEmpty && linkedPerson != null) {
      linkedPeople.add(linkedPerson!);
    }
    final person = peopleToConnect.isEmpty
        ? const LinkedPerson(
            id: 'assisted-id',
            name: 'Pessoa de Teste',
            email: 'pessoa@example.com',
          )
        : peopleToConnect.removeAt(0);
    linkedPerson = person;
    if (!linkedPeople.any((connected) => connected.id == person.id)) {
      linkedPeople.add(person);
    }
    _peopleChanges.add(List<LinkedPerson>.of(linkedPeople));
    return person;
  }

  @override
  Future<void> disconnect(UserAccount account, {String? assistedId}) async {
    disconnectCalls++;
    final personId = assistedId ?? linkedPerson?.id;
    linkedPeople.removeWhere((person) => person.id == personId);
    linkedPerson = linkedPeople.firstOrNull;
    _peopleChanges.add(List<LinkedPerson>.of(_currentLinkedPeople));
  }

  @override
  Stream<List<Medication>> watchMedications(String assistedId) =>
      const Stream.empty();

  @override
  Stream<Map<String, DoseStatus>> watchDoseStatuses({
    required String assistedId,
    required String dateKey,
  }) => _doseStatusChanges
      .putIfAbsent(
        assistedId,
        () => StreamController<Map<String, DoseStatus>>.broadcast(),
      )
      .stream;

  @override
  Future<void> saveMedication(String assistedId, Medication medication) async {}

  @override
  Future<void> deleteMedication(String assistedId, String medicationId) async {}

  @override
  Future<int?> saveDoseStatus({
    required String assistedId,
    required String dateKey,
    required String medicationId,
    required String time,
    required DoseStatus status,
  }) async => null;

  void emitDoseStatuses(String assistedId, Map<String, DoseStatus> statuses) {
    _doseStatusChanges[assistedId]?.add(statuses);
  }

  List<LinkedPerson> get _currentLinkedPeople => linkedPeople.isNotEmpty
      ? linkedPeople
      : linkedPerson == null
      ? const []
      : [linkedPerson!];
}

class _RestoringAuthenticationService implements AuthenticationService {
  const _RestoringAuthenticationService(this.account);

  final UserAccount account;

  @override
  Future<UserAccount?> restoreSession() async => account;

  @override
  Future<UserAccount> register({
    required String name,
    required String email,
    required String password,
    required AccountRole role,
  }) async => account;

  @override
  Future<UserAccount> signIn({
    required String email,
    required String password,
    required AccountRole role,
  }) async => account;

  @override
  Future<void> signOut() async {}
}
