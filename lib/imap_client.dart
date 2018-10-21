/// This library provides the interface to get emails via the imap protocol.
library imap_client;

import 'dart:io';
import 'dart:async';

import 'package:logging/logging.dart';

part "src/buffer_awaiter.dart";
part "src/imap_buffer.dart";
part "src/imap_command.dart";
part "src/imap_engine.dart";
part "src/imap_values.dart";
part "src/imap_word.dart";
part "src/exceptions/invalid_format.dart";

Logger _logger = new Logger('imap_client');
bool _isLoggerActive = false;

/// Prints the imap client's debug log.
void printImapClientDebugLog() {
  _isLoggerActive = true;
  _logger.onRecord.listen(print);
}
