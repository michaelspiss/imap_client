/// This library provides the interface to get emails via the imap protocol.
library imap_client;

import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:utf7/utf7.dart';

part "src/buffer_awaiter.dart";

part "src/imap_buffer.dart";

part "src/imap_command.dart";

part "src/imap_engine.dart";

part "src/imap_values.dart";

part "src/imap_word.dart";

part "src/imap_folder.dart";

part "src/imap_client.dart";

part "src/imap_greeting.dart";

part "src/imap_sasl_mechanism.dart";

part "src/imap_auth_methods.dart";

part "src/imap_commandable.dart";

part "src/imap_list_response.dart";

part "src/exceptions/invalid_format.dart";

part "src/exceptions/missing_command.dart";

part "src/exceptions/syntax_error.dart";

part "src/exceptions/state.dart";

part "src/exceptions/unsupported.dart";

Logger _logger = new Logger('imap_client');
bool _debugging = false;

/// Prints the imap client's debug log.
void printImapClientDebugLog() {
  _debugging = true;
  _logger.onRecord.listen(print);
}

/// Logs [message] if debugging
void _debugLog(String message) {
  if (_debugging) _logger.info(message);
}
