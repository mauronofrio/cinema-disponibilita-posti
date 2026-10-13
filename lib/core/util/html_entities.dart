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
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    if (entity.startsWith('#')) {
      final code = int.tryParse(entity.substring(1));
      return code == null ? match.group(0)! : String.fromCharCode(code);
    }
    return _htmlNamedEntities[entity] ?? match.group(0)!;
  });
}

