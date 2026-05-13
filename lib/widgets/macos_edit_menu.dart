import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/editor_menu_provider.dart';
import '../providers/format_painter_provider.dart';

/// Wraps its child with a native macOS menu bar whose Edit menu routes
/// actions directly to the active QuillController. On non-macOS platforms
/// the child is returned unchanged.
///
/// Registers its own ChangeNotifier listener on the controller so the menu
/// bar reflects undo/redo/selection state without going through Riverpod on
/// every keystroke — this avoids interfering with the toolbar buttons'
/// independent setState calls.
class MacOSEditMenu extends ConsumerStatefulWidget {
  const MacOSEditMenu({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MacOSEditMenu> createState() => _MacOSEditMenuState();
}

class _MacOSEditMenuState extends ConsumerState<MacOSEditMenu> {
  QuillController? _ctrl;
  bool _hasUndo = false;
  bool _hasRedo = false;
  bool _hasSelection = false;

  @override
  void dispose() {
    _ctrl?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final sel = ctrl.selection;
    final nextUndo = ctrl.hasUndo;
    final nextRedo = ctrl.hasRedo;
    final nextSel = sel.isValid && !sel.isCollapsed;
    if (nextUndo == _hasUndo && nextRedo == _hasRedo && nextSel == _hasSelection) {
      return;
    }
    // Defer to post-frame so the platform channel update for the menu bar
    // doesn't fire during key-event processing, which confuses macOS keyboard
    // state tracking and causes spurious "key already pressed" warnings.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _hasUndo = nextUndo;
        _hasRedo = nextRedo;
        _hasSelection = nextSel;
      });
    });
  }

  void _attachController(QuillController? next) {
    if (_ctrl == next) return;
    _ctrl?.removeListener(_onControllerChanged);
    _ctrl = next;
    _hasUndo = next?.hasUndo ?? false;
    _hasRedo = next?.hasRedo ?? false;
    _hasSelection = false;
    _ctrl?.addListener(_onControllerChanged);
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return widget.child;
    }

    _attachController(ref.watch(editorMenuProvider));
    final ctrl = _ctrl;
    final isFormatPainterActive = ref.watch(formatPainterProvider) != null;

    return PlatformMenuBar(
      menus: [
        _appMenu(),
        _editMenu(ctrl, _hasSelection, isFormatPainterActive),
        _windowMenu(),
      ],
      child: widget.child,
    );
  }

  PlatformMenu _appMenu() => PlatformMenu(
        label: 'Notes',
        menus: const [
          PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          PlatformMenuItemGroup(members: [
            PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.servicesSubmenu),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.hideOtherApplications),
            PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.showAllApplications),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ]),
        ],
      );

  PlatformMenu _editMenu(
          QuillController? ctrl, bool hasSelection, bool isFormatPainterActive) =>
      PlatformMenu(
        label: 'Edit',
        menus: [
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'Undo',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ,
                  meta: true),
              onSelected:
                  (ctrl != null && _hasUndo) ? ctrl.undo : null,
            ),
            PlatformMenuItem(
              label: 'Redo',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyZ,
                  meta: true, shift: true),
              onSelected:
                  (ctrl != null && _hasRedo) ? ctrl.redo : null,
            ),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'Cut',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyX,
                  meta: true),
              onSelected: hasSelection ? () => _cut(ctrl!) : null,
            ),
            PlatformMenuItem(
              label: 'Copy',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyC,
                  meta: true),
              onSelected: hasSelection ? () => _copy(ctrl!) : null,
            ),
            PlatformMenuItem(
              label: isFormatPainterActive
                  ? 'Cancel Formatting'
                  : 'Copy Formatting',
              onSelected: (hasSelection || isFormatPainterActive)
                  ? _toggleFormatPainter
                  : null,
            ),
            // Paste has no shortcut so ⌘V stays in Flutter's key pipeline,
            // allowing NoteEditor._onKeyEvent to handle clipboard images.
            PlatformMenuItem(
              label: 'Paste',
              onSelected: ctrl != null
                  ? () {
                      // ignore: experimental_member_use
                      ctrl.clipboardPaste();
                    }
                  : null,
            ),
            PlatformMenuItem(
              label: 'Paste and Match Style',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyV,
                  meta: true, shift: true, alt: true),
              onSelected: ctrl != null
                  ? () => _pasteMatchStyle(ctrl)
                  : null,
            ),
            PlatformMenuItem(
              label: 'Delete',
              onSelected: hasSelection ? () => _delete(ctrl!) : null,
            ),
            PlatformMenuItem(
              label: 'Select All',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyA,
                  meta: true),
              onSelected: ctrl != null ? () => _selectAll(ctrl) : null,
            ),
          ]),
          PlatformMenuItemGroup(members: [
            PlatformMenuItem(
              label: 'Find…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyF,
                  meta: true),
              onSelected: ctrl != null ? () => _openFind(ctrl) : null,
            ),
          ]),
        ],
      );

  PlatformMenu _windowMenu() => PlatformMenu(
        label: 'Window',
        menus: const [
          PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow),
          PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow),
          PlatformMenuItemGroup(members: [
            PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.arrangeWindowsInFront),
          ]),
        ],
      );

  void _toggleFormatPainter() {
    final notifier = ref.read(formatPainterProvider.notifier);
    if (ref.read(formatPainterProvider) != null) {
      notifier.clear();
      return;
    }
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final attrs = ctrl.getSelectionStyle().attributes;
    if (attrs.isNotEmpty) notifier.capture(attrs);
  }

  void _cut(QuillController ctrl) {
    _copy(ctrl);
    final sel = ctrl.selection;
    if (sel.isValid && !sel.isCollapsed) {
      ctrl.replaceText(sel.start, sel.end - sel.start, '', null);
    }
  }

  void _copy(QuillController ctrl) {
    final sel = ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final text = ctrl.document.toPlainText();
    final start = sel.start.clamp(0, text.length);
    final end = sel.end.clamp(0, text.length);
    if (start < end) {
      Clipboard.setData(ClipboardData(text: text.substring(start, end)));
    }
  }

  void _pasteMatchStyle(QuillController ctrl) {
    Clipboard.getData(Clipboard.kTextPlain).then((data) {
      final text = data?.text;
      if (text == null || text.isEmpty) return;
      final sel = ctrl.selection;
      if (sel.isValid && !sel.isCollapsed) {
        ctrl.replaceText(sel.start, sel.end - sel.start, text, null);
      } else if (sel.isValid) {
        ctrl.replaceText(sel.baseOffset, 0, text, null);
      }
    });
  }

  void _delete(QuillController ctrl) {
    final sel = ctrl.selection;
    if (sel.isValid && !sel.isCollapsed) {
      ctrl.replaceText(sel.start, sel.end - sel.start, '', null);
    }
  }

  void _openFind(QuillController ctrl) {
    showDialog<void>(
      context: context,
      builder: (_) => QuillToolbarSearchDialog(controller: ctrl),
    );
  }

  void _selectAll(QuillController ctrl) {
    ctrl.updateSelection(
      TextSelection(baseOffset: 0, extentOffset: ctrl.document.length - 1),
      ChangeSource.local,
    );
  }
}
