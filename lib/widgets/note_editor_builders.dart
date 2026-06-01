part of 'note_editor.dart';

// ── Editor builders ───────────────────────────────────────────────────────────

extension _NoteEditorBuilders on _NoteEditorState {
  void _registerListeners(Note note) {
    ref.listen(aiHelperRequestProvider, (prev, next) {
      if (next > (prev ?? 0) && _controller != null) _onAiHelper();
    });
    final firestoreId = note.firestoreId;
    if (firestoreId != null) {
      ref.listen(sharedNoteStreamProvider(firestoreId), (_, next) {
        final remote = next.valueOrNull;
        if (remote == null || _isDirty || !mounted) return;
        final user = ref.read(appUserProvider);
        if (remote.updatedBy == user?.id) return;
        _applyRemoteContent(remote.content, remote.title);
      });
    }
  }

  Widget _buildDropTarget() => DropTarget(
        onDragEntered: (_) => _rebuild(() => _dragging = true),
        onDragExited: (_) => _rebuild(() => _dragging = false),
        onDragDone: (detail) async {
          _rebuild(() => _dragging = false);
          for (final file in detail.files) {
            if (isImagePath(file.path)) {
              await embedImageFile(_controller!, file.path);
            }
          }
          if (mounted) _rebuild(() {});
        },
        child: Stack(
          children: [
            _buildEditorLayout(),
            if (_dragging) _DragOverlay(),
          ],
        ),
      );

  // ValueKey forces toolbar rebuild on controller change so the history
  // buttons re-subscribe to the new controller.changes stream.
  NoteFormattingToolbar _buildToolbar() => NoteFormattingToolbar(
        key: ValueKey(_controller),
        quillController: _controller!,
        onInsertImage: _pickAndInsertImage,
        onInsertLink: _onInsertLink,
        editorFocusNode: _focusNode,
        isAiSheetOpen: _isAiSheetOpen,
      );

  NoteTitleField _buildTitleField(bool aiVerified) => NoteTitleField(
        controller: _titleController,
        hintText: _hintTitle,
        onChanged: _scheduleSave,
        isShared: _currentNote?.isShared ?? false,
        onShare: _currentNote == null
            ? null
            : () => showShareDialog(
                  context,
                  _currentNote!,
                  onNoteUpdated: () {
                    ref.read(notesProvider.notifier).saveNote(_currentNote!);
                    if (mounted) _rebuild(() {});
                  },
                ),
        isPinned: _currentNote?.isPinned ?? false,
        onPin: _currentNote == null
            ? null
            : () =>
                ref.read(notesProvider.notifier).togglePin(_currentNote!.id),
        onAiHelper: aiVerified ? _onAiHelper : null,
      );

  Widget _buildEditorLayout() {
    final aiVerified = ref.watch(aiKeyVerifiedProvider).valueOrNull ?? false;
    final toolbar = _buildToolbar();
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    return Column(
      children: [
        _buildTitleField(aiVerified),
        if (isMacOS) toolbar,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: _buildEditor(),
          ),
        ),
        if (!isMacOS) toolbar,
      ],
    );
  }

  Widget _buildEditor() {
    final editor = QuillEditor.basic(
      controller: _controller!,
      focusNode: _focusNode,
      config: _buildEditorConfig(),
    );
    return defaultTargetPlatform != TargetPlatform.macOS
        ? _buildAndroidListener(editor)
        : _buildMacListener(editor);
  }

  QuillEditorConfig _buildEditorConfig() => QuillEditorConfig(
        placeholder: 'Start writing…',
        enableInteractiveSelection: true,
        // Quill's selection toolbar overlaps the toolbar on macOS; use showMenu.
        enableSelectionToolbar: defaultTargetPlatform != TargetPlatform.macOS,
        customStyleBuilder: defaultTargetPlatform == TargetPlatform.macOS
            ? macFontStyleBuilder
            : null,
        embedBuilders: [
          NoteImageEmbedBuilder(controller: _controller!),
          const NoteTabEmbedBuilder(),
          const NoteTableEmbedBuilder(),
        ],
        // ignore: experimental_member_use
        onKeyPressed: _onEditorKeyPressed,
        onTapUp: _onEditorTapUp,
        quillMagnifierBuilder: defaultTargetPlatform == TargetPlatform.android
            ? defaultQuillMagnifierBuilder
            : null,
        onLaunchUrl: _onEditorLaunchUrl,
        contextMenuBuilder: defaultTargetPlatform == TargetPlatform.macOS
            ? null
            : (ctx, rawEditorState) => _buildContextMenu(ctx, rawEditorState),
      );

  KeyEventResult? _onEditorKeyPressed(KeyEvent event, Node? node) {
    if (event is! KeyDownEvent) return null;
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _insertTab();
      return KeyEventResult.handled;
    }
    // Intercept Cmd+C/X/V (macOS) and Ctrl+C/X/V (other) so Quill's
    // built-in plain-text handlers never run.
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    final modifierDown = isMac
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (!modifierDown) return null;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyV) { _handlePaste(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyC) { _handleCopy(); return KeyEventResult.handled; }
    if (key == LogicalKeyboardKey.keyX) { _handleCut();  return KeyEventResult.handled; }
    return null;
  }

  bool _onEditorTapUp(
      TapUpDetails details, TextPosition Function(Offset) getPosition) {
    final pos = getPosition(details.localPosition);
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      // Cmd+click opens link; plain click just positions the cursor.
      if (HardwareKeyboard.instance.isMetaPressed) {
        openLinkAtPosition(_controller!, pos.offset);
      }
    } else {
      openLinkAtPosition(_controller!, pos.offset);
    }
    return false;
  }

  Future<void> _onEditorLaunchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildAndroidListener(Widget editor) => Listener(
        onPointerDown: (_) => _primaryPointerDown = true,
        onPointerUp: (_) {
          _primaryPointerDown = false;
          _onPrimaryPointerUp();
        },
        child: editor,
      );

  Widget _buildMacListener(Widget editor) => Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            _secondaryButtonActive = true;
          } else if (event.buttons == kPrimaryMouseButton) {
            _primaryPointerDown = true;
            _trackPrimaryTap();
          }
        },
        onPointerUp: (event) {
          if (_secondaryButtonActive) {
            _secondaryButtonActive = false;
            final pos = event.position;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showMacContextMenu(pos);
            });
            return;
          }
          _primaryPointerDown = false;
          _onPrimaryPointerUp();
        },
        child: editor,
      );
}
