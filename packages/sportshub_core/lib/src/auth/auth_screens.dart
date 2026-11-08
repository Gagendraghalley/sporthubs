import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../module/module_providers.dart';
import '../module/sportshub_module.dart';
import '../router/core_routes.dart';
import '../theme/brand.dart';
import '../utils/friendly_error.dart';
import '../utils/validators.dart';
import '../widgets/app_page.dart';
import '../widgets/common.dart';
import '../widgets/logo.dart';
import '../widgets/splash.dart';
import 'auth_layout.dart';
import 'auth_repository.dart';

/// Why a code was emailed, which decides where entering it leads.
enum CodePurpose { signUp, signIn, resetPassword }

/// The email a code went to, between asking for it and entering it.
class PendingCode {
  final String email;
  final CodePurpose purpose;
  final String? next;

  const PendingCode({required this.email, required this.purpose, this.next});

  /// New accounts and resets choose a password next.
  bool get choosesPassword => purpose != CodePurpose.signIn;
}

final pendingCodeProvider = StateProvider<PendingCode?>((ref) => null);

/// For visitors: the lead module's own Welcome (SportsHubModule.buildWelcome)
/// or, without one, what SportsHub has (each module's public pages), and
/// signing up or in.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(enabledModulesProvider);
    // The splash while the modules load, rather than flashing the plain page
    // before a module's own.
    return SplashGate(
      ready: enabled.hasValue || !enabled.isLoading,
      builder: (context) => _page(context, enabled.valueOrNull ?? const <SportsHubModule>[]),
    );
  }

  Widget _page(BuildContext context, List<SportsHubModule> modules) {
    for (final m in modules) {
      final page = m.buildWelcome(context);
      if (page != null) return page;
    }
    return AppPage(
      body: ListView(
        padding: pagePadding(context, horizontal: 20),
        children: [
          const Center(child: SportsHubLogo(height: 150)),
          const SizedBox(height: 4),
          Text(
            'Gyms, grounds and games across Bhutan, with one account.',
            textAlign: TextAlign.center,
            style: context.text.titleMedium?.copyWith(color: context.brand.muted, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          for (final m in modules)
            for (final item in m.playerMenuItems().where((i) => i.isExternal || m.publicPaths.contains(i.route)))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: MenuTile(
                  icon: item.icon,
                  title: item.title,
                  subtitle: item.subtitle,
                  trailing: item.isExternal ? const Icon(Icons.open_in_new_rounded, size: 20) : null,
                  onTap: () => item.open(context),
                ),
              ),
          const SizedBox(height: 28),
          FilledButton(onPressed: () => context.push(CoreRoutes.signUp), child: const Text('Create an account')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => context.push(CoreRoutes.signIn), child: const Text('Sign in')),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () => context.push(CoreRoutes.registerVenue),
            icon: const Icon(Icons.storefront_rounded),
            label: const Text('Run a gym or ground? Register your venue'),
          ),
        ],
      ),
    );
  }
}

class SignInScreen extends ConsumerStatefulWidget {
  final String? next;

  const SignInScreen({super.key, this.next});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    await _run(() async {
      await ref.read(authRepositoryProvider).signIn(email: _email.text, password: _password.text);
      if (mounted) context.go(widget.next ?? CoreRoutes.home);
    });
  }

  /// Emails a code: to sign in without the password, or to reset it.
  Future<void> _sendCode(CodePurpose purpose) async {
    if (Validators.email(_email.text) != null) {
      setState(() => _error = 'Enter your email first, then tap this again.');
      return;
    }
    await _run(() async {
      await ref.read(authRepositoryProvider).sendLoginCode(_email.text);
      ref.read(pendingCodeProvider.notifier).state =
          PendingCode(email: _email.text.trim().toLowerCase(), purpose: purpose, next: widget.next);
      if (mounted) context.push(CoreRoutes.verify);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      side: AuthSide.signIn,
      title: 'Welcome Back!',
      subtitle: 'Sign in to continue to your account',
      onBack: () => context.go(CoreRoutes.welcome),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  validator: Validators.email,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _hide,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _signIn(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _hide ? 'Show password' : 'Hide password',
                      icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  validator: (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy ? null : () => _sendCode(CodePurpose.resetPassword),
            style: TextButton.styleFrom(
              foregroundColor: context.brand.accent,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14),
            ),
            child: const Text('Forgot password?'),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 4), AuthError(_error!), const SizedBox(height: 14)],
        const SizedBox(height: 6),
        AuthPrimaryButton(label: 'Sign in', icon: Icons.arrow_forward_rounded, busy: _busy, onPressed: _signIn),
        const SizedBox(height: 22),
        const AuthDivider(text: 'or continue with'),
        const SizedBox(height: 18),
        AuthSecondaryButton(
          label: 'Email me a code instead',
          icon: Icons.mark_email_read_outlined,
          onPressed: _busy ? null : () => _sendCode(CodePurpose.signIn),
        ),
        const SizedBox(height: 18),
        AuthSwitchLink(
          question: "Don't have an account?",
          action: 'Register here',
          onPressed: () => context.pushReplacement(CoreRoutes.signUpFor(widget.next)),
        ),
      ],
    );
  }
}

class SignUpScreen extends ConsumerStatefulWidget {
  final String? next;

  const SignUpScreen({super.key, this.next});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = _phone.text.trim().isEmpty ? null : Validators.normalizePhone(_phone.text);
      await ref.read(authRepositoryProvider).sendSignUpCode(email: _email.text, fullName: _name.text, phone: phone);
      ref.read(pendingCodeProvider.notifier).state =
          PendingCode(email: _email.text.trim().toLowerCase(), purpose: CodePurpose.signUp, next: widget.next);
      if (mounted) context.push(CoreRoutes.verify);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      side: AuthSide.join,
      title: 'Create Your Account',
      subtitle: 'Get started with SportsHub today',
      onBack: () => context.go(CoreRoutes.welcome),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Full name *', prefixIcon: Icon(Icons.person_outline_rounded)),
                  validator: (v) => Validators.required(v, 'Your name'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email address *', prefixIcon: Icon(Icons.mail_outline_rounded)),
                  validator: Validators.email,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    helperText: 'Optional: so your gym can reach you',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: Validators.phone,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const AuthNote(
          icon: Icons.mark_email_unread_outlined,
          text: "We'll email you a 6-digit code to confirm it's you. "
              'The same account works on the website and in the app.',
        ),
        if (_error != null) ...[const SizedBox(height: 14), AuthError(_error!)],
        const SizedBox(height: 22),
        AuthPrimaryButton(label: 'Register account', icon: Icons.person_add_alt_1_rounded, busy: _busy, onPressed: _submit),
        const SizedBox(height: 14),
        AuthSwitchLink(
          question: 'Already have an account?',
          action: 'Sign in here',
          onPressed: () => context.pushReplacement(
              widget.next == null ? CoreRoutes.signIn : CoreRoutes.signInFor(widget.next!)),
        ),
      ],
    );
  }
}

class VerifyCodeScreen extends ConsumerStatefulWidget {
  const VerifyCodeScreen({super.key});

  @override
  ConsumerState<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends ConsumerState<VerifyCodeScreen> {
  static const resendSeconds = 45;

  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  int _wait = resendSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _wait = resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _wait <= 1) t.cancel();
      if (mounted) setState(() => _wait = (_wait - 1).clamp(0, resendSeconds));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify(PendingCode pending) async {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6 digits from the email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyCode(email: pending.email, code: _code.text);
      ref.read(pendingCodeProvider.notifier).state = null;
      if (!mounted) return;
      if (pending.choosesPassword) {
        final next = pending.next;
        context.go(next == null ? CoreRoutes.setPassword : '${CoreRoutes.setPassword}?next=${Uri.encodeComponent(next)}');
      } else {
        context.go(pending.next ?? CoreRoutes.home);
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend(PendingCode pending) async {
    try {
      // Supabase made the account with the first sign-up code (its name
      // went with it), so a repeat is a plain sign-in code.
      await ref.read(authRepositoryProvider).sendLoginCode(pending.email);
      _startTimer();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A new code is on its way.')));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingCodeProvider);
    if (pending == null) {
      return AuthLayout(
        side: AuthSide.signIn,
        title: 'Start again',
        subtitle: 'Ask for a new code from the sign-in page.',
        children: [
          AuthPrimaryButton(
            label: 'Go to sign in',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => context.go(CoreRoutes.signIn),
          ),
        ],
      );
    }
    return AuthLayout(
      side: pending.purpose == CodePurpose.signUp ? AuthSide.join : AuthSide.signIn,
      title: 'Check your email',
      subtitle: 'We emailed a 6-digit code to',
      children: [
        Transform.translate(
          offset: const Offset(0, -18),
          child: Text(
            pending.email,
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: context.brand.accent),
          ),
        ),
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: context.text.headlineMedium?.copyWith(letterSpacing: 12, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(counterText: '', hintText: '000000'),
          onChanged: (v) {
            if (v.length == 6 && !_busy) _verify(pending);
          },
        ),
        const SizedBox(height: 10),
        Text(
          "Can't see it? Check your spam folder.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: context.brand.muted),
        ),
        if (_error != null) ...[const SizedBox(height: 14), AuthError(_error!)],
        const SizedBox(height: 22),
        AuthPrimaryButton(
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          busy: _busy,
          onPressed: () => _verify(pending),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _wait > 0 ? null : () => _resend(pending),
            style: TextButton.styleFrom(
              foregroundColor: context.brand.accent,
              textStyle: const TextStyle(fontFamily: brandFont, fontWeight: FontWeight.w700, fontSize: 14),
            ),
            child: Text(_wait > 0 ? 'Send a new code in $_wait s' : 'Send a new code'),
          ),
        ),
      ],
    );
  }
}

class SetPasswordScreen extends ConsumerStatefulWidget {
  final String? next;

  const SetPasswordScreen({super.key, this.next});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).setPassword(_password.text);
      if (mounted) context.go(widget.next ?? CoreRoutes.home);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      side: AuthSide.join,
      title: 'Set Account Password',
      subtitle: 'Use it to sign in next time, on the website or in the app.',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _password,
                  obscureText: _hide,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helperText: 'At least 8 characters',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _hide ? 'Show password' : 'Hide password',
                      icon: Icon(_hide ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  validator: Validators.password,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirm,
                  obscureText: _hide,
                  decoration: const InputDecoration(labelText: 'Type it again', prefixIcon: Icon(Icons.lock_outline_rounded)),
                  validator: (v) => v != _password.text ? "The passwords don't match" : null,
                  onFieldSubmitted: (_) => _save(),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 14), AuthError(_error!)],
        const SizedBox(height: 22),
        AuthPrimaryButton(label: 'Save password', icon: Icons.verified_user_outlined, busy: _busy, onPressed: _save),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _busy ? null : () => context.go(widget.next ?? CoreRoutes.home),
            style: TextButton.styleFrom(foregroundColor: context.brand.muted),
            child: const Text('Skip for now (sign in with email codes)'),
          ),
        ),
      ],
    );
  }
}
