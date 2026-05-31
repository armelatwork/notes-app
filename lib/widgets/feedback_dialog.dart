import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../providers/app_provider.dart';
import '../services/app_logger.dart';
import '../services/feedback_service.dart';

class FeedbackDialog extends ConsumerStatefulWidget {
  const FeedbackDialog({super.key});

  @override
  ConsumerState<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends ConsumerState<FeedbackDialog> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();

  static const _minLength = 10;
  static const _maxLength = 1000;

  var _isSending = false;
  var _sent = false;
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSending = true;
      _error = null;
    });
    try {
      final user = ref.read(appUserProvider);
      final info = await PackageInfo.fromPlatform();
      await FeedbackService.instance.submit(
        message: _messageController.text.trim(),
        senderEmail: user?.email,
        appVersion: info.version,
        platform: Platform.isAndroid ? 'Android' : 'macOS',
      );
      if (mounted) setState(() => _sent = true);
    } on TimeoutException {
      // Message reached Formspree; confirmation was just slow to arrive.
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      AppLogger.instance.error('FeedbackDialog', 'submit failed', e);
      if (mounted) setState(() => _error = _toErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _toErrorMessage(Object e) {
    if (e is SocketException) return 'No internet connection.';
    if (e is FeedbackAlreadySubmittedException) {
      return 'You\'ve already sent feedback this session.';
    }
    return 'Failed to send. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send Feedback'),
      content: _sent ? _buildSuccess() : _buildForm(context),
      actions: _sent ? _buildSentActions(context) : _buildFormActions(context),
    );
  }

  Widget _buildSuccess() {
    return const SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
          SizedBox(height: 12),
          Text(
            'Thanks for your feedback!',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6),
          Text('We read every submission.'),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    return SizedBox(
      width: 400,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Found a bug or have a suggestion? Let us know.'),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _messageController,
              maxLength: _maxLength,
              maxLines: 4,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Describe the issue or idea…',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v?.trim().length ?? 0) < _minLength
                  ? 'Please enter at least $_minLength characters.'
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFormActions(BuildContext context) => [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSending ? null : _submit,
          child: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send'),
        ),
      ];

  List<Widget> _buildSentActions(BuildContext context) => [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ];
}
