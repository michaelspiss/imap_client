import 'package:ImapClient/imap_client.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'dart:async';

int port = 6153;
String host = "127.0.0.1";

class TestServer {
  ServerSocket socket;
  Socket client;
  Future hasConnection;
  Completer _completer;

  TestServer() {
    _completer = new Completer();
    hasConnection = _completer.future;
    ServerSocket.bind(host, port).then((socket) {
      this.socket = socket;
      this.socket.listen((client) {
        this.client = client;
        _completer.complete();
        _completer = new Completer();
        hasConnection = _completer.future;
      });
    });
  }
}

TestServer server = new TestServer();

void main() {
  group('Server greetings', ()
  {
    ImapClient client;

    setUp(() {
      client = new ImapClient();
    });

    test('Client connect is complete when server sends greeting', () {
      bool greetingSent = false;
      client.connect(host, port, false).then((_) {
        expect(greetingSent, isTrue);
      });
      server.hasConnection.then((_) {
        Future.delayed(Duration(seconds: 1), () {
          greetingSent = true;
          server.client.write("* OK\r\n");
        });
      });
    });
    test('Client sets state to connected after OK', () {
      client.connect(host, port, false).then((_) {
        expect(client.connectionState, ImapClient.stateConnected);
      });
      server.hasConnection.then((_) {
        server.client.write("* OK\r\n");
      });
    });
    test('Client sets state to authenticated after PREAUTH', () {
      client.connect(host, port, false).then((_) {
        expect(client.connectionState, ImapClient.stateAuthenticated);
      });
      server.hasConnection.then((_) {
        server.client.write("* PREAUTH\r\n");
      });
    });
    test('Client sets state to closed after BYE and disconnect', () {
      client.connect(host, port, false).then((_) {
        expect(client.connectionState, ImapClient.stateClosed);
      });
      server.hasConnection.then((_) {
        server.client.write("* BYE\r\n");
        server.client.close();
      });
    });
  });
}
