import 'package:imap_client/imap_client.dart';

main() async {
  printImapClientDebugLog();
  ImapClient client = new ImapClient();
  await client.connect("imap.web.de", 993, true);
}