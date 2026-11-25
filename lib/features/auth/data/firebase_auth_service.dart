import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_account.dart';
import 'local_auth_service.dart';

class FirebaseAuthService implements AuthenticationService {
  FirebaseAuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  Future<UserAccount?> restoreSession() async {
    final user = await _auth.authStateChanges().first;
    if (user == null) return null;

    final profile = (await _userDocument(user.uid).get()).data();
    if (profile == null) {
      throw const LocalAuthException(
        'O perfil desta conta não foi encontrado. Entre em contato com o suporte.',
      );
    }

    final roleName = profile['role'];
    if (roleName is! String) {
      throw const LocalAuthException(
        'O perfil desta conta está inválido. Entre em contato com o suporte.',
      );
    }
    final role = AccountRole.values
        .where((candidate) => candidate.name == roleName)
        .firstOrNull;
    if (role == null) {
      throw const LocalAuthException(
        'O perfil desta conta está inválido. Entre em contato com o suporte.',
      );
    }

    return UserAccount(
      id: user.uid,
      name: profile['name'] as String,
      email: profile['email'] as String,
      role: role,
      passwordSalt: '',
      passwordHash: '',
    );
  }

  @override
  Future<UserAccount> register({
    required String name,
    required String email,
    required String password,
    required AccountRole role,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const LocalAuthException('Não foi possível criar a conta.');
      }

      final profile = UserAccount(
        id: user.uid,
        name: name.trim(),
        email: user.email ?? email.trim().toLowerCase(),
        role: role,
        passwordSalt: '',
        passwordHash: '',
      );

      try {
        await user.updateDisplayName(profile.name);
        await _userDocument(user.uid).set({
          'name': profile.name,
          'email': profile.email,
          'role': role.name,
          'linkedPatientId': null,
          'linkedPatientIds': <String>[],
          'linkedCaregiverId': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException {
        await user.delete();
        rethrow;
      }
      return profile;
    } on FirebaseAuthException catch (error) {
      throw LocalAuthException(_messageFor(error));
    }
  }

  @override
  Future<UserAccount> signIn({
    required String email,
    required String password,
    required AccountRole role,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const LocalAuthException('E-mail ou senha incorretos.');
      }

      final profileSnapshot = await _userDocument(user.uid).get();
      final profile = profileSnapshot.data();
      if (profile == null) {
        await _auth.signOut();
        throw const LocalAuthException(
          'O perfil desta conta não foi encontrado. Entre em contato com o suporte.',
        );
      }
      final storedRole = AccountRole.values.byName(profile['role'] as String);
      if (storedRole != role) {
        await _auth.signOut();
        throw const LocalAuthException(
          'O perfil selecionado não corresponde a esta conta.',
        );
      }

      return UserAccount(
        id: user.uid,
        name: profile['name'] as String,
        email: profile['email'] as String,
        role: storedRole,
        passwordSalt: '',
        passwordHash: '',
      );
    } on FirebaseAuthException catch (error) {
      throw LocalAuthException(_messageFor(error));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  DocumentReference<Map<String, dynamic>> _userDocument(String uid) =>
      _firestore.collection('users').doc(uid);

  String _messageFor(FirebaseAuthException error) => switch (error.code) {
    'email-already-in-use' => 'Este e-mail já possui uma conta.',
    'invalid-email' => 'Informe um e-mail válido.',
    'weak-password' => 'Escolha uma senha mais segura.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'E-mail ou senha incorretos.',
    'network-request-failed' =>
      'Sem conexão com a internet. Verifique a rede e tente novamente.',
    'too-many-requests' =>
      'Muitas tentativas. Aguarde um pouco e tente novamente.',
    _ => 'Não foi possível acessar a conta. Tente novamente.',
  };
}
