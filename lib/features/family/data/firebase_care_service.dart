import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/auth/models/user_account.dart';
import '../../../models/medication.dart';

class LinkedPerson {
  const LinkedPerson({
    required this.id,
    required this.name,
    required this.email,
  });

  final String id;
  final String name;
  final String email;
}

/// Token de conexão gerado pela pessoa assistida.
class CareLinkToken {
  const CareLinkToken({required this.code, required this.expiresAt});

  /// 12 caracteres, sem hífens (ex.: `ABCD2345EFGH`).
  final String code;
  final DateTime expiresAt;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());

  /// Formato de exibição: `ABCD-2345-EFGH`.
  String get formatted =>
      '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8)}';
}

abstract interface class CareService {
  static const maxCaregiverPatients = 4;

  /// Gera um token novo. Qualquer token anterior ainda não usado é invalidado.
  Future<CareLinkToken> createOneTimeToken(UserAccount assisted);

  /// Token ainda válido (não usado e não expirado) desta pessoa, se houver.
  Future<CareLinkToken?> getActiveToken(UserAccount assisted);

  /// Cancela um token que ainda não foi usado.
  Future<void> revokeToken(UserAccount assisted, String code);

  Future<LinkedPerson?> getConnectedPerson(UserAccount account);

  Future<List<LinkedPerson>> getConnectedPeople(UserAccount caregiver);

  /// Acompanha o vínculo em tempo real (conectou / desconectou).
  Stream<LinkedPerson?> watchConnectedPerson(UserAccount account);

  Stream<List<LinkedPerson>> watchConnectedPeople(UserAccount caregiver);

  Future<LinkedPerson> connectCaregiverWithToken(
    UserAccount caregiver,
    String token,
  );

  /// Desfaz o vínculo. Pode ser chamado pelo cuidador ou pela pessoa assistida.
  Future<void> disconnect(UserAccount account, {String? assistedId});

  Stream<List<Medication>> watchMedications(String assistedId);

  Stream<Map<String, DoseStatus>> watchDoseStatuses({
    required String assistedId,
    required String dateKey,
  });

  Future<void> saveMedication(String assistedId, Medication medication);

  Future<void> deleteMedication(String assistedId, String medicationId);

  /// Returns the remaining stock when the dose crosses the low-stock
  /// threshold; otherwise returns null.
  Future<int?> saveDoseStatus({
    required String assistedId,
    required String dateKey,
    required String medicationId,
    required String time,
    required DoseStatus status,
  });
}

class FirebaseCareService implements CareService {
  FirebaseCareService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const _tokenAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _tokenLength = 12;
  static const _tokenLifetime = Duration(minutes: 15);
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _tokens =>
      _firestore.collection('careLinkTokens');

  // ---------------------------------------------------------------------------
  // Tokens
  // ---------------------------------------------------------------------------

  @override
  Future<CareLinkToken> createOneTimeToken(UserAccount assisted) async {
    final assistedId = assisted.id;
    if (assistedId == null || assisted.role != AccountRole.caredFor) {
      throw StateError(
        'Somente a conta da pessoa assistida pode gerar o código.',
      );
    }

    final assistedRef = _users.doc(assistedId);
    final profile = await assistedRef.get();
    if (profile.data()?['role'] != AccountRole.caredFor.name) {
      throw StateError('O perfil da pessoa assistida não foi encontrado.');
    }
    if (profile.data()?['linkedCaregiverId'] != null) {
      throw StateError('Esta conta já está conectada a um cuidador.');
    }

    // Só um token válido por vez: apaga os anteriores que não foram usados.
    final previous = await _unusedTokensOf(assistedId);

    final code = _generateToken();
    final expiresAt = DateTime.now().add(_tokenLifetime);
    final batch = _firestore.batch();
    for (final document in previous) {
      batch.delete(document.reference);
    }
    batch.set(_tokens.doc(code), {
      'assistedId': assistedId,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'usedBy': null,
    });
    await batch.commit();
    return CareLinkToken(code: code, expiresAt: expiresAt);
  }

  @override
  Future<CareLinkToken?> getActiveToken(UserAccount assisted) async {
    final assistedId = assisted.id;
    if (assistedId == null || assisted.role != AccountRole.caredFor) {
      return null;
    }
    final documents = await _unusedTokensOf(assistedId);
    CareLinkToken? best;
    for (final document in documents) {
      final expiresAt = document.data()['expiresAt'];
      if (expiresAt is! Timestamp) continue;
      final token = CareLinkToken(
        code: document.id,
        expiresAt: expiresAt.toDate(),
      );
      if (token.isExpired) continue;
      if (best == null || token.expiresAt.isAfter(best.expiresAt)) {
        best = token;
      }
    }
    return best;
  }

  @override
  Future<void> revokeToken(UserAccount assisted, String code) async {
    final assistedId = assisted.id;
    if (assistedId == null) return;
    final reference = _tokens.doc(_normalizeToken(code));
    final snapshot = await reference.get();
    final data = snapshot.data();
    if (data == null) return;
    if (data['assistedId'] != assistedId) {
      throw StateError('Este código não pertence a esta conta.');
    }
    if (data['usedBy'] != null) {
      throw StateError('Este código já foi usado.');
    }
    await reference.delete();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _unusedTokensOf(
    String assistedId,
  ) async {
    final result = await _tokens
        .where('assistedId', isEqualTo: assistedId)
        .where('usedBy', isNull: true)
        .get();
    return result.docs;
  }

  // ---------------------------------------------------------------------------
  // Vínculo
  // ---------------------------------------------------------------------------

  @override
  Future<LinkedPerson?> getConnectedPerson(UserAccount account) async {
    final accountId = account.id;
    if (accountId == null) {
      throw StateError('Esta conta não possui um identificador do Firebase.');
    }
    final profile = await _users.doc(accountId).get();
    final profileData = profile.data();
    if (profileData == null) {
      throw StateError('O perfil desta conta não foi encontrado.');
    }
    return _personFromProfile(account, profileData);
  }

  @override
  Future<List<LinkedPerson>> getConnectedPeople(UserAccount caregiver) async {
    final caregiverId = caregiver.id;
    if (caregiverId == null || caregiver.role != AccountRole.caregiver) {
      throw StateError('Somente uma conta de cuidador pode listar pessoas.');
    }
    final profile = await _users.doc(caregiverId).get();
    final profileData = profile.data();
    if (profileData == null) {
      throw StateError('O perfil desta conta não foi encontrado.');
    }
    final ids = _linkedPatientIds(profileData);
    final people = <LinkedPerson>[];
    for (final id in ids) {
      final person = await _users.doc(id).get();
      final data = person.data();
      if (data == null) continue;
      people.add(
        LinkedPerson(
          id: person.id,
          name: data['name'] as String,
          email: data['email'] as String,
        ),
      );
    }
    return people;
  }

  @override
  Stream<LinkedPerson?> watchConnectedPerson(UserAccount account) {
    final accountId = account.id;
    if (accountId == null) {
      return Stream<LinkedPerson?>.error(
        StateError('Esta conta não possui um identificador do Firebase.'),
      );
    }
    return _users.doc(accountId).snapshots().asyncMap((snapshot) async {
      final data = snapshot.data();
      if (data == null) return null;
      try {
        return await _personFromProfile(account, data);
      } on FirebaseException {
        // Logo após desconectar a leitura do perfil do outro lado pode ser
        // negada. Nesse caso o vínculo já não existe.
        return null;
      }
    });
  }

  @override
  Stream<List<LinkedPerson>> watchConnectedPeople(UserAccount caregiver) {
    final caregiverId = caregiver.id;
    if (caregiverId == null || caregiver.role != AccountRole.caregiver) {
      return Stream<List<LinkedPerson>>.error(
        StateError('Somente uma conta de cuidador pode listar pessoas.'),
      );
    }
    return _users.doc(caregiverId).snapshots().asyncMap((snapshot) async {
      final data = snapshot.data();
      if (data == null) return <LinkedPerson>[];
      return getConnectedPeople(caregiver);
    });
  }

  Future<LinkedPerson?> _personFromProfile(
    UserAccount account,
    Map<String, dynamic> profileData,
  ) async {
    final personId = account.role == AccountRole.caregiver
        ? profileData['linkedPatientId']
        : profileData['linkedCaregiverId'];
    if (personId is! String || personId.isEmpty) return null;

    final person = await _users.doc(personId).get();
    final personData = person.data();
    if (personData == null) return null;
    return LinkedPerson(
      id: person.id,
      name: personData['name'] as String,
      email: personData['email'] as String,
    );
  }

  @override
  Future<LinkedPerson> connectCaregiverWithToken(
    UserAccount caregiver,
    String token,
  ) async {
    final caregiverId = caregiver.id;
    final normalizedToken = _normalizeToken(token);
    if (caregiverId == null || caregiver.role != AccountRole.caregiver) {
      throw StateError('Somente uma conta de cuidador pode conectar alguém.');
    }
    if (normalizedToken.length != _tokenLength ||
        normalizedToken
            .split('')
            .any((character) => !_tokenAlphabet.contains(character))) {
      throw const FormatException('Confira o código e tente novamente.');
    }

    final tokenRef = _tokens.doc(normalizedToken);
    final caregiverRef = _users.doc(caregiverId);
    late String connectedAssistedId;
    await _firestore.runTransaction<void>((transaction) async {
      final tokenSnapshot = await transaction.get(tokenRef);
      if (!tokenSnapshot.exists) {
        throw const FormatException('Código inválido ou expirado.');
      }
      final tokenData = tokenSnapshot.data()!;
      final assistedId = tokenData['assistedId'];
      final expiresAt = tokenData['expiresAt'];
      if (tokenData['usedBy'] != null ||
          assistedId is! String ||
          expiresAt is! Timestamp ||
          !expiresAt.toDate().isAfter(DateTime.now())) {
        throw const FormatException(
          'Código inválido, expirado ou já utilizado.',
        );
      }
      if (assistedId == caregiverId) {
        throw const FormatException(
          'Este código pertence à sua própria conta.',
        );
      }
      connectedAssistedId = assistedId;

      final caregiverSnapshot = await transaction.get(caregiverRef);
      final caregiverData = caregiverSnapshot.data();
      if (caregiverData == null ||
          caregiverData['role'] != AccountRole.caregiver.name) {
        throw StateError('O perfil desta conta não é de cuidador.');
      }
      final linkedIds = _linkedPatientIds(caregiverData);
      if (linkedIds.contains(assistedId)) {
        throw StateError('Esta pessoa já está conectada à sua conta.');
      }
      if (linkedIds.length >= CareService.maxCaregiverPatients) {
        throw StateError(
          'Um cuidador pode acompanhar até '
          '${CareService.maxCaregiverPatients} pessoas.',
        );
      }

      transaction.update(tokenRef, {
        'usedBy': caregiverId,
        'usedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(caregiverRef, {
        'linkedPatientIds': [...linkedIds, assistedId],
        'linkedPatientId': linkedIds.isEmpty ? assistedId : linkedIds.first,
        'linkedAt': FieldValue.serverTimestamp(),
        'linkTokenId': normalizedToken,
      });
      transaction.update(_users.doc(assistedId), {
        'linkedCaregiverId': caregiverId,
        'linkedAt': FieldValue.serverTimestamp(),
        'linkTokenId': normalizedToken,
      });
    });
    final person = (await getConnectedPeople(caregiver))
        .where((connectedPerson) => connectedPerson.id == connectedAssistedId)
        .firstOrNull;
    if (person == null) {
      throw StateError(
        'O vínculo foi criado, mas não foi possível ler o perfil.',
      );
    }
    return person;
  }

  @override
  Future<void> disconnect(UserAccount account, {String? assistedId}) async {
    final accountId = account.id;
    if (accountId == null) {
      throw StateError('Esta conta não possui um identificador do Firebase.');
    }
    final isCaregiver = account.role == AccountRole.caregiver;
    final ownRef = _users.doc(accountId);
    final profile = await ownRef.get();
    final profileData = profile.data();
    final otherId = isCaregiver
        ? assistedId ?? _linkedPatientIds(profileData ?? {}).firstOrNull
        : profileData?['linkedCaregiverId'];
    if (otherId is! String || otherId.isEmpty) return;
    if (isCaregiver &&
        !_linkedPatientIds(profileData ?? {}).contains(otherId)) {
      throw StateError('Esta pessoa não está conectada à sua conta.');
    }
    final otherProfile = isCaregiver ? null : await _users.doc(otherId).get();
    final otherProfileData = otherProfile?.data();
    final caregiverPatients = isCaregiver
        ? const <String>[]
        : _linkedPatientIds(otherProfileData ?? {});
    if (!isCaregiver && !caregiverPatients.contains(accountId)) {
      throw StateError('Esta conexão não está mais ativa.');
    }

    final batch = _firestore.batch();
    if (isCaregiver) {
      final remainingIds = _linkedPatientIds(profileData ?? {})
          .where((id) => id != otherId)
          .toList();
      batch.update(ownRef, {
        'linkedPatientIds': remainingIds,
        'linkedPatientId': remainingIds.firstOrNull,
        if (remainingIds.isEmpty) 'linkedAt': FieldValue.delete(),
        if (remainingIds.isNotEmpty) 'linkedAt': FieldValue.serverTimestamp(),
        'linkTokenId': FieldValue.delete(),
      });
      batch.update(_users.doc(otherId), {
        'linkedCaregiverId': null,
        'linkedAt': FieldValue.delete(),
        'linkTokenId': FieldValue.delete(),
      });
    } else {
      batch.update(ownRef, {
        'linkedCaregiverId': null,
        'linkedAt': FieldValue.delete(),
        'linkTokenId': FieldValue.delete(),
      });
      final remainingIds = caregiverPatients
          .where((id) => id != accountId)
          .toList();
      batch.update(_users.doc(otherId), {
        'linkedPatientIds': remainingIds,
        'linkedPatientId': remainingIds.firstOrNull,
        if (remainingIds.isEmpty) 'linkedAt': FieldValue.delete(),
        if (remainingIds.isNotEmpty) 'linkedAt': FieldValue.serverTimestamp(),
        'linkTokenId': FieldValue.delete(),
      });
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Medicamentos e doses
  // ---------------------------------------------------------------------------

  @override
  Stream<List<Medication>> watchMedications(String assistedId) => _users
      .doc(assistedId)
      .collection('medications')
      .snapshots()
      .map((snapshot) {
        final medications =
            snapshot.docs
                .map((document) => _medicationFromDocument(document))
                .toList()
              ..sort((first, second) => first.name.compareTo(second.name));
        return medications;
      });

  @override
  Stream<Map<String, DoseStatus>> watchDoseStatuses({
    required String assistedId,
    required String dateKey,
  }) => _users
      .doc(assistedId)
      .collection('doseStatuses')
      .where('dateKey', isEqualTo: dateKey)
      .snapshots()
      .map((snapshot) {
        return {
          for (final document in snapshot.docs)
            '${document.data()['medicationId']}|${document.data()['time']}':
                DoseStatus.values.byName(document.data()['status'] as String),
        };
      });

  @override
  Future<void> saveMedication(String assistedId, Medication medication) =>
      _users.doc(assistedId).collection('medications').doc(medication.id).set({
        'name': medication.name,
        'dosage': medication.dosage,
        'instructions': medication.instructions,
        'times': medication.times,
        'stock': medication.stock,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteMedication(String assistedId, String medicationId) =>
      _users
          .doc(assistedId)
          .collection('medications')
          .doc(medicationId)
          .delete();

  @override
  Future<int?> saveDoseStatus({
    required String assistedId,
    required String dateKey,
    required String medicationId,
    required String time,
    required DoseStatus status,
  }) {
    final userRef = _users.doc(assistedId);
    final doseRef = userRef
        .collection('doseStatuses')
        .doc(_doseDocumentId(dateKey, medicationId, time));
    final medicationRef = userRef.collection('medications').doc(medicationId);

    return _firestore.runTransaction<int?>((transaction) async {
      final doseSnapshot = await transaction.get(doseRef);
      final medicationSnapshot = await transaction.get(medicationRef);
      final previousStatus = doseSnapshot.exists
          ? DoseStatus.values.byName(doseSnapshot.data()!['status'] as String)
          : DoseStatus.pending;
      final medicationData = medicationSnapshot.data();
      final previousStock = medicationData?['stock'] as int?;
      final updatedStock = stockAfterDoseStatus(
        stock: previousStock,
        previousStatus: previousStatus,
        nextStatus: status,
      );

      transaction.set(doseRef, {
        'dateKey': dateKey,
        'medicationId': medicationId,
        'time': time,
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (medicationSnapshot.exists && updatedStock != previousStock) {
        transaction.update(medicationRef, {
          'stock': updatedStock,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      return crossedLowStockThreshold(previousStock, updatedStock)
          ? updatedStock
          : null;
    });
  }

  Medication _medicationFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return Medication(
      id: document.id,
      name: data['name'] as String,
      dosage: data['dosage'] as String,
      instructions: data['instructions'] as String,
      times: List<String>.from(data['times'] as List),
      stock: data['stock'] as int?,
    );
  }

  String _generateToken() {
    final random = Random.secure();
    return List.generate(
      _tokenLength,
      (_) => _tokenAlphabet[random.nextInt(_tokenAlphabet.length)],
    ).join();
  }

  String _normalizeToken(String token) =>
      token.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  List<String> _linkedPatientIds(Map<String, dynamic> profile) {
    final linkedIds = profile['linkedPatientIds'];
    if (linkedIds is List) {
      return linkedIds.whereType<String>().toList();
    }
    final legacyId = profile['linkedPatientId'];
    return legacyId is String && legacyId.isNotEmpty ? [legacyId] : [];
  }

  String _doseDocumentId(String dateKey, String medicationId, String time) =>
      '${dateKey}_$medicationId-${time.replaceAll(':', '')}';
}
