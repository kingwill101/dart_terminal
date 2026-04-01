String ghosttyTerminalNormalizeInputText(String text) {
  if (text.isEmpty) {
    return text;
  }
  return text.replaceAllMapped(
    RegExp(r'<fe0f>', caseSensitive: false),
    (_) => '\uFE0F',
  );
}
