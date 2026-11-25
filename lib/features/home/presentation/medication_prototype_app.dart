import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../features/auth/models/user_account.dart';
import '../../../models/medication.dart';
import '../../../services/notification_service.dart';
import '../../../services/overdue_dose_schedule.dart';
import '../../family/data/firebase_care_service.dart';
import '../../family/presentation/family_form_sheet.dart';
import '../../medication/presentation/medication_form_sheet.dart';

part 'home_page.dart';
part '../../medication/presentation/medications_page.dart';
part '../../history/presentation/history_page.dart';
part '../../family/presentation/family_page.dart';
part '../../../shared/widgets/prototype_widgets.dart';

class MedicationPrototypeApp extends StatefulWidget {
  const MedicationPrototypeApp({
    super.key,
    required this.account,
    required this.careService,
    required this.largeText,
    required this.onLargeTextChanged,
    required this.darkMode,
    required this.onDarkModeChanged,
    required this.onSignOut,
  });

  final UserAccount account;
  final CareService? careService;
  final bool largeText;
  final ValueChanged<bool> onLargeTextChanged;
  final bool darkMode;
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onSignOut;

  @override
  State<MedicationPrototypeApp> createState() => _MedicationPrototypeAppState();
}

class _MedicationPrototypeAppState extends State<MedicationPrototypeApp>
    with WidgetsBindingObserver {
  static const _maxNotices = 30;

  int _selectedTab = 0;
  String _historyPeriod = 'Hoje';
  bool _familySharingEnabled = true;
  String _familyName = 'Mariana Oliveira';
  String _familyRelationship = 'Filha';
  String _familyPhone = '(37) 99999-1234';
  final List<AppNotice> _familyNotifications = [];
  // Não é mais `final`: o dia muda com o app aberto (ver _onClockTick).
  late String _todayKey;
  late final List<Medication> _medications;
  final Map<String, DoseStatus> _doseStatuses = {};
  StreamSubscription<List<Medication>>? _medicationSubscription;
  StreamSubscription<Map<String, DoseStatus>>? _doseStatusSubscription;
  StreamSubscription<LinkedPerson?>? _personSubscription;
  StreamSubscription<List<LinkedPerson>>? _peopleSubscription;
  StreamSubscription<AppNotice>? _remoteNoticeSubscription;
  final Map<String, StreamSubscription<List<Medication>>>
  _overdueMedicationSubscriptions = {};
  final Map<String, StreamSubscription<Map<String, DoseStatus>>>
  _overdueStatusSubscriptions = {};
  final Map<String, List<Medication>> _overdueMedications = {};
  final Map<String, Map<String, DoseStatus>> _overdueStatuses = {};
  final Set<String> _overdueStatusSnapshotReady = {};
  final Set<String> _announcedMissedDoseKeys = {};
  final Set<String> _announcedOverdueDoseKeys = {};
  Timer? _clockTimer;
  String? _assistedId;
  CareLinkToken? _activeToken;
  LinkedPerson? _linkedPerson;
  final List<LinkedPerson> _linkedPeople = [];
  bool _careLoading = false;
  bool _tokenBusy = false;
  String? _careError;
  bool _appResumed = true;
  bool _checkingOverdueDoses = false;
  // Falso até o primeiro snapshot de doses chegar: o primeiro snapshot é só a
  // carga inicial e não deve gerar avisos de "mudança".
  bool _doseSnapshotReady = false;

  bool get _isCaregiver => widget.account.role == AccountRole.caregiver;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _todayKey = _dateKey(DateTime.now());
    _clockTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _onClockTick(),
    );
    _medications = [];
    if (widget.careService != null) {
      _careLoading = true;
      unawaited(_initializeCareData());
    }
    unawaited(_initializeNotifications());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    unawaited(_medicationSubscription?.cancel());
    unawaited(_doseStatusSubscription?.cancel());
    unawaited(_personSubscription?.cancel());
    unawaited(_peopleSubscription?.cancel());
    for (final subscription in _overdueMedicationSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    for (final subscription in _overdueStatusSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    if (_isCaregiver) {
      unawaited(
        NotificationService.instance.syncCaregiverOverdueAlerts(
          reminders: const [],
        ),
      );
    }
    unawaited(_remoteNoticeSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed) {
      _onClockTick();
      unawaited(_syncReminders());
    }
  }

  // ---------------------------------------------------------------------------
  // Relógio: virada do dia e expiração do token
  // ---------------------------------------------------------------------------

  void _onClockTick() {
    if (!mounted) return;
    final key = _dateKey(DateTime.now());
    if (key != _todayKey) {
      setState(() {
        _todayKey = key;
        _doseStatuses.clear();
      });
      final assistedId = _assistedId;
      if (widget.careService != null && assistedId != null) {
        _watchCareData(assistedId);
      }
      if (_isCaregiver) {
        for (final subscription in _overdueStatusSubscriptions.values) {
          unawaited(subscription.cancel());
        }
        _overdueStatusSubscriptions.clear();
        _overdueStatuses.clear();
        _overdueStatusSnapshotReady.clear();
        _announcedMissedDoseKeys.clear();
        _announcedOverdueDoseKeys.clear();
        _watchCaregiverOverdueData();
      }
      unawaited(_syncReminders());
      return;
    }
    if (_isCaregiver) unawaited(_checkForegroundOverdueDoses());
    final token = _activeToken;
    if (token != null && token.isExpired) {
      setState(() => _activeToken = null);
    }
  }

  // ---------------------------------------------------------------------------
  // Notificações
  // ---------------------------------------------------------------------------

  Future<void> _initializeNotifications() async {
    final notifications = NotificationService.instance;
    await notifications.requestPermissions();
    if (!mounted) return;

    if (_isCaregiver) {
      _remoteNoticeSubscription = notifications.remoteNotices.listen((notice) {
        if (!mounted) return;
        setState(() => _insertNotice(notice));
      });
    }

    final accountId = widget.account.id;
    if (widget.careService != null && accountId != null) {
      await notifications.registerPushToken(accountId);
    }
    await _syncReminders();
    if (_isCaregiver) await _syncCaregiverOverdueAlerts();
  }

  /// Reagenda os lembretes locais de dose (só a pessoa assistida recebe).
  Future<void> _syncReminders() async {
    if (_isCaregiver) return;
    await NotificationService.instance.syncDoseReminders(
      medications: _medications,
      takenToday: (medicationId, time) =>
          _doseStatuses[_doseKey(medicationId, time)] == DoseStatus.taken,
    );
  }

  void _insertNotice(AppNotice notice) {
    _familyNotifications.insert(0, notice);
    if (_familyNotifications.length > _maxNotices) {
      _familyNotifications.removeRange(
        _maxNotices,
        _familyNotifications.length,
      );
    }
  }

  void _addNotice(String message, {bool demo = false}) {
    _insertNotice(
      AppNotice(message: message, createdAt: DateTime.now(), demo: demo),
    );
  }

  /// Aviso de conexão: aparece na lista e, se o app estiver fechado ou em
  /// segundo plano, também como notificação do sistema.
  void _announceLink(String title, String message) {
    setState(() => _addNotice(message));
    if (_appResumed) {
      _showMessage(message);
    } else {
      unawaited(
        NotificationService.instance.showAlert(title: title, body: message),
      );
    }
  }

  /// Cuidador com o app aberto: avisa quando a pessoa confirma ou atrasa uma
  /// dose. A falta de confirmação também tem um alarme local agendado.
  void _announceDoseChanges(Map<String, DoseStatus> previous) {
    final person = _linkedPerson?.name ?? 'A pessoa acompanhada';
    final messages = <String>[];
    for (final record in _todayRecords) {
      final before =
          previous[_doseKey(record.medication.id, record.time)] ??
          DoseStatus.pending;
      if (record.status == before) continue;
      switch (record.status) {
        case DoseStatus.taken:
          messages.add(
            '$person tomou ${record.medication.name} (${record.time}).',
          );
        case DoseStatus.missed:
          if (!_announcedMissedDoseKeys.add(
            _missedDoseKey(
              _linkedPerson?.id,
              record.medication.id,
              record.time,
            ),
          )) {
            break;
          }
          messages.add(
            '${record.medication.name}: dose das ${record.time} '
            'registrada como atrasada.',
          );
        case DoseStatus.pending:
          break;
      }
    }
    if (messages.isEmpty) return;
    setState(() {
      for (final message in messages) {
        _addNotice(message);
      }
    });
    if (_appResumed) _showMessage(messages.first);
    final missedMessage = messages
        .where((message) => message.contains('dose das'))
        .firstOrNull;
    if (missedMessage != null) {
      unawaited(
        NotificationService.instance.showAlert(
          title: 'Dose não confirmada',
          body: missedMessage,
        ),
      );
    }
  }

  Future<void> _enableNotifications() async {
    final granted = await NotificationService.instance.requestPermissions();
    final enabled = await NotificationService.instance
        .areNotificationsEnabled();
    if (!mounted) return;
    if (granted && enabled) {
      _showMessage('Notificações ativadas.');
    } else {
      _showMessage(
        'As notificações estão bloqueadas. Ative-as nas configurações do '
        'aparelho, em Apps > Cuidar+ > Notificações.',
      );
    }
  }

  Future<void> _openExactAlarmSettings() async {
    await NotificationService.instance.openExactAlarmSettings();
  }

  Future<void> _sendTestNotification() async {
    await NotificationService.instance.showAlert(
      title: 'Cuidar+',
      body: 'As notificações estão funcionando neste aparelho.',
    );
  }

  // ---------------------------------------------------------------------------
  // Dados compartilhados (Firebase)
  // ---------------------------------------------------------------------------

  Future<void> _initializeCareData() async {
    final service = widget.careService;
    if (service == null) return;
    _careError = null;
    try {
      if (_isCaregiver) {
        _linkedPeople
          ..clear()
          ..addAll(await service.getConnectedPeople(widget.account));
        _linkedPerson = _linkedPeople.firstOrNull;
        _assistedId = _linkedPerson?.id;
      } else {
        _assistedId = widget.account.id;
        _linkedPerson = await service.getConnectedPerson(widget.account);
        if (_linkedPerson == null) {
          _activeToken = await service.getActiveToken(widget.account);
        }
      }
      if (!mounted) return;
      if (_assistedId != null) {
        _watchCareData(_assistedId!);
      }
      _watchLink();
      if (_isCaregiver) _watchCaregiverOverdueData();
    } catch (error) {
      if (mounted) setState(() => _careError = _errorText(error));
    } finally {
      if (mounted) {
        setState(() => _careLoading = false);
      }
    }
  }

  /// Acompanha o vínculo em tempo real: a pessoa assistida vê o cuidador
  /// entrar sem reabrir o app, e o cuidador percebe se for desconectado.
  void _watchLink() {
    final service = widget.careService;
    if (service == null) return;
    if (_isCaregiver) {
      unawaited(_peopleSubscription?.cancel());
      _peopleSubscription = service
          .watchConnectedPeople(widget.account)
          .listen(
            _updateLinkedPeople,
            onError: (Object error, StackTrace stackTrace) {
              if (mounted) setState(() => _careError = _errorText(error));
            },
          );
      return;
    }
    unawaited(_personSubscription?.cancel());
    _personSubscription = service
        .watchConnectedPerson(widget.account)
        .listen(
          (person) {
            if (!mounted) return;
            final previous = _linkedPerson;
            if (previous?.id == person?.id) return;
            setState(() {
              _linkedPerson = person;
              if (person != null) _activeToken = null;
            });
            if (person != null) {
              _announceLink(
                'Conta conectada',
                _isCaregiver
                    ? 'Conta de ${person.name} conectada.'
                    : 'Cuidador conectado: ${person.name}.',
              );
            } else {
              _announceLink(
                'Conta desconectada',
                _isCaregiver
                    ? 'A conexão com ${previous?.name ?? 'a pessoa acompanhada'} '
                          'foi encerrada.'
                    : 'Seu cuidador foi desconectado.',
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (mounted) setState(() => _careError = _errorText(error));
          },
        );
  }

  void _updateLinkedPeople(List<LinkedPerson> people) {
    if (!mounted) return;
    final previousId = _linkedPerson?.id;
    final selected =
        people.where((person) => person.id == previousId).firstOrNull ??
        people.firstOrNull;
    final selectionChanged = selected?.id != previousId;
    setState(() {
      _linkedPeople
        ..clear()
        ..addAll(people);
      _linkedPerson = selected;
      _assistedId = selected?.id;
    });
    if (selectionChanged) {
      if (selected == null) {
        _clearCareData();
      } else {
        _watchCareData(selected.id);
      }
    }
    _watchCaregiverOverdueData();
  }

  void _selectCaregiverPerson(LinkedPerson person) {
    if (_linkedPerson?.id == person.id) return;
    setState(() {
      _linkedPerson = person;
      _assistedId = person.id;
      _careError = null;
    });
    _watchCareData(person.id);
  }

  void _watchCaregiverOverdueData() {
    final service = widget.careService;
    if (service == null || !_isCaregiver) return;
    final linkedIds = _linkedPeople.map((person) => person.id).toSet();
    for (final id in _overdueMedicationSubscriptions.keys.toList()) {
      if (linkedIds.contains(id)) continue;
      unawaited(_overdueMedicationSubscriptions.remove(id)?.cancel());
      unawaited(_overdueStatusSubscriptions.remove(id)?.cancel());
      _overdueMedications.remove(id);
      _overdueStatuses.remove(id);
      _overdueStatusSnapshotReady.remove(id);
    }
    for (final person in _linkedPeople) {
      if (!_overdueMedicationSubscriptions.containsKey(person.id)) {
        _overdueMedicationSubscriptions[person.id] = service
            .watchMedications(person.id)
            .listen(
              (medications) {
                if (!mounted) return;
                _overdueMedications[person.id] = medications;
                unawaited(_syncCaregiverOverdueAlerts());
                unawaited(_checkForegroundOverdueDoses());
              },
              onError: (Object error, StackTrace stackTrace) {
                if (mounted) setState(() => _careError = _errorText(error));
              },
            );
      }
      if (!_overdueStatusSubscriptions.containsKey(person.id)) {
        _overdueStatusSubscriptions[person.id] = service
            .watchDoseStatuses(assistedId: person.id, dateKey: _todayKey)
            .listen(
              (statuses) {
                if (!mounted) return;
                _overdueStatuses[person.id] = statuses;
                _overdueStatusSnapshotReady.add(person.id);
                _announceMissedDoses(person, statuses);
                unawaited(_syncCaregiverOverdueAlerts());
                unawaited(_checkForegroundOverdueDoses());
              },
              onError: (Object error, StackTrace stackTrace) {
                if (mounted) setState(() => _careError = _errorText(error));
              },
            );
      }
    }
    unawaited(_syncCaregiverOverdueAlerts());
    unawaited(_checkForegroundOverdueDoses());
  }

  Future<void> _checkForegroundOverdueDoses() async {
    if (!_isCaregiver || !_appResumed || !mounted || _checkingOverdueDoses) {
      return;
    }
    _checkingOverdueDoses = true;
    try {
      final notifications = NotificationService.instance;
      await notifications.initialize();
      if (!mounted || !_appResumed) return;
      final now = tz.TZDateTime.now(tz.local);
      for (final person in _linkedPeople) {
        if (!_overdueStatusSnapshotReady.contains(person.id)) continue;
        final statuses = _overdueStatuses[person.id] ?? const {};
        for (final medication
            in _overdueMedications[person.id] ?? const <Medication>[]) {
          for (final time in medication.times) {
            final status = statuses['${medication.id}|$time'];
            if (status == DoseStatus.taken || status == DoseStatus.missed) {
              continue;
            }
            final schedule = OverdueDoseSchedule.calculate(
              now: now,
              time: time,
              gracePeriod: caregiverOverdueGracePeriod,
            );
            if (schedule?.shouldNotifyImmediately != true) continue;
            final key =
                '${schedule!.handledDateKey}|${person.id}|'
                '${medication.id}|$time';
            if (_announcedOverdueDoseKeys.contains(key)) continue;
            final shown = await notifications.showCaregiverOverdueAlert(
              CaregiverDoseReminder(
                assistedId: person.id,
                assistedName: person.name,
                medicationId: medication.id,
                medicationName: medication.name,
                time: time,
                resolvedToday: false,
              ),
            );
            if (!shown || !mounted) continue;
            _announcedOverdueDoseKeys.add(key);
            final message =
                '${medication.name} de ${person.name} está atrasado. '
                'A dose das $time ainda não foi confirmada.';
            setState(() => _addNotice(message));
          }
        }
      }
    } finally {
      _checkingOverdueDoses = false;
    }
  }

  Future<void> _syncCaregiverOverdueAlerts() async {
    final reminders = <CaregiverDoseReminder>[];
    for (final person in _linkedPeople) {
      for (final medication in _overdueMedications[person.id] ?? const []) {
        for (final time in medication.times) {
          reminders.add(
            CaregiverDoseReminder(
              assistedId: person.id,
              assistedName: person.name,
              medicationId: medication.id,
              medicationName: medication.name,
              time: time,
              resolvedToday: switch (_overdueStatuses[person
                  .id]?['${medication.id}|$time']) {
                DoseStatus.taken || DoseStatus.missed => true,
                _ => false,
              },
            ),
          );
        }
      }
    }
    await NotificationService.instance.syncCaregiverOverdueAlerts(
      reminders: reminders,
    );
  }

  void _announceMissedDoses(
    LinkedPerson person,
    Map<String, DoseStatus> current,
  ) {
    final medications = _overdueMedications[person.id] ?? const [];
    for (final entry in current.entries) {
      if (entry.value != DoseStatus.missed) continue;
      final parts = entry.key.split('|');
      final medication = parts.isEmpty
          ? null
          : medications
                .where((candidate) => candidate.id == parts.first)
                .firstOrNull;
      final medicationId = parts.firstOrNull;
      final time = parts.length > 1 ? parts[1] : '';
      if (medicationId == null ||
          !_announcedMissedDoseKeys.add(
            _missedDoseKey(person.id, medicationId, time),
          )) {
        continue;
      }
      final message =
          '${person.name}: dose de ${medication?.name ?? 'um medicamento'} '
          'registrada como atrasada.';
      if (mounted) {
        setState(() => _addNotice(message));
        if (_appResumed) _showMessage(message);
      }
      unawaited(
        NotificationService.instance.showAlert(
          title: 'Dose não confirmada',
          body: message,
        ),
      );
    }
  }

  void _clearCareData() {
    unawaited(_medicationSubscription?.cancel());
    unawaited(_doseStatusSubscription?.cancel());
    setState(() {
      _assistedId = null;
      _medications.clear();
      _doseStatuses.clear();
    });
  }

  void _watchCareData(String assistedId) {
    final service = widget.careService!;
    unawaited(_medicationSubscription?.cancel());
    unawaited(_doseStatusSubscription?.cancel());
    _doseSnapshotReady = false;
    _medicationSubscription = service
        .watchMedications(assistedId)
        .listen(
          (medications) {
            if (!mounted) return;
            setState(
              () => _medications
                ..clear()
                ..addAll(medications),
            );
            unawaited(_syncReminders());
          },
          onError: (Object error, StackTrace stackTrace) {
            if (mounted) setState(() => _careError = _errorText(error));
          },
        );
    _doseStatusSubscription = service
        .watchDoseStatuses(assistedId: assistedId, dateKey: _todayKey)
        .listen(
          (statuses) {
            if (!mounted) return;
            final previous = Map<String, DoseStatus>.of(_doseStatuses);
            setState(() {
              _doseStatuses.removeWhere(
                (key, _) => key.startsWith('$_todayKey|'),
              );
              for (final entry in statuses.entries) {
                final parts = entry.key.split('|');
                if (parts.length == 2) {
                  _doseStatuses[_doseKey(parts[0], parts[1])] = entry.value;
                }
              }
            });
            if (_isCaregiver) {
              if (_doseSnapshotReady) {
                _announceDoseChanges(previous);
              } else if (_linkedPerson case final person?) {
                _announceMissedDoses(person, statuses);
              }
            }
            _doseSnapshotReady = true;
            unawaited(_syncReminders());
          },
          onError: (Object error, StackTrace stackTrace) {
            if (mounted) setState(() => _careError = _errorText(error));
          },
        );
  }

  // ---------------------------------------------------------------------------
  // Token de conexão
  // ---------------------------------------------------------------------------

  Future<void> _createCareToken() async {
    final service = widget.careService;
    if (service == null || _tokenBusy) return;
    setState(() => _tokenBusy = true);
    try {
      final token = await service.createOneTimeToken(widget.account);
      if (!mounted) return;
      setState(() => _activeToken = token);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Código de conexão'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                token.formatted,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  letterSpacing: 2,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Válido até ${_formatClock(token.expiresAt)} '
                '(15 minutos) e para uma única conexão. Compartilhe apenas '
                'com seu cuidador de confiança.',
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _copyToken(token),
              icon: const Icon(Icons.copy),
              label: const Text('Copiar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Não foi possível gerar o código: ${_errorText(error)}');
      }
    } finally {
      if (mounted) setState(() => _tokenBusy = false);
    }
  }

  Future<void> _copyToken(CareLinkToken token) async {
    await Clipboard.setData(ClipboardData(text: token.formatted));
    if (mounted) _showMessage('Código copiado.');
  }

  Future<void> _revokeActiveToken() async {
    final service = widget.careService;
    final token = _activeToken;
    if (service == null || token == null || _tokenBusy) return;
    setState(() => _tokenBusy = true);
    try {
      await service.revokeToken(widget.account, token.code);
      if (!mounted) return;
      setState(() => _activeToken = null);
      _showMessage('Código cancelado.');
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Não foi possível cancelar o código: ${_errorText(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _tokenBusy = false);
    }
  }

  Future<void> _connectCaregiverWithToken() async {
    final service = widget.careService;
    if (service == null) return;
    var tokenValue = '';
    String? connectionError;
    while (mounted) {
      final token = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            scrollable: true,
            title: const Text('Conectar pessoa idosa'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Use apenas o código recebido da pessoa que deseja acompanhar. '
                  'Não compartilhe sua senha.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('care-link-token-field'),
                  initialValue: tokenValue,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (value) {
                    tokenValue = value;
                    if (connectionError != null) {
                      setDialogState(() => connectionError = null);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Código de 12 caracteres',
                    hintText: 'ABCD-EFGH-JKLM',
                  ),
                ),
                if (connectionError != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      connectionError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const Key('connect-caregiver-button'),
                onPressed: () {
                  if (tokenValue.trim().isEmpty) {
                    setDialogState(
                      () => connectionError = 'Informe o código recebido.',
                    );
                    return;
                  }
                  Navigator.pop(context, tokenValue.trim());
                },
                child: const Text('Conectar'),
              ),
            ],
          ),
        ),
      );
      if (token == null || !mounted) return;

      setState(() {
        _careLoading = true;
        _careError = null;
      });
      try {
        final person = await service.connectCaregiverWithToken(
          widget.account,
          token,
        );
        if (!mounted) return;
        // O listener do vínculo pode ter tratado a conexão antes desta linha.
        final alreadyHandled = _linkedPeople.any(
          (linkedPerson) => linkedPerson.id == person.id,
        );
        setState(() {
          if (!alreadyHandled) _linkedPeople.add(person);
          _linkedPerson = person;
          _assistedId = person.id;
        });
        if (_peopleSubscription == null) _watchLink();
        if (!alreadyHandled) {
          _watchCareData(person.id);
          _watchCaregiverOverdueData();
          setState(() => _addNotice('Conta de ${person.name} conectada.'));
          _showMessage('Conta de ${person.name} conectada.');
        }
        return;
      } catch (error) {
        connectionError =
            'Não foi possível conectar. Confira o código e tente novamente. '
            '${_errorText(error)}';
      } finally {
        if (mounted) setState(() => _careLoading = false);
      }
    }
  }

  Future<void> _disconnectCare() async {
    final service = widget.careService;
    final person = _linkedPerson;
    if (service == null || person == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _isCaregiver ? 'Desconectar pessoa?' : 'Desconectar cuidador?',
        ),
        content: Text(
          _isCaregiver
              ? 'Você deixará de acompanhar ${person.name} e de receber os '
                    'avisos de doses.'
              : '${person.name} deixará de ver suas doses e de receber avisos. '
                    'Você poderá gerar um novo código depois.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('confirm-disconnect-button'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      setState(() => _careLoading = true);
      await service.disconnect(
        widget.account,
        assistedId: _isCaregiver ? person.id : null,
      );
      if (!mounted) return;
      // O listener do vínculo atualiza a tela; aqui só garantimos o estado
      // caso o evento demore.
      if (_isCaregiver) {
        final remaining = _linkedPeople
            .where((linkedPerson) => linkedPerson.id != person.id)
            .toList();
        final selected = remaining.firstOrNull;
        setState(() {
          _linkedPeople
            ..clear()
            ..addAll(remaining);
          _linkedPerson = selected;
          _assistedId = selected?.id;
        });
        if (selected == null) {
          _clearCareData();
        } else {
          _watchCareData(selected.id);
        }
        _watchCaregiverOverdueData();
      } else if (_linkedPerson?.id == person.id) {
        setState(() => _linkedPerson = null);
      }
      _showMessage('Conexão encerrada.');
    } catch (error) {
      if (mounted) {
        _showMessage('Não foi possível desconectar: ${_errorText(error)}');
      }
    } finally {
      if (mounted) setState(() => _careLoading = false);
    }
  }

  String _errorText(Object error) {
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message;
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => 'sem permissão para esta ação. Confira o perfil da conta ou fale com o suporte.',
        'unavailable' || 'network-request-failed' =>
          'sem conexão com a internet. Confira a rede e tente novamente.',
        _ => 'ocorreu um erro. Tente novamente.',
      };
    }
    return 'ocorreu um erro. Tente novamente.';
  }

  String _formatClock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  String _doseKey(String medicationId, String time) =>
      '$_todayKey|$medicationId|$time';

  String _missedDoseKey(String? assistedId, String medicationId, String time) =>
      '$_todayKey|${assistedId ?? 'unknown'}|$medicationId|$time';

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  List<DoseRecord> get _todayRecords {
    final records = <DoseRecord>[];
    for (final medication in _medications) {
      for (final time in medication.times) {
        records.add(
          DoseRecord(
            medication: medication,
            time: time,
            status:
                _doseStatuses[_doseKey(medication.id, time)] ??
                DoseStatus.pending,
          ),
        );
      }
    }
    records.sort((a, b) => a.time.compareTo(b.time));
    return records;
  }

  Future<void> _snoozeDose(DoseRecord record) async {
    final scheduled = await NotificationService.instance.snooze(
      medication: record.medication,
      time: record.time,
    );
    if (!mounted) return;
    _showMessage(
      scheduled
          ? 'Vou lembrar de novo em 10 minutos.'
          : 'Não foi possível agendar o lembrete. Verifique as notificações.',
    );
  }

  Future<void> _updateDose(DoseRecord record, DoseStatus status) async {
    final service = widget.careService;
    if (service != null) {
      final assistedId = _assistedId;
      if (assistedId == null) {
        _showMessage('Nenhuma pessoa assistida está conectada.');
        return;
      }
      try {
        final lowStockUnits = await service.saveDoseStatus(
          assistedId: assistedId,
          dateKey: _todayKey,
          medicationId: record.medication.id,
          time: record.time,
          status: status,
        );
        unawaited(
          NotificationService.instance.cancelSnooze(
            record.medication.id,
            record.time,
          ),
        );
        if (!mounted) return;
        if (status == DoseStatus.missed) {
          setState(
            () => _addNotice(
              '${record.medication.name}: dose das ${record.time} registrada '
              'como atrasada.'
              '${_linkedPerson != null ? ' Seu cuidador foi avisado.' : ''}',
            ),
          );
        }
        final message = status == DoseStatus.taken
            ? 'Dose registrada. O cuidador poderá ver a atualização.'
            : 'Atraso registrado.';
        _showMessage(
          lowStockUnits == null
              ? message
              : '$message ${_lowStockMessage(record.medication.name, lowStockUnits)}',
        );
        if (lowStockUnits != null) {
          _notifyLowStock(record.medication.name, lowStockUnits);
        }
      } catch (error) {
        if (mounted) {
          _showMessage(
            'Não foi possível registrar a dose: ${_errorText(error)}',
          );
        }
      }
      return;
    }

    final doseKey = _doseKey(record.medication.id, record.time);
    final previousStatus = _doseStatuses[doseKey] ?? DoseStatus.pending;
    final previousStock = record.medication.stock;
    final updatedStock = stockAfterDoseStatus(
      stock: previousStock,
      previousStatus: previousStatus,
      nextStatus: status,
    );
    setState(() {
      _doseStatuses[doseKey] = status;
      record.medication.stock = updatedStock;
      if (status == DoseStatus.missed && _familySharingEnabled) {
        _addNotice(
          '${record.medication.name}: dose das ${record.time} registrada como atrasada.',
          demo: true,
        );
      }
    });
    unawaited(
      NotificationService.instance.cancelSnooze(
        record.medication.id,
        record.time,
      ),
    );
    unawaited(_syncReminders());

    final lowStockUnits = crossedLowStockThreshold(previousStock, updatedStock)
        ? updatedStock
        : null;
    if (status == DoseStatus.taken) {
      final message = 'Dose registrada. Seu histórico foi atualizado.';
      _showMessage(
        lowStockUnits == null
            ? message
            : '$message ${_lowStockMessage(record.medication.name, lowStockUnits)}',
      );
    } else if (status == DoseStatus.missed && _familySharingEnabled) {
      _showMessage(
        'Atraso registrado e aviso demonstrativo enviado à família.',
      );
    } else if (status == DoseStatus.missed) {
      _showMessage(
        'Atraso registrado. O compartilhamento com a família está desativado.',
      );
    }
    if (lowStockUnits != null) {
      _notifyLowStock(record.medication.name, lowStockUnits);
    }
  }

  void _notifyLowStock(String medicationName, int unitsRemaining) {
    unawaited(
      NotificationService.instance.showLowStockAlert(
        medicationName: medicationName,
        unitsRemaining: unitsRemaining,
      ),
    );
  }

  String _lowStockMessage(String medicationName, int unitsRemaining) =>
      'Estoque baixo: restam $unitsRemaining '
      '${unitsRemaining == 1 ? 'unidade' : 'unidades'} de $medicationName.';

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openMedicationForm({Medication? medication}) async {
    final service = widget.careService;
    final assistedId = _assistedId;
    if (service != null && assistedId == null) {
      _showMessage('Não foi possível identificar esta conta.');
      return;
    }

    var editingMedication = medication;
    final isCreatingMedication = medication == null;
    final previousStock = medication?.stock;
    String? saveError;
    while (mounted) {
      final result = await showModalBottomSheet<MedicationFormResult>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => MedicationFormSheet(
          medication: editingMedication,
          errorMessage: saveError,
          isEditing: !isCreatingMedication,
        ),
      );
      if (result == null || !mounted) return;

      final updatedMedication = Medication(
        id:
            editingMedication?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: result.name,
        dosage: result.dosage,
        instructions: result.instructions,
        times: result.times,
        stock: result.stock,
      );

      if (service != null) {
        try {
          await service.saveMedication(assistedId!, updatedMedication);
          if (!mounted) return;
        } catch (error) {
          if (!mounted) return;
          editingMedication = updatedMedication;
          saveError =
              'Não foi possível salvar. Seus dados continuam no formulário. '
              '${_errorText(error)} Tente novamente.';
          continue;
        }
      } else {
        setState(() {
          if (editingMedication == null) {
            _medications.add(updatedMedication);
          } else {
            final index = _medications.indexWhere(
              (item) => item.id == editingMedication!.id,
            );
            if (index >= 0) _medications[index] = updatedMedication;
          }
        });
        unawaited(_syncReminders());
      }

      final lowStockUnits =
          crossedLowStockThreshold(previousStock, result.stock)
          ? result.stock
          : null;
      final message = isCreatingMedication
          ? 'Medicamento adicionado à rotina.'
          : 'Medicamento atualizado.';
      _showMessage(
        lowStockUnits == null
            ? message
            : '$message ${_lowStockMessage(updatedMedication.name, lowStockUnits)}',
      );
      if (lowStockUnits != null) {
        _notifyLowStock(updatedMedication.name, lowStockUnits);
      }
      return;
    }
  }

  Future<void> _openFamilyForm() async {
    final result = await showModalBottomSheet<FamilyFormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FamilyFormSheet(
        name: _familyName,
        relationship: _familyRelationship,
        phone: _familyPhone,
      ),
    );
    if (result == null) return;
    setState(() {
      _familyName = result.name;
      _familyRelationship = result.relationship;
      _familyPhone = result.phone;
      _familySharingEnabled = true;
    });
    _showMessage('Familiar vinculado neste protótipo.');
  }

  void _selectTab(int index) {
    setState(() => _selectedTab = index);
  }

  void _setHistoryPeriod(String period) {
    setState(() => _historyPeriod = period);
  }

  void _setFamilySharingEnabled(bool enabled) {
    setState(() => _familySharingEnabled = enabled);
  }

  Future<void> _removeMedication(Medication medication) async {
    final service = widget.careService;
    if (service != null) {
      final assistedId = _assistedId;
      if (assistedId == null) {
        _showMessage('Não foi possível identificar esta conta.');
        return;
      }
      try {
        await service.deleteMedication(assistedId, medication.id);
      } catch (error) {
        if (mounted) {
          _showMessage(
            'Não foi possível remover o medicamento: ${_errorText(error)}',
          );
        }
        return;
      }
      _showMessage('Medicamento removido da rotina.');
      return;
    }
    setState(() => _medications.remove(medication));
    unawaited(_syncReminders());
    _showMessage('Medicamento removido da rotina.');
  }

  @override
  Widget build(BuildContext context) {
    final isCaregiver = _isCaregiver;
    final destinations = isCaregiver
        ? <({IconData icon, IconData selectedIcon, String label})>[
            (
              icon: Icons.monitor_heart_outlined,
              selectedIcon: Icons.monitor_heart,
              label: 'Acompanhar',
            ),
            (
              icon: Icons.medication_outlined,
              selectedIcon: Icons.medication,
              label: 'Medicamentos',
            ),
            (
              icon: Icons.history,
              selectedIcon: Icons.history,
              label: 'Histórico',
            ),
            (
              icon: Icons.person_outline,
              selectedIcon: Icons.person,
              label: 'Conta',
            ),
          ]
        : <({IconData icon, IconData selectedIcon, String label})>[
            (
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: 'Início',
            ),
            (
              icon: Icons.medication_outlined,
              selectedIcon: Icons.medication,
              label: 'Remédios',
            ),
            (
              icon: Icons.history,
              selectedIcon: Icons.history,
              label: 'Histórico',
            ),
            (
              icon: Icons.family_restroom_outlined,
              selectedIcon: Icons.family_restroom,
              label: 'Família',
            ),
          ];
    final pages = [
      _buildHomePage(),
      _buildMedicationsPage(),
      _buildHistoryPage(),
      _buildFamilyPage(),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _selectedTab, children: pages),
      ),
      bottomNavigationBar: widget.largeText
          ? _buildLargeTextNavigationBar(destinations)
          : NavigationBar(
              selectedIndex: _selectedTab,
              onDestinationSelected: _selectTab,
              height: 84,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final destination in destinations)
                  NavigationDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: destination.label,
                  ),
              ],
            ),
    );
  }

  Widget _buildLargeTextNavigationBar(
    List<({IconData icon, IconData selectedIcon, String label})> destinations,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final tileWidth = (width - 48) / 2;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < destinations.length; index++)
              SizedBox(
                width: tileWidth,
                child: Material(
                  color: index == _selectedTab
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _selectTab(index),
                    child: Semantics(
                      button: true,
                      selected: index == _selectedTab,
                      label: destinations[index].label,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              index == _selectedTab
                                  ? destinations[index].selectedIcon
                                  : destinations[index].icon,
                              color: colorScheme.onSurface,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                destinations[index].label,
                                maxLines: 2,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
