import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/medication.dart';
import 'overdue_dose_schedule.dart';

/// Aviso exibido na lista "Avisos" do app.
class AppNotice {
  const AppNotice({
    required this.message,
    required this.createdAt,
    this.demo = false,
  });

  final String message;
  final DateTime createdAt;
  final bool demo;
}

class CaregiverDoseReminder {
  const CaregiverDoseReminder({
    required this.assistedId,
    required this.assistedName,
    required this.medicationId,
    required this.medicationName,
    required this.time,
    required this.resolvedToday,
  });

  final String assistedId;
  final String assistedName;
  final String medicationId;
  final String medicationName;
  final String time;
  final bool resolvedToday;
}

/// Centraliza TUDO que é notificação:
///  * lembretes locais agendados de cada dose (pessoa assistida);
///  * avisos imediatos (conexão, dose confirmada/atrasada);
///  * token FCM do aparelho, usado por um backend de push quando configurado.
///
/// Todos os métodos públicos engolem erros (só fazem `debugPrint`), para que
/// uma falha de notificação nunca derrube o app.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const reminderChannelId = 'dose_reminders_v2';
  static const alertChannelId = 'caregiver_alerts_v2';
  static const stockChannelId = 'low_stock_alerts';

  /// Fuso usado para agendar os lembretes (horário de Brasília).
  /// O Brasil não tem mais horário de verão, então não há ajuste de DST.
  static const _timeZoneName = 'America/Sao_Paulo';

  static const _reminderPayloadPrefix = 'dose|';
  static const _snoozePayloadPrefix = 'snooze|';
  static const _caregiverOverduePayloadPrefix = 'overdue|';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<AppNotice> _remoteNotices =
      StreamController<AppNotice>.broadcast();

  Future<void>? _initFuture;
  bool _ready = false;
  Future<void> _syncQueue = Future<void>.value();
  Future<void> _overdueSyncQueue = Future<void>.value();
  int _nextAlertId = 0x40000000;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  String? _pushUserId;
  String? _pushToken;

  /// Avisos recebidos por push enquanto o app está aberto.
  Stream<AppNotice> get remoteNotices => _remoteNotices.stream;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  // ---------------------------------------------------------------------------
  // Inicialização e permissões
  // ---------------------------------------------------------------------------

  Future<void> initialize() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(_timeZoneName));

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final android = _android;
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          reminderChannelId,
          'Lembretes de medicação',
          description: 'Avisa a hora de tomar cada medicamento.',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          alertChannelId,
          'Avisos ao cuidador',
          description: 'Doses confirmadas, atrasadas e conexões da conta.',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          stockChannelId,
          'Avisos de estoque',
          description: 'Avisa quando restam poucas unidades do medicamento.',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      _ready = true;
    } catch (error, stackTrace) {
      debugPrint('Falha ao iniciar notificações: $error\n$stackTrace');
    }
  }

  /// Pede a permissão de notificações (Android 13+). Retorna `true` se ativa.
  Future<bool> requestPermissions() async {
    await initialize();
    if (!_ready) return false;
    try {
      final granted = await _android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (error) {
      debugPrint('Falha ao pedir permissão de notificações: $error');
      return false;
    }
  }

  Future<bool> areNotificationsEnabled() async {
    await initialize();
    if (!_ready) return false;
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// No Android 12+ o alarme exato depende de uma permissão especial.
  Future<bool> canScheduleExactAlarms() async {
    await initialize();
    if (!_ready) return false;
    try {
      return await _android?.canScheduleExactNotifications() ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Abre a tela do sistema onde o usuário libera "Alarmes e lembretes".
  Future<void> openExactAlarmSettings() async {
    await initialize();
    if (!_ready) return;
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (error) {
      debugPrint('Falha ao abrir configuração de alarmes: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Lembretes de dose (pessoa assistida)
  // ---------------------------------------------------------------------------

  NotificationDetails get _reminderDetails => const NotificationDetails(
    android: AndroidNotificationDetails(
      reminderChannelId,
      'Lembretes de medicação',
      channelDescription: 'Avisa a hora de tomar cada medicamento.',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      playSound: true,
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    ),
  );

  NotificationDetails get _alertDetails => const NotificationDetails(
    android: AndroidNotificationDetails(
      alertChannelId,
      'Avisos ao cuidador',
      channelDescription: 'Doses confirmadas, atrasadas e conexões da conta.',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      onlyAlertOnce: true,
    ),
  );

  NotificationDetails get _stockDetails => const NotificationDetails(
    android: AndroidNotificationDetails(
      stockChannelId,
      'Avisos de estoque',
      channelDescription: 'Avisa quando restam poucas unidades do medicamento.',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// Reagenda todos os lembretes de dose.
  ///
  /// Cada horário vira um lembrete diário. Se a dose de hoje já foi tomada,
  /// o primeiro disparo passa para amanhã. Chame sempre que a lista de
  /// medicamentos ou o status das doses mudar.
  Future<void> syncDoseReminders({
    required Iterable<Medication> medications,
    required bool Function(String medicationId, String time) takenToday,
  }) {
    // Tira uma "foto" agora: a fila pode rodar depois que o estado mudou.
    final entries = <_ReminderEntry>[
      for (final medication in medications)
        for (final time in medication.times)
          _ReminderEntry(
            medicationId: medication.id,
            name: medication.name,
            dosage: medication.dosage,
            time: time,
            takenToday: takenToday(medication.id, time),
          ),
    ];
    _syncQueue = _syncQueue.then((_) => _syncNow(entries));
    return _syncQueue;
  }

  Future<void> _syncNow(List<_ReminderEntry> entries) async {
    await initialize();
    if (!_ready) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.payload?.startsWith(_reminderPayloadPrefix) ?? false) {
          await _plugin.cancel(id: request.id);
        }
      }

      final mode = await canScheduleExactAlarms()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final now = tz.TZDateTime.now(tz.local);

      for (final entry in entries) {
        final parsed = _parseTime(entry.time);
        if (parsed == null) continue;

        var first = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          parsed.$1,
          parsed.$2,
        );
        if (entry.takenToday || !first.isAfter(now)) {
          first = first.add(const Duration(days: 1));
        }

        await _plugin.zonedSchedule(
          id: _stableId('${entry.medicationId}|${entry.time}'),
          title: 'Hora do remédio',
          body: '${entry.name} • ${entry.dosage} (${entry.time})',
          scheduledDate: first,
          notificationDetails: _reminderDetails,
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: '$_reminderPayloadPrefix${entry.medicationId}|${entry.time}',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Falha ao agendar lembretes: $error\n$stackTrace');
    }
  }

  /// Lembra de novo daqui a [delay] (botão "Lembrar em 10 minutos").
  Future<bool> snooze({
    required Medication medication,
    required String time,
    Duration delay = const Duration(minutes: 10),
  }) async {
    await initialize();
    if (!_ready) return false;
    try {
      final mode = await canScheduleExactAlarms()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      await _plugin.zonedSchedule(
        id: _stableId('snooze|${medication.id}|$time'),
        title: 'Hora do remédio',
        body: '${medication.name} • ${medication.dosage} (era às $time)',
        scheduledDate: tz.TZDateTime.now(tz.local).add(delay),
        notificationDetails: _reminderDetails,
        androidScheduleMode: mode,
        payload: '$_snoozePayloadPrefix${medication.id}|$time',
      );
      return true;
    } catch (error) {
      debugPrint('Falha ao adiar lembrete: $error');
      return false;
    }
  }

  /// Cancela o adiamento pendente de uma dose (ex.: quando ela foi tomada).
  Future<void> cancelSnooze(String medicationId, String time) async {
    await initialize();
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _stableId('snooze|$medicationId|$time'));
    } catch (error) {
      debugPrint('Falha ao cancelar adiamento: $error');
    }
  }

  /// Remove todos os lembretes (usado ao sair da conta).
  Future<void> cancelAllReminders() async {
    await initialize();
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (error) {
      debugPrint('Falha ao cancelar lembretes: $error');
    }
  }

  /// Agenda avisos no aparelho do cuidador para doses sem confirmação.
  ///
  /// A agenda repete diariamente; os status sincronizados cancelam o aviso
  /// daquele dia e o próximo snapshot agenda novamente a próxima dose.
  Future<void> syncCaregiverOverdueAlerts({
    required Iterable<CaregiverDoseReminder> reminders,
  }) {
    final entries = List<CaregiverDoseReminder>.of(reminders);
    _overdueSyncQueue = _overdueSyncQueue.then(
      (_) => _syncCaregiverOverdueAlerts(entries),
    );
    return _overdueSyncQueue;
  }

  Future<void> _syncCaregiverOverdueAlerts(
    List<CaregiverDoseReminder> reminders,
  ) async {
    await initialize();
    if (!_ready) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (request.payload?.startsWith(_caregiverOverduePayloadPrefix) ??
            false) {
          await _plugin.cancel(id: request.id);
        }
      }

      final mode = await canScheduleExactAlarms()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final now = tz.TZDateTime.now(tz.local);
      final preferences = await SharedPreferences.getInstance();
      for (final reminder in reminders) {
        if (reminder.resolvedToday) continue;
        final handledKey =
            'caregiver_overdue_handled_'
            '${reminder.assistedId}_${reminder.medicationId}_${reminder.time}';
        final schedule = OverdueDoseSchedule.calculate(
          now: now,
          time: reminder.time,
          gracePeriod: caregiverOverdueGracePeriod,
          lastHandledDateKey: preferences.getString(handledKey),
        );
        if (schedule == null) {
          debugPrint(
            'Horário inválido para aviso de dose atrasada: '
            '${reminder.time}',
          );
          continue;
        }
        final payload =
            '$_caregiverOverduePayloadPrefix'
            '${reminder.assistedId}|${reminder.medicationId}|${reminder.time}';
        if (schedule.shouldNotifyImmediately) {
          await _plugin.show(
            id: _stableId(payload),
            title: 'Medicamento atrasado',
            body:
                '${reminder.medicationName} de ${reminder.assistedName} está '
                'atrasado. A dose das ${reminder.time} ainda não foi confirmada.',
            notificationDetails: _alertDetails,
            payload: payload,
          );
        }

        await _plugin.zonedSchedule(
          id: _stableId(payload),
          title: 'Medicamento atrasado',
          body:
              '${reminder.medicationName} de ${reminder.assistedName} está '
              'atrasado. A dose das ${reminder.time} ainda não foi confirmada.',
          scheduledDate: schedule.scheduledDate,
          notificationDetails: _alertDetails,
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
        await preferences.setString(handledKey, schedule.handledDateKey);
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Falha ao agendar avisos de doses não confirmadas: '
        '$error\n$stackTrace',
      );
    }
  }

  Future<bool> showCaregiverOverdueAlert(CaregiverDoseReminder reminder) async {
    await initialize();
    if (!_ready) return false;
    final payload =
        '$_caregiverOverduePayloadPrefix'
        '${reminder.assistedId}|${reminder.medicationId}|${reminder.time}';
    try {
      await _plugin.show(
        id: _stableId(payload),
        title: 'Medicamento atrasado',
        body:
            '${reminder.medicationName} de ${reminder.assistedName} está '
            'atrasado. A dose das ${reminder.time} ainda não foi confirmada.',
        notificationDetails: _alertDetails,
        payload: payload,
      );
      return true;
    } catch (error) {
      debugPrint('Falha ao mostrar aviso de dose atrasada: $error');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Avisos imediatos
  // ---------------------------------------------------------------------------

  /// Mostra uma notificação agora (cuidador: dose atrasada, conexão etc.).
  Future<void> showAlert({required String title, required String body}) async {
    await initialize();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextAlertId++,
        title: title,
        body: body,
        notificationDetails: _alertDetails,
      );
    } catch (error) {
      debugPrint('Falha ao mostrar notificação: $error');
    }
  }

  Future<void> showLowStockAlert({
    required String medicationName,
    required int unitsRemaining,
  }) async {
    await initialize();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextAlertId++,
        title: 'Estoque baixo',
        body:
            'Restam $unitsRemaining '
            '${unitsRemaining == 1 ? 'unidade' : 'unidades'} de '
            '$medicationName.',
        notificationDetails: _stockDetails,
      );
    } catch (error) {
      debugPrint('Falha ao mostrar aviso de estoque: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Push (Firebase Cloud Messaging)
  // ---------------------------------------------------------------------------

  /// Salva o token FCM deste aparelho em `users/{uid}/fcmTokens/{token}` para
  /// que a Cloud Function consiga avisar este usuário com o app fechado.
  Future<void> registerPushToken(String userId) async {
    await initialize();
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();

      _pushUserId = userId;
      // The backend uses FCM registration tokens; register() emits an
      // installation ID and requires a corresponding backend migration.
      // ignore: deprecated_member_use
      final token = await messaging.getToken();
      if (token != null) await _saveToken(userId, token);

      await _tokenRefreshSubscription?.cancel();
      // ignore: deprecated_member_use
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen((
        newToken,
      ) async {
        final previous = _pushToken;
        await _saveToken(userId, newToken);
        if (previous != null && previous != newToken) {
          await _deleteToken(userId, previous);
        }
      }, onError: (Object error) => debugPrint('Erro no token FCM: $error'));

      await _foregroundSubscription?.cancel();
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
    } catch (error, stackTrace) {
      debugPrint('Falha ao registrar push: $error\n$stackTrace');
    }
  }

  /// Remove o token deste aparelho do usuário atual. Chame ANTES do signOut
  /// (as regras do Firestore exigem o usuário autenticado).
  Future<void> unregisterPushToken() async {
    final userId = _pushUserId;
    final token = _pushToken;
    _pushUserId = null;
    _pushToken = null;
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundSubscription = null;
    try {
      if (userId != null && token != null) {
        await _deleteToken(userId, token);
      }
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      debugPrint('Falha ao remover token FCM: $error');
    }
  }

  Future<void> _saveToken(String userId, String token) async {
    _pushToken = token;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('fcmTokens')
        .doc(token)
        .set({
          'token': token,
          'platform': defaultTargetPlatform.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _deleteToken(String userId, String token) => FirebaseFirestore
      .instance
      .collection('users')
      .doc(userId)
      .collection('fcmTokens')
      .doc(token)
      .delete();

  /// Com o app aberto o Android não mostra push sozinho. Mostramos só o aviso
  /// de dose atrasada: confirmações/atrasos registrados já são tratados pelo
  /// listener do Firestore na tela, e mostrar os dois duplicaria o aviso.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final type = message.data['type'];
    final title = message.notification?.title ?? 'Aviso';
    final body = message.notification?.body ?? '';
    if (type == 'dose_overdue') {
      _remoteNotices.add(AppNotice(message: body, createdAt: DateTime.now()));
      await showAlert(title: title, body: body);
    }
  }

  // ---------------------------------------------------------------------------
  // Utilitários
  // ---------------------------------------------------------------------------

  /// "08:30" -> (8, 30). Retorna null se o texto for inválido.
  (int, int)? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  /// FNV-1a de 31 bits: id estável entre execuções (String.hashCode não é).
  int _stableId(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x3FFFFFFF;
  }
}

class _ReminderEntry {
  const _ReminderEntry({
    required this.medicationId,
    required this.name,
    required this.dosage,
    required this.time,
    required this.takenToday,
  });

  final String medicationId;
  final String name;
  final String dosage;
  final String time;
  final bool takenToday;
}
