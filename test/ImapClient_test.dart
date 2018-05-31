import 'package:ImapClient/ImapClient.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    ImapClient client;

    setUp(() {
      client = new ImapClient();
    });

    test('First Test', () {
      //expect(awesome.isAwesome, isTrue);
    });
  });
}
