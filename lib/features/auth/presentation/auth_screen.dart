import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';

import '../data/local_auth_service.dart';
import '../data/local_account_repository.dart';
import '../models/user_account.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.repository,
    this.authService,
    this.initialError,
    required this.onAuthenticated,
  });

  final AccountRepository repository;
  final AuthenticationService? authService;
  final String? initialError;
  final ValueChanged<UserAccount> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late final AuthenticationService _authService;
  AccountRole _selectedRole = AccountRole.caredFor;
  bool _isRegistering = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? LocalAuthService(widget.repository);
    _errorMessage = widget.initialError;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final account = _isRegistering
          ? await _authService.register(
              name: _nameController.text,
              email: _emailController.text,
              password: _passwordController.text,
              role: _selectedRole,
            )
          : await _authService.signIn(
              email: _emailController.text,
              password: _passwordController.text,
              role: _selectedRole,
            );
      if (!mounted) return;
      widget.onAuthenticated(account);
    } on LocalAuthException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _firebaseErrorMessage(error));
    } on Exception {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Não foi possível acessar sua conta. Confira os dados e tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _validateName(String? value) {
    if (_isRegistering && (value == null || value.trim().isEmpty)) {
      return 'Informe seu nome.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Informe seu e-mail.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Informe um e-mail válido.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Informe sua senha.';
    if (_isRegistering && value.length < 8) {
      return 'Use pelo menos 8 caracteres.';
    }
    return null;
  }

  String? _validatePasswordConfirmation(String? value) {
    if (_isRegistering && value != _passwordController.text) {
      return 'As senhas não correspondem.';
    }
    return null;
  }

  String _firebaseErrorMessage(FirebaseException error) => switch (error.code) {
    'permission-denied' => 'Sua conta não tem permissão para esta ação. Confira o perfil selecionado ou fale com o suporte.',
    'unavailable' || 'network-request-failed' =>
      'Sem conexão com a internet. Confira a rede e tente novamente.',
    _ => 'Não foi possível acessar sua conta. Tente novamente.',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          child: Icon(
                            Icons.favorite_outline,
                            size: 38,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Cuidar+',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isRegistering
                              ? 'Criar uma conta'
                              : 'Entrar na sua conta',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        SegmentedButton<bool>(
                          key: const Key('auth-mode-toggle'),
                          segments: const [
                            ButtonSegment(
                              value: false,
                              icon: Icon(Icons.login),
                              label: Text('Entrar'),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.person_add_alt_1),
                              label: Text('Criar conta'),
                            ),
                          ],
                          selected: {_isRegistering},
                          onSelectionChanged: _isLoading
                              ? null
                              : (selection) => setState(() {
                                  _isRegistering = selection.first;
                                  _errorMessage = null;
                                  _formKey.currentState?.reset();
                                }),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Perfil desta conta',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Escolha o perfil usado ao criar esta conta.',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<AccountRole>(
                          key: const Key('account-role-selector'),
                          segments: const [
                            ButtonSegment(
                              value: AccountRole.caredFor,
                              icon: Icon(Icons.elderly_outlined),
                              label: Text('Pessoa cuidada'),
                            ),
                            ButtonSegment(
                              value: AccountRole.caregiver,
                              icon: Icon(Icons.volunteer_activism_outlined),
                              label: Text('Cuidador'),
                            ),
                          ],
                          selected: {_selectedRole},
                          onSelectionChanged: _isLoading
                              ? null
                              : (selection) => setState(
                                  () => _selectedRole = selection.first,
                                ),
                        ),
                        if (_isRegistering) ...[
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('auth-name-field'),
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Nome',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: _validateName,
                          ),
                        ],
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('auth-email-field'),
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'E-mail',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('auth-password-field'),
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: _isRegistering
                              ? const [AutofillHints.newPassword]
                              : const [AutofillHints.password],
                          decoration: const InputDecoration(
                            labelText: 'Senha',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: _validatePassword,
                        ),
                        if (_isRegistering) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            key: const Key('auth-confirm-password-field'),
                            controller: _confirmPasswordController,
                            obscureText: _obscurePassword,
                            decoration: const InputDecoration(
                              labelText: 'Confirme a senha',
                              prefixIcon: Icon(Icons.lock_outline),
                              border: OutlineInputBorder(),
                            ),
                            validator: _validatePasswordConfirmation,
                          ),
                        ],
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: const Key('toggle-password-visibility'),
                            onPressed: _isLoading
                                ? null
                                : () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            label: Text(
                              _obscurePassword
                                  ? 'Mostrar senha'
                                  : 'Ocultar senha',
                            ),
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              key: const Key('auth-error-message'),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Os dados da conta e da rotina são sincronizados '
                            'para manter o acesso entre dispositivos. Nunca '
                            'compartilhe sua senha.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          key: const Key('auth-submit-button'),
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_isRegistering ? 'Criar conta' : 'Entrar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
