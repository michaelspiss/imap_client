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
  Function(String) _onContinueHandler;

  /// Constructor for an ImapCommand.
  ///
  /// The [command] will be executed by the [engine], in the given [folder]. If
  /// the [command] is to be executed without a mailbox/folder selected, pass
  /// null. [command] cannot be changed later and must be given without trailing
  /// \r\n (newline).
  ImapCommand(this._engine, this.folder, this.command) {
    // default handler just aborts
    _onContinueHandler = (String response) {
      _engine.writeln("");
    };
  }

  /// Sets a [handler] for all untagged responses of the specified [type]
  ///
  /// [type] is not case-sensitive, [handler] overwrites default behaviour if
  /// there is one for the given type.
  void setUntaggedHandler(String type, UntaggedHandler handler) {
    _untaggedHandlers[type.toUpperCase()] = handler;
  }

  /// Sets handler that is being called when there is a command continue request
  void setOnContinueHandler(Function(String) handler) {
    _onContinueHandler = handler;
  }

  @override
  String toString() {
    return "[ImapCommand " + tag + "] " + command;
  }
}
