part of imap_client;

/// Represents a folder ("mailbox"), "selected state" commands are called here
class ImapFolder extends _ImapCommandable {
  /// Folder ("mailbox") name - acts as id
  String _name;

  String get name => _name;

  /// UIDVALIDITY attribute - uid for mailbox, defined in rfc 3501
  int _uidvalidity;

  int get uidvalidity => _uidvalidity;

  /// UID for next incoming mail, defined in rfc 3501
  int _uidnext;

  int get uidnext => _uidnext;

  /// Indicates whether the client has read-only (false) or read-write access
  bool _isReadWrite;

  bool get isReadWrite => _isReadWrite;

  /// List of all available flags
  List<String> _flags = new List();

  List<String> get flags => _flags;

  /// List of all flags that can be set permanently
  List<String> _permanentFlags = new List();

  List<String> get permanentFlags => _permanentFlags;

  /// The number of mails in this folder
  int _mailCount;

  int get mailCount => _mailCount;

  /// Number of recent messages in this folder
  int _recentCount;

  int get recentCount => _recentCount;

  /// Number of messages without \Seen flag in this folder
  int _unseenCount;

  int get unseenCount => _unseenCount;

  /// Should be selected right after, to avoid null pointers for attributes
  ImapFolder(ImapEngine engine, String name) {
    _engine = engine;
    _name = name;
  }

  /// May trigger housekeeping operations on selected folder. Else, like noop.
  ///
  /// Sends "CHECK" command as defined in rfc 3501
  Future<ImapTaggedResponse> check() async {
    return sendCommand("CHECK");
  }

  /// Deletes all messages with \Deleted flag and goes to unselected state.
  ///
  /// In this implementation, a simply use another folder to call close.
  /// Use expunge() rather than close(), because close() will not know which
  /// messages were deleted.
  /// ```dart
  /// inbox.close();
  /// // same as
  /// inbox.foo();
  /// client.bar(); // folder change automatically closes previous
  /// ```
  /// Sends "CLOSE" command as defined in rfc 3501
  Future<ImapTaggedResponse> close() async {
    ImapCommand command = new ImapCommand(_engine, null, "");
    _engine.enqueueCommand(command);
    await _engine.executeCommand(command);
    if (_engine._currentFolder == null) {
      return ImapTaggedResponse.ok;
    } else {
      return ImapTaggedResponse.bad;
    }
  }

  /// Deletes all messages with the \Deleted flag.
  ///
  /// [callback] is called for each deleted mail with the mail's uid as
  /// parameter.
  /// Sends "EXPUNGE" command as defined in rfc 3501
  Future<ImapTaggedResponse> expunge(void Function(int) callback) async {
    return sendCommand("EXPUNGE", untaggedHandlers: {
      "EXPUNGE": (ImapBuffer response, {int number}) async {
        callback(number);
        await response.skipLine();
      }
    });
  }

  /// Returns UIds for messages that match the given [searchQuery]
  ///
  /// Returns list of mail UIDs that match the [searchQuery]. Optionally an
  /// IANA [charset] can be given. Throws [SyntaxErrorException] if
  /// [searchQuery] is malformed or if there is a problem with the [charset].
  /// Sends "SEARCH" command as defined in rfc 3501
  Future<List<int>> search(String searchQuery,
      {bool uid = true, String charset}) async {
    charset = charset == null ? "" : charset + " ";
    String uid_s = uid ? "UID " : "";
    List<int> results = <int>[];
    ImapTaggedResponse response = await sendCommand(
        uid_s + "SEARCH " + charset + searchQuery,
        untaggedHandlers: {
          "SEARCH": (ImapBuffer response, {int number}) async {
            results.add(number);
            await response.skipLine();
          }
        });
    if (response == ImapTaggedResponse.no) {
      throw new SyntaxErrorException(
          "Search query malformed or problem with charset.");
    }
    return results;
  }

  /// Retrieves (parts) of messages from the server
  ///
  /// Either [messageIds] or [messageIdRanges] must be set, else an
  /// [ArgumentError] will be thrown. If [uid] is true, UIDs must be used.
  /// [messageDataItems] sets the scope of what items to fetch.
  /// Sends "FETCH" or "UID FETCH" command as defined in rfc 3501
  Future<Map<int, Map<String, dynamic>>> fetch(
      Iterable<String> messageDataItems,
      {Iterable<int> messageIds,
      Iterable<String> messageIdRanges,
      bool uid = false}) async {
    String uidString = uid ? "UID " : "";
    Map<int, Map<String, dynamic>> result = {};
    await sendCommand(
        uidString +
            "FETCH " +
            _getSequenceSet(messageIds, messageIdRanges) +
            " (" +
            messageDataItems.join(" ") +
            ")",
        untaggedHandlers: {
          "FETCH": (ImapBuffer buffer, {int number}) async {
            await _processFetch(buffer, number, result);
          }
        });
    return result;
  }

  /// Sets flags for messages
  ///
  /// Either [messageIds] or [messageIdRanges] must be given, else an
  /// [ArgumentError] will be thrown. If [silent] is true, the client will not
  /// automatically update affected mails. This must be done by the developer
  /// after this method returned [ImapTaggedResponse.ok]. It is always faster
  /// than the default variant, but needs to be customized by the developer.
  /// Sends "STORE" or "UID STORE" command as defined in rfc 3501
  Future<ImapTaggedResponse> store(
      ImapFlagsOption flagOption, Iterable<String> flags,
      {Iterable<int> messageIds,
      Iterable<String> messageIdRanges,
      bool silent = false,
      bool uid = false}) async {
    String silentSuffix = silent ? ".SILENT" : "";
    String sequenceSet = _getSequenceSet(messageIds, messageIdRanges);
    String option = _flagOptionToString(flagOption);
    String uidString = uid ? "UID " : "";
    return sendCommand("${uidString}STORE $sequenceSet $option$silentSuffix (" +
        flags.join(" ") +
        ")");
  }

  /// Copies specified messages to the end of the [destination] folder
  ///
  /// Flags are preserved, \Recent _should_ be set. If [uid] is true, UIds must
  /// be used.
  /// Sends "COPY" or "UID COPY" command as defined in rfc 3501
  Future<ImapTaggedResponse> copy(ImapFolder destination,
      {Iterable<int> messageIds,
      Iterable<String> messageIdRanges,
      bool uid = false}) async {
    String uidString = uid ? "UID " : "";
    return sendCommand(uidString +
        "COPY " +
        _getSequenceSet(messageIds, messageIdRanges) +
        " " +
        destination.name);
  }

  /// If this folder is no longer needed, mark it for garbage collection.
  ///
  /// Commands will no longer work, if this folder is needed later, you need to
  /// get it via [_ImapCommandable.getFolder] again.
  void destroy() {
    _engine._folderCache.remove(this.name);
    _engine = null;
  }

  /// Listens for changes to the currently selected mailbox
  ///
  /// To make the server aware that this client is still active and prevent a
  /// timeout, idle should be re-issued at least every 29 minutes.
  /// Throws an [UnsupportedException] if the server does not support the idle.
  /// The [duration] of this listening should not be less than one minute, in
  /// that case other commands might be more efficient.
  /// Sends "IDLE" command, defined in rfc 2177
  Future<ImapTaggedResponse> idle(
      [Duration duration = const Duration(minutes: 29)]) async {
    if (!_engine.hasCapability("IDLE")) {
      throw new UnsupportedException(
          "Server does not support the idle command");
    }
    _debugLog("IDLEing for " + duration.toString());
    new Timer(duration, endIdle);
    return sendCommand("IDLE");
  }

  /// Ends the currently running [idle] command
  void endIdle() {
    if (_engine._currentInstruction.command != "IDLE") {
      throw new StateException("Trying to end IDLE, but command is not active");
    }
    _engine.writeln("DONE");
  }

  /*
  Helper methods
   */

  /// Converts iterables of message UIds and message uid ranges to a string list
  ///
  /// Both arguments are allowed to be null, but not at the same time. An
  /// [ArgumentError] is thrown in this event.
  String _getSequenceSet(
      Iterable<int> messageUIds, Iterable<String> messageUIdRanges) {
    String uids = messageUIds?.join(",") ?? "";
    String uidRanges = messageUIdRanges?.join(",") ?? "";
    if (uids.isEmpty && uidRanges.isEmpty) {
      throw new ArgumentError(
          "No messages selected for flags altering operation.");
    } else if (uids.isEmpty) {
      return uidRanges;
    } else if (uidRanges.isEmpty) {
      return uids;
    } else {
      return uids + "," + uidRanges;
    }
  }

  /// Converts [ImapFlagsOption] enum to its string equivalent
  String _flagOptionToString(ImapFlagsOption option) {
    switch (option) {
      case ImapFlagsOption.add:
        return "+FLAGS";
      case ImapFlagsOption.remove:
        return "-FLAGS";
      case ImapFlagsOption.replace:
        return "FLAGS";
    }
    throw new ArgumentError("Unknown option " + option.toString());
  }

  /// Sorts data retrieved from a fetch response into [result]
  void _processFetch(ImapBuffer buffer, int number, Map result) async {
    result[number] = <String, dynamic>{};
    ImapWord word = await buffer.readWord(expected: ImapWordType.parenOpen);
    word = await buffer.readWord();
    while (word.type != ImapWordType.parenClose) {
      String dataItem = word.value.toUpperCase();
      switch (dataItem) {
        case "UID":
        case "RFC822.SIZE":
          result[number][dataItem] = await buffer.readInteger();
          break;
        case "RFC822.HEADER":
        case "RFC822.TEXT":
        case "INTERNALDATE":
          result[number][dataItem] = await _readNString(buffer);
          break;
        case "ENVELOPE":
          result[number]["ENVELOPE"] = await _processEnvelope(buffer);
          break;
        case "FLAGS":
          result[number]["FLAGS"] = await _readStringList(buffer);
          break;
        case "BODY":
        case "BODYSTRUCTURE":
          result[number][dataItem] = await _processBody(buffer);
          break;
        default:
          if (dataItem.startsWith("BODY[")) {
            int startAdr = buffer._bufferPosition;
            int endAdr = buffer._bufferPosition;
            do {
              buffer._bufferPosition++;
            } while (buffer._buffer[endAdr++] != 93 /* "]" */);
            dataItem +=
                String.fromCharCodes(buffer._buffer.getRange(startAdr, endAdr))
                    .toUpperCase();
            result[number][dataItem] = await _readNString(buffer);
          } else {
            _debugLog("No handler found for fetch data item " + dataItem);
          }
      }
      word = await buffer.readWord();
    }
    await buffer.readWord(expected: ImapWordType.eol);
  }

  /// Sorts envelope data into [envelope] map
  static Future<Map<String, dynamic>> _processEnvelope(
      ImapBuffer buffer) async {
    Map<String, dynamic> envelope = {};
    await buffer.readWord(expected: ImapWordType.parenOpen);
    envelope["date"] = await _readNString(buffer);
    envelope["subject"] = await _readNString(buffer);
    envelope["from"] = await _readAddressList(buffer);
    envelope["sender"] = await _readAddressList(buffer);
    envelope["reply-to"] = await _readAddressList(buffer);
    envelope["to"] = await _readAddressList(buffer);
    envelope["cc"] = await _readAddressList(buffer);
    envelope["bcc"] = await _readAddressList(buffer);
    envelope["in-reply-to"] = await _readNString(buffer);
    envelope["message-id"] = await _readNString(buffer);
    await buffer.readWord(expected: ImapWordType.parenClose);
    return envelope;
  }

  /*
  BODY, BODYSTRUCTURE helpers
   */

  /// Returns data from BODY or BODYSTRUCTURE as key-value Map
  ///
  /// If multiple bodies are sent, the bodies are in a list "BODIES", else only
  /// the body itself is returned.
  /// BODY example:
  /// ```
  /// {
  ///   "TYPE": "TEXT",
  ///   "SUBTYPE": "PLAIN",
  ///   "FIELDS": {
  ///     PARAMETER: {
  ///       "CHARSET": "UTF-8"
  ///     },
  ///     "ID": null,
  ///     "DESCRIPTION": null,
  ///     "ENCODING": "QUOTED-PRINTABLE",
  ///     "SIZE": 999 // number of octets
  ///   },
  ///   "BODYLINES": 26
  /// }
  /// ```
  static Future<Map<String, dynamic>> _processBody(ImapBuffer buffer) async {
    await buffer.readWord(expected: ImapWordType.parenOpen);
    ImapWord word = await buffer.readWord();
    if (word.type == ImapWordType.string) {
      buffer.unread("\"" + word.value + "\"");
      return _processBodyOnePart(buffer);
    } else if (word.type == ImapWordType.parenOpen) {
      buffer.unread(word.value);
      return _processBodyMultiPart(buffer);
    } else {
      throw new SyntaxErrorException("Could not read BODY(STRUCTURE) response");
    }
  }

  static Future<Map<String, dynamic>> _processBodyOnePart(
      ImapBuffer buffer) async {
    Map<String, dynamic> results = {
      "TYPE": (await buffer.readWord(expected: ImapWordType.string)).value,
      "SUBTYPE": (await buffer.readWord(expected: ImapWordType.string)).value
    };
    switch (results["TYPE"].toUpperCase()) {
      case "MESSAGE": // body-type-msg
        results["FIELDS"] = await _processBodyFields(buffer);
        results["ENVELOPE"] = await _processEnvelope(buffer);
        results["BODY"] = _processBody(buffer);
        results["BODYLINES"] = await buffer.readInteger();
        break;
      case "TEXT": // body-type-text
        results["FIELDS"] = await _processBodyFields(buffer);
        results["BODYLINES"] = await buffer.readInteger();
        break;
      default: // body-type-basic
        results["FIELDS"] = await _processBodyFields(buffer);
    }
    // extensions
    Map<String, dynamic> extensions = await _processExtensions(buffer, false);
    results.addAll(extensions);
    return results;
  }

  static Future<Map<String, dynamic>> _processExtensions(
      ImapBuffer buffer, bool multipart) async {
    Map<String, dynamic> extensions = {};
    int extCount = 0;
    ImapWord word = await buffer.readWord();
    while (word.type != ImapWordType.parenClose) {
      var value;
      // get value
      if (word.type == ImapWordType.nil)
        value = null;
      else if (word.type == ImapWordType.string)
        value = word.value;
      else if (word.type == ImapWordType.atom) {
        int number = int.tryParse(word.value);
        if (number != null) {
          value = number;
        } else {
          throw new SyntaxErrorException("Expected number, got $word");
        }
      } else if (word.type == ImapWordType.parenOpen) {
        if (extCount == 1) {
          // "DISPOSITION"
          value = await _processDispositionSubfields(buffer);
        } else {
          value = new List<String>();
          word = await buffer.readWord();
          while (word.type != ImapWordType.parenClose) {
            value.add(word.value);
            word = await buffer.readWord();
          }
        }
      } else {
        throw new SyntaxErrorException(
            "Expected nil, string, number or list, but got $word");
      }
      // add entry
      if (extCount == 0) {
        if (value is List) {
          Map<String, String> map = {};
          if (value.length % 2 != 0) {
            throw new SyntaxErrorException(
                "Expected key/value pairs, but got odd number of items.");
          }
          for (int i = 0; i < value.length; i = i + 2) {
            map[value[i]] = value[i + 1];
          }
          extensions["PARAMETER"] = map;
        } else {
          extensions["MD5"] = value;
        }
      } else if (extCount == 1) {
        extensions["DISPOSITION"] = value;
      } else if (extCount == 2) {
        extensions["LANGUAGE"] = value;
      } else if (extCount == 3) {
        extensions["LOCATION"] = value;
      } else {
        extensions["EXT-" + (extCount - 3).toString()] = value;
      }
      extCount++;
      word = await buffer.readWord();
    }
    return extensions;
  }

  static Future<Map<String, dynamic>> _processBodyMultiPart(
      ImapBuffer buffer) async {
    Map<String, dynamic> results = {"BODIES": <Map<String, dynamic>>[]};
    ImapWord word = await buffer.readWord();
    while (word.type == ImapWordType.parenOpen) {
      buffer.unread(word.value);
      results["BODIES"].add(await _processBody(buffer));
      word = await buffer.readWord();
    }
    if (word.type != ImapWordType.string) {
      throw new SyntaxErrorException("Expected string, but got $word");
    }
    results["SUBTYPE"] = word.value;
    // extensions
    Map<String, dynamic> extensions = await _processExtensions(buffer, false);
    results.addAll(extensions);
    return results;
  }

  static Future<Map<String, dynamic>> _processBodyFields(
      ImapBuffer buffer) async {
    // either map or nil
    Map<String, String> bodyFieldParam = new Map();
    ImapWord word = await buffer.readWord();
    if (word.type != ImapWordType.nil) {
      assert(word.type == ImapWordType.parenOpen);
      word = await buffer.readWord();
      while (word.type != ImapWordType.parenClose) {
        bodyFieldParam[word.value] =
            (await buffer.readWord(expected: ImapWordType.string)).value;
        word = await buffer.readWord();
      }
    }
    String bodyFieldId = await _readNString(buffer);
    String bodyFieldDesc = await _readNString(buffer);
    String bodyFieldEnc =
        (await buffer.readWord(expected: ImapWordType.string)).value;
    int bodyFieldOctets = await buffer.readInteger();

    return <String, dynamic>{
      "PARAMETER": bodyFieldParam,
      "ID": bodyFieldId,
      "DESCRIPTION": bodyFieldDesc,
      "ENCODING": bodyFieldEnc,
      "SIZE": bodyFieldOctets
    };
  }

  static Future<Map<String, dynamic>> _processDispositionSubfields(
      ImapBuffer buffer) async {
    Map<String, dynamic> subfieldMap = new Map();

    // expects prenOpen to be consumed already
    ImapWord word = await buffer.readWord();
    while (word.type != ImapWordType.parenClose) {
      if (word.type != ImapWordType.nil) {
        if (word.type != ImapWordType.string) {
          throw new InvalidFormatException(
              "Expected ), NIL or string, but got ${word.type}");
        }
        String key = word.value;
        word = await buffer.readWord();
        if (word.type != ImapWordType.nil) {
          Map<String, String> values = new Map();
          if (word.type != ImapWordType.parenOpen) {
            throw new InvalidFormatException(
                "Expected (, but got ${word.type}");
          }
          word = await buffer.readWord();
          while (word.type != ImapWordType.parenClose) {
            values[word.value] =
                (await buffer.readWord(expected: ImapWordType.string)).value;
            word = await buffer.readWord();
          }
          subfieldMap.addAll({key: values});
        }
      }

      word = await buffer.readWord();
    }

    return subfieldMap;
  }

  /*
  Other helpers
   */

  /// Reads words until parenthesized list ends
  static Future<List<String>> _readStringList(ImapBuffer buffer) async {
    ImapWord word = await buffer.readWord(expected: ImapWordType.parenOpen);
    word = await buffer.readWord();
    List<String> list = [];
    while (word.type != ImapWordType.parenClose) {
      list.add(word.value);
      word = await buffer.readWord();
    }
    return list;
  }

  /// Reads address lists, returns null if value is nil
  static Future<List<List<String>>> _readAddressList(ImapBuffer buffer) async {
    ImapWord word = await buffer.readWord();
    if (word.type == ImapWordType.nil) return null;
    List<List<String>> outerList = [];
    List<String> innerList = [];
    word = await buffer.readWord(expected: ImapWordType.parenOpen);
    while (word.type == ImapWordType.parenOpen) {
      word = await buffer.readWord();
      innerList.clear();
      while (word.type != ImapWordType.parenClose) {
        if (word.type == ImapWordType.nil) {
          innerList.add(null);
        } else if (word.type == ImapWordType.string) {
          innerList.add(word.value);
        } else if (word.type == ImapWordType.atom) {
          innerList.add(word.value);
        } else {
          throw new SyntaxErrorException("Expected nil or string, got $word");
        }
        word = await buffer.readWord();
      }
      outerList.add(innerList);
      word = await buffer.readWord();
    }
    return outerList;
  }

  /// Reads string that could also be NIL
  static Future<String> _readNString(ImapBuffer buffer) async {
    ImapWord word = await buffer.readWord();
    if (word.type == ImapWordType.string) return word.value;
    if (word.type == ImapWordType.atom) return word.value;
    if (word.type == ImapWordType.nil) return null;
    throw new SyntaxErrorException("Expected string or nil, but got $word");
  }
}
