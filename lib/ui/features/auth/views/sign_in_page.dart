import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../data/repositories/auth_repository.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({
    super.key,
    required this.authRepository,
    required this.onContinueOffline,
    required this.onAuthenticated,
  });

  final AuthRepository authRepository;
  final VoidCallback onContinueOffline;
  final VoidCallback onAuthenticated;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  var _createAccount = false;
  var _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      if (_createAccount) {
        await widget.authRepository.createUsernamePasswordAccount(
          username: _username.text,
          password: _password.text,
        );
      } else {
        await widget.authRepository.signInWithUsernamePassword(
          username: _username.text,
          password: _password.text,
        );
      }
      widget.onAuthenticated();
    } on ApiException catch (error) {
      _error = error.message;
    } on FormatException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'The service could not be reached. You can continue offline.';
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return ColoredBox(
      color: theme.colorScheme.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ShadCard(
                title: Text('MetroLink', style: theme.textTheme.h2),
                description: const Text('Passenger journeys and operator network control.'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ShadInput(
                      controller: _username,
                      placeholder: const Text('Username'),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Demo operator access', style: theme.textTheme.small),
                          const SizedBox(height: 4),
                          Text('Username  operator.demo\nPassword  MetroLink!2026', style: theme.textTheme.muted),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ShadInput(
                      controller: _password,
                      placeholder: const Text('Password'),
                      obscureText: true,
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: theme.textTheme.small.copyWith(
                          color: theme.colorScheme.destructive,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ShadButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: Text(
                        _isSubmitting
                            ? 'Signing in...'
                            : _createAccount
                            ? 'Create account'
                            : 'Sign in',
                      ),
                    ),
                    const SizedBox(height: 10),
                    ShadButton.outline(
                      onPressed: () =>
                          setState(() => _createAccount = !_createAccount),
                      child: Text(
                        _createAccount
                            ? 'Use an existing account'
                            : 'Create an account',
                      ),
                    ),
                    const SizedBox(height: 10),
                    ShadButton.ghost(
                      onPressed: widget.onContinueOffline,
                      child: const Text('Continue offline'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
