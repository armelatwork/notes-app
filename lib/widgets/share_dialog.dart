import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/note.dart';
import '../providers/app_provider.dart';
import '../services/app_logger.dart';
import '../services/sharing_service.dart';
import '../utils/image_utils.dart';

const _kFirestoreBase = 'https://thechaos-mynotes.web.app/note';

/// Bottom-sheet / dialog for sharing a note with collaborators.
class ShareDialog extends ConsumerStatefulWidget {
  final Note note;
  final VoidCallback onNoteUpdated;

  const ShareDialog({
    super.key,
    required this.note,
    required this.onNoteUpdated,
  });

  @override
  ConsumerState<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends ConsumerState<ShareDialog> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  late bool _isOwner;
  String? _authorEmail;
  late List<String> _collaborators;

  @override
  void initState() {
    super.initState();
    _isOwner = widget.note.sharedByEmail == null;
    _collaborators = List.from(widget.note.sharedWithEmails);
    if (!_isOwner && widget.note.firestoreId != null) {
      _loadCollaborators();
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCollaborators() async {
    setState(() => _loading = true);
    try {
      final data =
          await SharingService.instance.fetchNote(widget.note.firestoreId!);
      if (data != null && mounted) {
        setState(() {
          _authorEmail = data.ownerEmail;
          _collaborators = data.collaboratorEmails;
        });
      }
    } catch (e) {
      AppLogger.instance.warn('ShareDialog', 'failed to load collaborators', e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter an email address';
    final emailRe = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (!emailRe.hasMatch(v.trim())) return 'Enter a valid email address';
    if (_collaborators.contains(v.trim())) return 'Already added';
    return null;
  }

  Future<void> _addCollaborator() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    final user = ref.read(appUserProvider);
    if (user == null) return;

    setState(() => _loading = true);
    try {
      if (_isOwner) {
        await _addAsOwner(email, user);
      } else {
        await SharingService.instance.addCollaborator(
            widget.note.firestoreId!, email, user.email ?? '');
      }
      setState(() => _collaborators = [..._collaborators, email]);
      _emailCtrl.clear();
      if (_isOwner) widget.onNoteUpdated();
    } catch (e) {
      AppLogger.instance.error('ShareDialog', 'addCollaborator failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add collaborator')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addAsOwner(String email, AppUser user) async {
    if (widget.note.firestoreId == null) {
      await _createShare(email, user);
      return;
    }
    try {
      await SharingService.instance.addCollaborator(
          widget.note.firestoreId!, email, user.email ?? '');
      widget.note.sharedWithEmails = [..._collaborators, email];
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('not-found') || msg.contains('no document')) {
        AppLogger.instance.warn(
            'ShareDialog', 'stale firestoreId, recreating share', e);
        widget.note.firestoreId = null;
        widget.note.sharedWithEmails = [];
        await _createShare(email, user);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _createShare(String email, AppUser user) async {
    final inlinedContent = await inlineImagesForSharing(widget.note.content);
    final id = await SharingService.instance.shareNote(
      note: widget.note,
      ownerUid: user.id,
      ownerEmail: user.email ?? '',
      collaboratorEmail: email,
      contentOverride: inlinedContent,
    );
    widget.note.firestoreId = id;
    widget.note.sharedWithEmails = [email];
  }

  Future<void> _removeCollaborator(String email) async {
    if (widget.note.firestoreId == null) return;
    setState(() => _loading = true);
    try {
      await SharingService.instance.removeCollaborator(
          widget.note.firestoreId!, email);
      widget.note.sharedWithEmails =
          _collaborators.where((e) => e != email).toList();
      setState(() =>
          _collaborators = _collaborators.where((e) => e != email).toList());
      widget.onNoteUpdated();
    } catch (e) {
      AppLogger.instance.error('ShareDialog', 'removeCollaborator failed', e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copyLink() {
    final id = widget.note.firestoreId;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Share with someone first to generate a link')),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: '$_kFirestoreBase/$id'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = ref.read(appUserProvider)?.email;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isOwner)
                _OwnerHeader(onCopyLink: _copyLink)
              else
                _CollaboratorHeader(
                  authorEmail: _authorEmail,
                  sharedByEmail: widget.note.sharedByEmail,
                  onCopyLink: _copyLink,
                ),
              const SizedBox(height: 16),
              _EmailInput(
                formKey: _formKey,
                controller: _emailCtrl,
                loading: _loading,
                validator: _validateEmail,
                onAdd: _addCollaborator,
              ),
              if (_collaborators.isNotEmpty) ...[
                const SizedBox(height: 16),
                _CollaboratorList(
                  collaborators: _collaborators,
                  currentEmail: currentEmail,
                  loading: _loading,
                  canRemove: _isOwner,
                  onRemove: _removeCollaborator,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerHeader extends StatelessWidget {
  final VoidCallback onCopyLink;
  const _OwnerHeader({required this.onCopyLink});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('Share note',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const Spacer(),
        TextButton.icon(
          onPressed: onCopyLink,
          icon: const Icon(Icons.link, size: 18),
          label: const Text('Copy link'),
        ),
      ],
    );
  }
}

class _CollaboratorHeader extends StatelessWidget {
  final String? authorEmail;
  final String? sharedByEmail;
  final VoidCallback onCopyLink;

  const _CollaboratorHeader({
    required this.authorEmail,
    required this.sharedByEmail,
    required this.onCopyLink,
  });

  @override
  Widget build(BuildContext context) {
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Shared note',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton.icon(
              onPressed: onCopyLink,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Copy link'),
            ),
          ],
        ),
        if (authorEmail != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.person_outline, size: 14, color: grey),
              const SizedBox(width: 4),
              Text('Author: $authorEmail',
                  style: TextStyle(fontSize: 12, color: grey)),
            ],
          ),
        ],
        if (sharedByEmail != null) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.subdirectory_arrow_right, size: 14, color: grey),
              const SizedBox(width: 4),
              Text('Shared with you by: $sharedByEmail',
                  style: TextStyle(fontSize: 12, color: grey)),
            ],
          ),
        ],
      ],
    );
  }
}

class _EmailInput extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController controller;
  final bool loading;
  final String? Function(String?) validator;
  final VoidCallback onAdd;

  const _EmailInput({
    required this.formKey,
    required this.controller,
    required this.loading,
    required this.validator,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Google email address',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.emailAddress,
              validator: validator,
              onFieldSubmitted: (_) => onAdd(),
            ),
          ),
          const SizedBox(width: 8),
          loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton.filled(
                  onPressed: onAdd,
                  icon: const Icon(Icons.person_add_outlined),
                  tooltip: 'Add collaborator',
                ),
        ],
      ),
    );
  }
}

class _CollaboratorList extends StatelessWidget {
  final List<String> collaborators;
  final String? currentEmail;
  final bool loading;
  final bool canRemove;
  final void Function(String) onRemove;

  const _CollaboratorList({
    required this.collaborators,
    required this.currentEmail,
    required this.loading,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Collaborators',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        ...collaborators.map((email) {
          final isYou = email == currentEmail;
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(
              radius: 14,
              child: Icon(Icons.person_outline, size: 16),
            ),
            title: Text(
              isYou ? '$email (you)' : email,
              style: const TextStyle(fontSize: 14),
            ),
            trailing: (canRemove && !loading)
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => onRemove(email),
                    tooltip: 'Remove',
                  )
                : null,
          );
        }),
      ],
    );
  }
}

/// Show the share dialog as a modal bottom sheet.
void showShareDialog(BuildContext context, Note note,
    {required VoidCallback onNoteUpdated}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => ShareDialog(note: note, onNoteUpdated: onNoteUpdated),
  );
}
