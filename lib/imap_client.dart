/// This library provides the interface to get emails via the imap protocol.
library imap_client;

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';

part 'src/imap_connection.dart';

part 'src/imap_response.dart';

part 'src/imap_analyzer.dart';

part 'src/auth_methods.dart';

part 'src/imap_client.dart';

part 'src/imap_converter.dart';

Logger _logger = new Logger('imap_client');

void printImapClientDebugLog() {
  _logger.onRecord.listen(print);
}
