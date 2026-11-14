/// Extracts the human counterparty name from a MoMo SMS body.
///
/// MoMo texts come from a shared shortcode (M-Money, MTN, ...), so the
/// actual sender/recipient's name lives inside the message text itself,
/// e.g. "received ... from LAMBERT BAYIRINGIRE (*********915)" or
/// "payment ... to Jeanne 929308 was completed".
class MomoCounterparty {
  static final _patterns = [
    /* "received ... from NAME (...)" / "transferred to NAME (...)" */
    RegExp(r"(?:from|to)\s+([A-Z][A-Za-z'.]+(?:\s+[A-Za-z'.]+)*)\s*\("),
    /* "payment of X to NAME <id> was completed" */
    RegExp(r"to\s+([A-Z][A-Za-z'.]+(?:\s+[A-Za-z'.]+)*)\s+\d+\s+was completed"),
    /* "transaction ... by/to NAME was completed" (merchant payments) */
    RegExp(r"(?:by|to)\s+([A-Z][A-Za-z'.]+(?:\s+[A-Za-z'.]+)*)\s+was completed"),
  ];

  /// Returns the counterparty's name found in [body], or null if the
  /// message doesn't match a known MoMo transaction phrasing.
  ///
  /// @param body - Raw SMS text to search.
  static String? extractName(String body) {
    for (final pattern in _patterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final name = match.group(1)!.trim();
        if (name.length > 1) return name;
      }
    }
    return null;
  }
}
