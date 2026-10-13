const _htmlNamedEntities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'rsquo': '’',
  'lsquo': '‘',
  'rdquo': '”',
  'ldquo': '“',
  'hellip': '…',
  'agrave': 'à',
  'egrave': 'è',
  'igrave': 'ì',
  'ograve': 'ò',
  'ugrave': 'ù',
  'aacute': 'á',
  'eacute': 'é',
  'iacute': 'í',
  'oacute': 'ó',
  'uacute': 'ú',
};

/// `String.fromCharCode` throws above 0x10FFFF (and for negatives) - hostile
/// or corrupt markup must not crash a parse, so the raw entity stays.
String _fromCode(int? code, String raw) =>
    code == null || code < 0 || code > 0x10FFFF
    ? raw
    : String.fromCharCode(code);

/// Decodes numeric (`&#39;`, `&#x27;`) and a small set of named HTML entities -
/// enough for titles and messages scraped from Italian cinema sites, not a
/// general HTML decoder.
String decodeHtmlEntities(String input) {
  return input.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (
    match,
  ) {
    final entity = match.group(1)!;
    if (entity.startsWith('#x') || entity.startsWith('#X')) {
      final code = int.tryParse(entity.substring(2), radix: 16);
      return _fromCode(code, match.group(0)!);
    }
    if (entity.startsWith('#')) {
      final code = int.tryParse(entity.substring(1));
      return _fromCode(code, match.group(0)!);
    }
    return _htmlNamedEntities[entity] ?? match.group(0)!;
  });
}

