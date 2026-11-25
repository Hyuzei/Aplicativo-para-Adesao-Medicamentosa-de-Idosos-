import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/user_account.dart';
import 'local_account_repository.dart';

class LocalAuthException implements Exception {
  const LocalAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AuthenticationService {
  Future<UserAccount?> restoreSession();

  Future<UserAccount> register({
    required String name,
    required String email,
    required String password,
    required AccountRole role,
  });

  Future<UserAccount> signIn({
    required String email,
    required String password,
    required AccountRole role,
  });

  Future<void> signOut();
}

class LocalAuthService implements AuthenticationService {
  LocalAuthService(this._repository);

  static const _pbkdf2Iterations = 120000;
  static const _derivedKeyLength = 32;
  final AccountRepository _repository;

  @override
  Future<UserAccount?> restoreSession() async => null;

  @override
  Future<UserAccount> register({
    required String name,
    required String email,
    required String password,
    required AccountRole role,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final accounts = await _repository.loadAccounts();
    if (accounts.any((account) => account.email == normalizedEmail)) {
      throw const LocalAuthException(
        'Já existe uma conta cadastrada com este e-mail.',
      );
    }

    final salt = _secureRandomBytes(16);
    final account = UserAccount(
      name: name.trim(),
      email: normalizedEmail,
      role: role,
      passwordSalt: base64Encode(salt),
      passwordHash: base64Encode(await _derivePasswordKey(password, salt)),
    );
    await _repository.saveAccounts([...accounts, account]);
    return account;
  }

  @override
  Future<UserAccount> signIn({
    required String email,
    required String password,
    required AccountRole role,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final accounts = await _repository.loadAccounts();
    UserAccount? account;
    for (final candidate in accounts) {
      if (candidate.email == normalizedEmail) {
        account = candidate;
        break;
      }
    }

    if (account == null ||
        account.role != role ||
        !_constantTimeEquals(
          base64Decode(account.passwordHash),
          await _derivePasswordKey(
            password,
            base64Decode(account.passwordSalt),
          ),
        )) {
      throw const LocalAuthException('E-mail, senha ou perfil incorretos.');
    }
    return account;
  }

  @override
  Future<void> signOut() async {}

  Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Future<Uint8List> _derivePasswordKey(String password, List<int> salt) async {
    final hmac = Hmac(sha256, utf8.encode(password));
    final blockInput = Uint8List(salt.length + 4)
      ..setRange(0, salt.length, salt);
    blockInput.setRange(salt.length, salt.length + 4, [0, 0, 0, 1]);

    var current = hmac.convert(blockInput).bytes;
    final derivedKey = Uint8List.fromList(current);
    for (var iteration = 1; iteration < _pbkdf2Iterations; iteration++) {
      current = hmac.convert(current).bytes;
      for (var index = 0; index < derivedKey.length; index++) {
        derivedKey[index] ^= current[index];
      }
      if (iteration % 2048 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return Uint8List.sublistView(derivedKey, 0, _derivedKeyLength);
  }

  bool _constantTimeEquals(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first[index] ^ second[index];
    }
    return difference == 0;
  }
}
