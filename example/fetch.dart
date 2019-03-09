import 'package:imap_client/imap_client.dart';

main() async {
  printImapClientDebugLog();
  ImapClient client = new ImapClient();
  await client.connect("imap.gmail.com", 993, true);
  await client.authenticate(new ImapPlainAuth("user@gmail.com", "password"));
  ImapFolder inbox = await client.getFolder("inbox");
  print(await inbox.fetch(["BODY"], messageIds: [1]));
  print(await inbox.fetch(["BODYSTRUCTURE"], messageIds: [1]));
  await client.logout();
}