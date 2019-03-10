import 'package:imap_client/imap_client.dart';

main() async {
  // print log, helpful for debugging
  printImapClientDebugLog();

  ImapClient client = new ImapClient();
  // connect
  await client.connect("imap.gmail.com", 993, true);
  // authenticate
  await client.authenticate(new ImapPlainAuth("user@gmail.com", "password"));
  // get folder
  ImapFolder inbox = await client.getFolder("inbox");
  // get "BODY" for message 1
  print(await inbox.fetch(["BODY"], messageIds: [1]));
  // get "BODYSTRUCTURE" for message 1
  print(await inbox.fetch(["BODYSTRUCTURE"], messageIds: [1]));
  // close connection
  await client.logout();
}
