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
  Future<String> rewriteNote(String plainText);
}

// Shared rewrite prompt used by every provider implementation.
const kRewritePrompt =
    'Rewrite the following note to be clearer and better written. '
    'Use plain paragraphs and headings only — do not use dashes or hyphens as list markers. '
    'A dash may only appear as a subtraction operator in a math expression. '
    'Return only the rewritten text, no explanations or commentary:\n\n';
