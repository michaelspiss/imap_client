/// This library provides the interface to get emails via the imap protocol.
library imap_client;

import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';



Logger _logger = new Logger('imap_client');

/// Prints the imap client's debug log.
void printImapClientDebugLog() {
  _logger.onRecord.listen(print);
}
