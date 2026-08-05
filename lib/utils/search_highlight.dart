/// Private-use marker characters recognized by the chat Markdown renderer.
///
/// The markers are deliberately unlikely to occur in a message. They let the
/// renderer style a matching substring without altering the original Markdown.
const String searchHighlightOpenMarker = '\uE000';
const String searchHighlightCloseMarker = '\uE001';

/// Adds non-printing search markers around visible, case-insensitive matches.
///
/// Markdown code and link syntax are kept unchanged. Altering those portions
/// would either change the code being displayed or break a link destination.
String markSearchMatches(String source, String query) {
  final normalizedQuery = query.trim();
  if (source.isEmpty ||
      normalizedQuery.isEmpty ||
      normalizedQuery.contains(searchHighlightOpenMarker) ||
      normalizedQuery.contains(searchHighlightCloseMarker)) {
    return source;
  }

  final protectedMarkdown = RegExp(
    r'```[\s\S]*?```|`[^`\r\n]*`|!?\[[^\]\r\n]*\]\([^\)\r\n]*\)',
  );
  final matchExpression = RegExp(
    RegExp.escape(normalizedQuery),
    caseSensitive: false,
  );

  String markSegment(String segment) {
    return segment.replaceAllMapped(matchExpression, (match) {
      return '$searchHighlightOpenMarker${match.group(0)}$searchHighlightCloseMarker';
    });
  }

  return source.splitMapJoin(
    protectedMarkdown,
    onMatch: (match) => match.group(0)!,
    onNonMatch: markSegment,
  );
}
