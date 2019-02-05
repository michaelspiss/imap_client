part of imap_client;

/// Buffers all responses sent by the server and allows for read operations
class ImapBuffer {
  /// Buffers responses sent by the server
  List<int> _buffer = <int>[];

  /// The position the reader is currently at in [_buffer]
  int _bufferPosition = 0;

  /// Waits for the [_buffer] to reach a certain length
  _BufferAwaiter _bufferAwaiter;

  /// Contains all chars that have special token types
  static const Map<int, ImapWordType> _specialChars = const <int, ImapWordType>{
    10: ImapWordType.eol, // "\n"
    43: ImapWordType.tokenPlus, // "+"
    42: ImapWordType.tokenAsterisk, // "*"
    40: ImapWordType.parenOpen, // "("
    41: ImapWordType.parenClose, // ")"
    91: ImapWordType.bracketOpen, // "["
    93: ImapWordType.bracketClose, // "]"
  };

  /// All characters considered whitespaces
  static const List<int> _whitespaceChars = const [
    32, // " "
    9, // "\t"
    13 // "\r"
  ];

  /// Adds data to the buffer
  void addAll(Iterable<int> data) {
    _buffer.addAll(data);
    if (_bufferAwaiter != null &&
        _bufferAwaiter.awaitedPosition <= _buffer.length - 1) {
      _bufferAwaiter.completer.complete();
      _bufferAwaiter = null;
    }
  }

  /// Returns the whole line as string
  ///
  /// Trims whitespaces at beginning and end. Removes newline at the end
  Future<String> readLine({autoReleaseBuffer = true}) async {
    List<int> charCodes = <int>[];
    while (await _isWhitespace()) _bufferPosition++;
    while (await _getCharCode() != 10) // "\n"
      charCodes.add(await _getCharCode(proceed: true));
    _bufferPosition++; // skip over newline character
    // trim trailing whitespaces
    Iterable<int> reversed = charCodes.reversed;
    while (await _isWhitespace(reversed.first)) charCodes.removeLast();
    if (autoReleaseBuffer) _releaseUsedBuffer();
    return String.fromCharCodes(charCodes);
  }

  /// Reads the next word from [_buffer] and returns it via an [ImapWord] object
  ///
  /// Automatically figures out which type the next word is. Skips whitespaces
  /// before the word automatically.
  Future<ImapWord> readWord({autoReleaseBuffer = true}) async {
    int charAtPosition = await skipWhitespaces();
    ImapWord word;
    if (_specialChars.containsKey(charAtPosition))
      word = ImapWord(_specialChars[charAtPosition],
          String.fromCharCode(await _getCharCode(proceed: true)));
    else if (charAtPosition == 34) // "\""
      word = await readQuotedString(autoReleaseBuffer: false);
    else if (charAtPosition == 123) // "{"
      word = await readLiteral(autoReleaseBuffer: false);
    else if (charAtPosition == 92) // "\\"
      word = await readFlag(autoReleaseBuffer: false);
    else
      word = await readAtom(autoReleaseBuffer: false);
    if (autoReleaseBuffer) _releaseUsedBuffer();
    return word;
  }

  /// Reads a quoted string starting at the current [_bufferPosition]
  ///
  /// Must start with "\""
  Future<ImapWord> readQuotedString({autoReleaseBuffer = true}) async {
    if (await _getCharCode() != 34) // "\""
      throw new InvalidFormatException(
          "Expected quote at beginning of quoted string");
    _bufferPosition++;
    List<int> charCodes = <int>[];
    while (await _getCharCode() != 34) // "\""
      charCodes.add(await _getCharCode(proceed: true));
    _bufferPosition++; // move behind closing quote
    if (autoReleaseBuffer) _releaseUsedBuffer();
    return new ImapWord(ImapWordType.string, String.fromCharCodes(charCodes));
  }

  /// Reads a literal starting at the current [_bufferPosition]
  ///
  /// Must start with "{"
  Future<ImapWord> readLiteral({autoReleaseBuffer = true}) async {
    if (await _getCharCode() != 123) // "{"
      throw new InvalidFormatException(
          "Expected open curly bracket at beginning of literal");
    _bufferPosition++;
    List<int> charCodes = <int>[];
    while (await _getCharCode() >= 48 && await _getCharCode() <= 57) // 0-9
      charCodes.add(await _getCharCode(proceed: true));
    _bufferPosition++; // move behind closing curly bracket
    int length = int.parse(String.fromCharCodes(charCodes));
    ImapWord word = await readWord(autoReleaseBuffer: false);
    if (word.type != ImapWordType.eol)
      throw new InvalidFormatException("Expected newline before literal text");
    charCodes.clear();
    charCodes
        .addAll(_buffer.getRange(_bufferPosition, _bufferPosition + length));
    _bufferPosition = _bufferPosition + length;
    if (autoReleaseBuffer) _releaseUsedBuffer();
    return ImapWord(ImapWordType.string, String.fromCharCodes(charCodes));
  }

  /// Reads a flag starting at the current [_bufferPosition]
  ///
  /// Must start with "\\"
  Future<ImapWord> readFlag({autoReleaseBuffer = true}) async {
    if (await _getCharCode() != 92) // "\\"
      throw new InvalidFormatException("Expected \\ before flag name");
    _bufferPosition++;
    List<int> charCodes = <int>[];
    while (!await _isWhitespace() && await _isValidAtomCharCode())
      charCodes.add(await _getCharCode(proceed: true));
    if (autoReleaseBuffer) _releaseUsedBuffer();
    return ImapWord(ImapWordType.flag, String.fromCharCodes(charCodes));
  }

  /// Reads an atom (unquoted string) starting at the current [_bufferPosition]
  ///
  /// Detects if it is NIL and sets the type accordingly.
  Future<ImapWord> readAtom({autoReleaseBuffer = true}) async {
    List<int> charCodes = <int>[];
    if (!await _isValidAtomCharCode())
      throw new InvalidFormatException("Atom starts with illegal character");
    while (!await _isWhitespace() && await _isValidAtomCharCode())
      charCodes.add(await _getCharCode(proceed: true));
    String value = String.fromCharCodes(charCodes);
    if (autoReleaseBuffer) _releaseUsedBuffer();
    return value == "NIL"
        ? ImapWord(ImapWordType.nil, value)
        : ImapWord(ImapWordType.atom, value);
  }

  /*
  Helper methods, mostly abbreviations
   */

  /// Checks if the given, or the [_bufferPosition]'s char code is a whitespace
  Future<bool> _isWhitespace([int charCode = -1]) async {
    if (charCode == -1) charCode = await _getCharCode();
    return _whitespaceChars.contains(charCode);
  }

  /// Sets the [_bufferPosition] to the first non-whitespace char and returns it
  Future<int> skipWhitespaces() async {
    while (_whitespaceChars.contains(await _getCharCode())) _bufferPosition++;
    return await _getCharCode();
  }

  /// Releases [_buffer] from index 0 to index [_bufferPosition], resets latter
  void _releaseUsedBuffer() {
    _buffer.removeRange(0, _bufferPosition);
    _bufferPosition = 0;
  }

  /// Checks if a char code is a valid atom char code as defined in rfc 3501
  Future<bool> _isValidAtomCharCode([int charCode = -1]) async {
    if (charCode == -1) charCode = await _getCharCode();
    if (charCode <= 31 || // CTL
        charCode == 34 || // "\""
        charCode == 37 || // "%"
        charCode == 40 || // "("
        charCode == 41 || // ")"
        charCode == 42 || // "*"
        charCode == 92 || // "\\"
        charCode == 93 || // "]"
        charCode == 123 || // "{"
        charCode == 127) {
      // CTL
      return false;
    }
    return true;
  }

  /// Gets the char code - set by [_bufferPosition] or a custom position
  ///
  /// [proceed] increases the [_bufferPosition] by one.
  Future<int> _getCharCode({bool proceed = false, int position = -1}) async {
    if (position == -1) position = _bufferPosition;
    if (position >= _buffer.length) {
      _bufferAwaiter = new _BufferAwaiter(new Completer(), position);
      await _bufferAwaiter.completer.future;
    }
    if (proceed) _bufferPosition++;
    return _buffer[position];
  }
}
