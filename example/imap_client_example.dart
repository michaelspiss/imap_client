import "package:imap_client/imap_client.dart";

main() async {
  ImapClient client = new ImapClient();

  await client.connect("imap.gmail.com", 993, true).then((response) {
    print(response.fullResponse);
  });
  await client.capability().then((response) {
    print(response.untagged['CAPABILITY']);
  });
  await client.noop();
  await client
      .authenticate("example@gmailcom", "verysecurepassword")
      .then((response) {
    print(response.status); // NO, because credentials are invalid
  });
  await client.logout().then((response) {
    print(response.fullResponse);
  });
}