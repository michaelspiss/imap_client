part of imap_client;

/// UntaggedHandler callback function. Used in [ImapEngine]
///
/// Untagged handlers MUST take an [ImapBuffer] instance. Handlers MUST always
/// read the whole line, including the newline character (\n). [number] is
/// optional and is only given when the number is in front of the handler's
/// name in the server's response (e.g. * 23 FETCH ...). Untagged handlers will
/// replace default handlers if set for the same type.
typedef UntaggedHandler = void Function(ImapBuffer, {int number});

class ImapCommand {
  /// The command's unique (ID) tag
  String _tag;

  String get tag => _tag;

  /// The folder this command is going to be executed in - null if no selection
  final ImapFolder folder;

  /// [ImapEngine] instance to execute command
  final ImapEngine _engine;

  /// Command this object represents.
  final String command;

  /// Holds handlers for untagged responses, types (key) are all uppercase
  Map<String, UntaggedHandler> _untaggedHandlers = new Map();

  /// Handler that is being called when there is a command continue request (+)
  String Function(String) _onContinueHandler;

  /// Response code which might have been sent by the server - else, null
  ///
  /// Only available after command completion, might hold values like PARSE,
  /// BADCHARSET or TRYCREATE
  String _responseCode;

  String get responseCode => _responseCode;

  /// Executed before run(), awaited for if async
  void Function() _before;

  /// Constructor for an ImapCommand.
  ///
  /// The [command] will be executed by the [_engine], in the given [folder]. If
  /// the [command] is to be executed without a mailbox/folder selected, pass
  /// null. [command] cannot be changed later and must be given without trailing
  /// \r\n (newline).
  ImapCommand(this._engine, this.folder, this.command) {
    _tag = _engine.generateTag();
  }

  /// Sets a [handler] for all untagged responses of the specified [type]
  ///
  /// [type] is not case-sensitive, [handler] overwrites default behaviour if
  /// there is one for the given type.
  void setUntaggedHandler(String type, UntaggedHandler handler) {
    _untaggedHandlers[type.toUpperCase()] = handler;
  }

  /// Sets handler that is being called when there is a command continue request
  void setOnContinueHandler(String Function(String) handler) {
    _onContinueHandler = handler;
  }

  /// Runs the command. Expects have exclusive access to the buffer.
  ///
  /// Server [responses] are being passed to this function wrapped in an
  /// [ImapBuffer] that already handles waiting for yet unsent responses.
  Future<ImapTaggedResponse> run(ImapBuffer responses) async {
    if (command.isEmpty) return ImapTaggedResponse.bad;
    _engine.writeln(tag + " " + command);

    ImapWord word;
    while (true) {
      word = await responses.readWord();
      // untagged response
      if (word.type == ImapWordType.tokenAsterisk) {
        await _engine.handleUntaggedResponse();
      }
      // command continue request
      else if (word.type == ImapWordType.tokenPlus) {
        String line = await responses.readLine();
        String response = _onContinueHandler?.call(line);
        if (response != null) _engine.writeln(response);
      }
      // tagged response
      else if (word.type == ImapWordType.atom && word.value[0] == 'A') {
        ImapWord status = await responses.readWord(expected: ImapWordType.atom);
        word = await responses.readWord();
        if (word.type == ImapWordType.bracketOpen) {
          await _engine.handleResponseCode();
        }
        await responses.skipLine();
        String statusValue = status.value.toUpperCase();
        if (statusValue == 'OK') return ImapTaggedResponse.ok;
        if (statusValue == 'NO') return ImapTaggedResponse.no;
        if (statusValue == 'BAD') return ImapTaggedResponse.bad;
        throw new SyntaxErrorException(
            "Expected command status after tag, but got " + status.value);
      } else {
        throw new SyntaxErrorException(
            "Expected */+/TAG, but got " + word.toString());
      }
    }
  }

  @override
  String toString() {
    return "[ImapCommand " + tag + "] " + command;
  }
}
