part of imap_client;

/// Base for all types of objects that can send commands
abstract class _ImapCommandable {
  ImapEngine _engine;

  /// Sends custom command. Command must not include CRLF (\r\n)!
  ///
  /// Untagged handler maps must have keys in UPPERCASE!
  Future<ImapTaggedResponse> sendCommand(String command,
      {String Function(String) onContinue,
      Map<String, UntaggedHandler> untaggedHandlers,
      void Function() before}) {
    if (_engine == null)
      throw new StateException(
          "Trying to execute command, but engine is not connected or not set.");
    ImapFolder folder = this is ImapFolder ? this : null;
    ImapCommand imapCommand = new ImapCommand(_engine, folder, command);
    if (onContinue != null) imapCommand.setOnContinueHandler(onContinue);
    if (untaggedHandlers != null)
      imapCommand._untaggedHandlers = untaggedHandlers;
    imapCommand._before = before;
    _engine.enqueueCommand(imapCommand);
    return _engine.executeCommand(imapCommand);
  }

  /*
  ANY state commands
   */

  /// Sends "CAPABILITY" command defined in rfc 3501
  ///
  /// Updates the server's capability list, which lists extensions and auth
  /// methods supported by the server.
  Future<ImapTaggedResponse> capability() async {
    return sendCommand("CAPABILITY");
  }

  /// Sends "LOGOUT" command defined in rfc 3501
  ///
  /// This tells the server that this client would like to close the connection.
  /// The connection is then closed by the server.
  Future<ImapTaggedResponse> logout() async {
    return sendCommand("LOGOUT");
  }

  /// Sends "NOOP" command defined in rfc 3501
  ///
  /// Does not do anything, but allows the server to response with untagged
  /// responses (mailbox changes for example) and also resets the timeout timer.
  Future<ImapTaggedResponse> noop() async {
    return sendCommand("NOOP");
  }

  /*
  AUTHENTICATED state commands
   */

  /// Creates a new folder with the given [folderName]
  ///
  /// Folder name may include a hierarchy delimiter if this is supported by the
  /// server.
  /// Sends "CREATE" command, defined in rfc 3501
  Future<ImapTaggedResponse> create(String folderName) {
    return sendCommand("CREATE \"" + folderName + "\"",
        before: () => _requiresAuthenticated("CREATE"));
  }

  /// Deletes the given [folder] and all messages inside.
  ///
  /// If this folder has inferiors, those will not be deleted, but this parent
  /// folder will no longer be selectable.
  /// Sends "DELETE" command, defined in rfc 3501
  Future<ImapTaggedResponse> delete(ImapFolder folder) {
    return sendCommand("DELETE \"" + folder.name + "\"",
        before: () => _requiresAuthenticated("CREATE"));
  }

  /// Renames the given [folder] to [newName]
  ///
  /// Sends "RENAME" command, defined in rfc 3501
  Future<ImapTaggedResponse> rename(ImapFolder folder, String newName) {
    return sendCommand("RENAME \"" + folder.name + "\" \"" + newName + "\"",
        before: () => _requiresAuthenticated("CREATE"));
  }

  /// Selects folder [folderName] and returns its [ImapFolder] representation instance
  ///
  /// Commands to be executed in a folder can be called from the returned
  /// [ImapFolder] instance. If [readOnly] is set, the folder will be read-only,
  /// no write operations allowed. If [dontOpen] is set, [readOnly] will be
  /// completely ignored and the folder is returned without checks whether it
  /// even exists or not. This may be used to [rename] or [delete] mailboxes
  /// without opening them first. USE AT YOUR OWN RISK.
  /// Throws [StateException] if user is not authenticated.
  /// Sends "SELECT" or "EXAMINE" commands, defined in rfc 3501
  Future<ImapFolder> select(String folderName,
      {bool readOnly = false, bool dontOpen = false}) async {
    ImapFolder folder = new ImapFolder(_engine, folderName);
    if (dontOpen) return folder;
    if (readOnly) folder._isReadWrite = false;
    ImapCommand command = new ImapCommand(_engine, folder, "");
    command._before = () => _requiresAuthenticated("SELECT/EXAMINE");
    _engine.enqueueCommand(command);
    await _engine.executeCommand(command);
    if (_engine._currentFolder != folder)
      throw new StateException(
          "Folder \"" + folderName + "\" could not be selected.");
    return folder;
  }

  /// Lists subset of folders available to the client.
  ///
  /// If [folderName] is empty (""), the mailbox hierarchy delimiter and root
  /// name is returned. The hierarchy delimiter may be NIL if there is no
  /// hierarchy. "*" is a wildcard for zero or more characters from this position,
  /// "%" is the same as "*", but does not match the hierarchy delimiter.
  /// [referenceName] is a level of hierarchy that should always end
  /// with the hierarchy delimiter.
  /// Returns a list of [ImapListResponse]s which packs together the information
  /// retrieved from this command. If the command fails, it throws an
  /// [ArgumentError].
  /// Sends "LIST" command, defined in rfc 3501
  Future<List<ImapListResponse>> list(String folderName,
      {String referenceName = ""}) async {
    List<ImapListResponse> list = [];
    ImapTaggedResponse response = await sendCommand(
        "LIST \"" + referenceName + "\" \"" + folderName + "\"",
        before: () => _requiresAuthenticated("LIST"),
        untaggedHandlers: {
          "LIST": (ImapBuffer buffer, {int number}) async {
            await buffer.readWord(expected: ImapWordType.parenOpen);
            ImapWord word = await buffer.readWord();
            List<String> attributes = [];
            while (word.type != ImapWordType.parenClose) {
              attributes.add(word.value);
              word = await buffer.readWord();
            }
            word = await buffer.readWord();
            String hierarchyDelimiter =
                word.type == ImapWordType.nil ? null : word.value;
            String name = (await buffer.readWord()).value;
            list.add(
                new ImapListResponse(attributes, name, hierarchyDelimiter));
            await buffer.skipLine();
          }
        });
    if (response != ImapTaggedResponse.ok)
      throw new ArgumentError("Reference or name cannot be listed.");
    return list;
  }

  /// Gets a [folder]'s status [dataItems] without opening it
  ///
  /// Sends "STATUS" command, defined in rfc 3501
  Future<ImapTaggedResponse> status(
      ImapFolder folder, Iterable<ImapStatusDataItem> dataItems) async {
    return sendCommand(
        "STATUS \"" +
            folder.name +
            "\" (" +
            await _statusItemsToString(dataItems) +
            ")",
        before: () => _requiresAuthenticated("STATUS"),
        untaggedHandlers: {
          "STATUS": (ImapBuffer buffer, {int number}) async {
            await buffer.readWord(expected: ImapWordType.atom);
            await buffer.readWord(expected: ImapWordType.parenOpen);
            ImapWord word = await buffer.readWord();
            while (word.type != ImapWordType.parenClose) {
              switch (word.value.toUpperCase()) {
                case "MESSAGES":
                  folder._mailCount = await buffer.readInteger();
                  break;
                case "RECENT":
                  folder._recentCount = await buffer.readInteger();
                  break;
                case "UIDNEXT":
                  folder._uidnext = await buffer.readInteger();
                  break;
                case "UIDVALIDITY":
                  folder._uidvalidity = await buffer.readInteger();
                  break;
                case "UNSEEN":
                  folder._unseenCount = await buffer.readInteger();
                  break;
                default:
                  _debugLog("Unknown status data item: " + word.value);
              }
              word = await buffer.readWord();
            }
            await buffer.readWord(expected: ImapWordType.eol);
          }
        });
  }

  /// Appends [message] to [folder]'s message list. Does not send mails.
  ///
  /// [flags] and [dateTime] are optional data that will be set for the new
  /// message. ([flags] will set the flags + always \Recent, [dateTime] will
  /// set this message's timestamp)
  /// Sends "APPEND" command, defined in 3501
  Future<ImapTaggedResponse> append(ImapFolder folder, String message,
      {Iterable<String> flags, DateTime dateTime}) async {
    String flagsList = flags == null ? "" : " (" + flags.join(" ") + ")";
    String dateTimeString =
        dateTime == null ? "" : " " + _dateTimeToString(dateTime);
    return sendCommand(
        "APPEND \"" +
            folder.name +
            "\"" +
            flagsList +
            dateTimeString +
            " {" +
            message.codeUnits.length.toString() +
            "}",
        before: () => _requiresAuthenticated("APPEND"),
        onContinue: (String serverData) => message);
  }

  /// Converts [DateTime] to imap date
  static String _dateTimeToString(DateTime dateTime) {
    StringBuffer buffer = new StringBuffer("\"");
    buffer.write(dateTime.day.toString().padLeft(2));
    buffer.write("-");
    buffer.write(_monthToString(dateTime));
    buffer.write("-");
    buffer.write(dateTime.year);
    buffer.write(" ");
    buffer.write(dateTime.hour);
    buffer.write(":");
    buffer.write(dateTime.minute);
    buffer.write(":");
    buffer.write(dateTime.second);
    buffer.write(" ");
    buffer.write(dateTime.timeZoneOffset.isNegative ? "-" : "+");
    buffer.write(dateTime.timeZoneOffset.inHours.toString().padLeft(2, "0"));
    buffer.write(dateTime.timeZoneOffset.inMinutes.toString().padLeft(2, "0"));
    buffer.write("\"");
    return buffer.toString();
  }

  /// Gets three letter abbreviation for [dateTime] month
  static String _monthToString(DateTime dateTime) {
    int month = dateTime.month;
    if (month == 1) return "Jan";
    if (month == 2) return "Feb";
    if (month == 3) return "Mar";
    if (month == 4) return "Apr";
    if (month == 5) return "May";
    if (month == 6) return "Jun";
    if (month == 7) return "Jul";
    if (month == 8) return "Aug";
    if (month == 9) return "Sep";
    if (month == 10) return "Oct";
    if (month == 11) return "Nov";
    return "Dec";
  }

  /// Converts [ImapStatusDataItem] iterable to string for [status]
  static Future<String> _statusItemsToString(
      Iterable<ImapStatusDataItem> dataItems) {
    return Stream.fromIterable(dataItems)
        .map((ImapStatusDataItem item) => item
            .toString()
            .substring("ImapStatusDataItem.".length)
            .toUpperCase())
        .join(" ");
  }

  /// Makes sure the client is authenticated, throws [StateException] otherwise
  void _requiresAuthenticated(String command) {
    if (!_engine.isAuthenticated)
      throw new StateException(
          "Trying to use \"" + command + "\" in unauthenticated state.");
  }
}
