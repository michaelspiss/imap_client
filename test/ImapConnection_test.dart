import 'package:ImapClient/imap_client.dart';
import 'package:test/test.dart';
import 'dart:async';

void main() {
  ImapConnection connection;

  setUp(() {
    connection = new ImapConnection();
  });

  test('Connection is indicated as closed on startup', () {
    expect(connection.isOpen, false);
  });

  test('Connection is indicated as closed if it fails', () async {
    try {
      await connection.connect('unknown.host', 993, true, (_) {});
    } catch (SocketException) {}
    expect(connection.isOpen, false);
  });

  test('Connection is indicated as open if successful', () async {
    await connection.connect('imap.gmail.com', 993, true, (_) {});
    expect(connection.isOpen, true);
  });

  test('isOpen cannot be set manually', () {
    try{
      connection.isOpen = true; // ignore: assignment_to_final_no_setter
    } catch(NoSuchMethodError) {}
    expect(connection.isOpen, false);
  });

  test('sendCommand throws SocketException if the connection is not open', () {
    expect(() => connection.writeln(), throwsException);
  });

  test('sendCommand writes to the server if the connection is open', () async {
    int called = 0;
    await connection.connect('imap.gmail.com', 993, true, (_) { called++; });
    connection.writeln('0 CAPABILITY');
    // wait a second to make sure the command was able to send
    new Future.delayed(const Duration(seconds: 1), () {
      expect(called, 2);
    });
  });
}