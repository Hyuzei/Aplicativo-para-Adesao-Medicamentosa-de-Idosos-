import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_account.dart';

abstract interface class AccountRepository {
  Future<List<UserAccount>> loadAccounts();
  Future<void> saveAccounts(List<UserAccount> accounts);
}

class PreferencesAccountRepository implements AccountRepository {
  PreferencesAccountRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _accountsKey = 'cuidar_plus.local_accounts.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<List<UserAccount>> loadAccounts() async {
    final encodedAccounts = await _preferences.getString(_accountsKey);
    if (encodedAccounts == null) return [];

    final decoded = jsonDecode(encodedAccounts);
    if (decoded is! List) {
      throw const FormatException('O cadastro local de contas está inválido.');
    }
    return decoded
        .map(
          (entry) => UserAccount.fromJson(
            Map<String, Object?>.from(entry as Map),
          ),
        )
        .toList();
  }

  @override
  Future<void> saveAccounts(List<UserAccount> accounts) async {
    await _preferences.setString(
      _accountsKey,
      jsonEncode(accounts.map((account) => account.toJson()).toList()),
    );
  }
}

class InMemoryAccountRepository implements AccountRepository {
  InMemoryAccountRepository({List<UserAccount> initialAccounts = const []})
    : _accounts = List<UserAccount>.of(initialAccounts);

  final List<UserAccount> _accounts;

  @override
  Future<List<UserAccount>> loadAccounts() async =>
      List<UserAccount>.of(_accounts);

  @override
  Future<void> saveAccounts(List<UserAccount> accounts) async {
    _accounts
      ..clear()
      ..addAll(accounts);
  }
}
