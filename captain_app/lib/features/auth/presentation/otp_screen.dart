import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/common.dart';
import '../application/session_controller.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});

  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _controller.text.trim();
    if (code.length != AppConstants.otpLength) {
      setState(() => _error = 'Enter the ${AppConstants.otpLength}-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // On success the session changes and the router moves to the next screen by itself.
      await ref.read(sessionControllerProvider.notifier).verifyOtp(phone: widget.phone, code: code);
    } catch (error) {
      if (mounted) setState(() => _error = userMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authRepositoryProvider).sendOtp(widget.phone);
      if (mounted) showMessage(context, 'A new code was sent.');
    } catch (error) {
      if (mounted) showMessage(context, userMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Enter the code', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Sent to ${widget.phone}'),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                maxLength: AppConstants.otpLength,
                autofocus: true,
                onSubmitted: (_) => _verify(),
                decoration: InputDecoration(labelText: 'Code', errorText: _error, counterText: ''),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Verify', busy: _busy, onPressed: _verify),
              const SizedBox(height: 8),
              Center(child: TextButton(onPressed: _resend, child: const Text('Resend code'))),
            ],
          ),
        ),
      ),
    );
  }
}
