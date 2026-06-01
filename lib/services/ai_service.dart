enum AiErrorKind { auth, rateLimit, network, timeout, server }

class AiException implements Exception {
  final AiErrorKind kind;
  const AiException(this.kind);

  @override
  String toString() => 'AiException(kind: $kind)';
}

abstract class AiService {
  /// Returns null on success, or a user-facing error string on failure.
  Future<String?> activateKey(String apiKey);
  Future<bool> isVerified();
  Future<void> clearKey();

  /// [customInstruction] replaces the default "clearer and better written"
  /// instruction. The no-dash rule is always appended unless the instruction
  /// explicitly mentions dashes or hyphens.
  Future<String> rewriteNote(String plainText, {String? customInstruction});
}

// Shared timeouts and retry config used by every provider implementation.
const kActivateTimeout = Duration(seconds: 20);
const kRewriteTimeout = Duration(seconds: 40);
const kMaxRewriteAttempts = 2;

// ── Prompt building ───────────────────────────────────────────────────────────

const _kNoDashRule =
    'Do not use dashes or hyphens as list markers. '
    'A dash may only appear as a subtraction operator in a math expression. ';

const _kReturnOnly =
    'Return only the rewritten text, no explanations or commentary:\n\n';

// Default prompt used when no custom instruction is provided.
const kRewritePrompt =
    'Rewrite the following note to be clearer and better written. '
    'Use plain paragraphs and headings only — $_kNoDashRule'
    '$_kReturnOnly';

/// Builds the full prompt for a custom instruction.
/// The no-dash rule is always included unless the instruction explicitly
/// mentions dashes or hyphens (the user is taking ownership of that rule).
String buildCustomRewritePrompt(String noteContent, String customInstruction) {
  final lower = customInstruction.toLowerCase();
  final userOverridesDashes =
      lower.contains('dash') || lower.contains('hyphen');
  final noDash = userOverridesDashes ? '' : _kNoDashRule;
  return 'Rewrite the following note. $customInstruction. '
      '$noDash'
      '$_kReturnOnly'
      '$noteContent';
}
