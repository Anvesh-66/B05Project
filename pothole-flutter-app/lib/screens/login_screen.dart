import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Sign in, or create an account.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _registering = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final email = _email.text.trim();
    if (_registering) {
      widget.auth.register(name: _name.text.trim(), email: email, password: _password.text);
    } else {
      widget.auth.login(email: email, password: _password.text);
    }
  }

  void _toggleMode() {
    widget.auth.clearError();
    setState(() => _registering = !_registering);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.add_road_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'RoadGuard AI',
                        style: TextStyle(color: c.primary, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    _registering ? 'Create account' : 'Welcome back',
                    style: context.text.headlineSmall?.copyWith(fontSize: 28),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _registering
                        ? 'Sign up to report potholes and get alerts near you.'
                        : 'Log in to report potholes and get alerts near you.',
                    style: TextStyle(color: c.muted, fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  ListenableBuilder(listenable: widget.auth, builder: (context, _) => _buildForm(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final auth = widget.auth;
    final c = context.colors;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_registering) ...[
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                hintText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            const SizedBox(height: Gap.md),
          ],
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              hintText: 'Email address',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
            validator: (v) {
              final value = v?.trim() ?? '';
              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value) ? null : 'Enter a valid email address';
            },
          ),
          const SizedBox(height: Gap.md),
          TextFormField(
            controller: _password,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: [_registering ? AutofillHints.newPassword : AutofillHints.password],
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (v) {
              final value = v ?? '';
              if (value.isEmpty) return 'Enter your password';
              if (_registering && value.length < 8) return 'Use at least 8 characters';
              return null;
            },
          ),
          if (auth.error != null) ...[
            const SizedBox(height: Gap.md),
            MessageBanner.error(auth.error!),
          ],
          const SizedBox(height: Gap.lg),
          FilledButton(
            onPressed: auth.busy ? null : _submit,
            child: auth.busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(_registering ? 'Create Account' : 'Log In'),
          ),
          const SizedBox(height: Gap.sm),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _registering ? 'Already have an account?' : 'New here?',
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
              TextButton(
                onPressed: auth.busy ? null : _toggleMode,
                child: Text(_registering ? 'Log in' : 'Create an account'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
