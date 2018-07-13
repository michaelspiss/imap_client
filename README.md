# imap_client

An interface to get emails via the imap protocol (version 4rev1) 

This interface implements the IMAP protocol (version 4 rev 1) as described in rfc 3501.
This package gives an easy access to all commands and automatically analyzes responses.
All responses are accessible through an ImapResponse object.

Supported extensions:
* RFC 2177: IMAP4 IDLE command

This package is made available under the [GNU General Public License v3.0](https://github.com/michaelspiss/ImapClient/blob/master/LICENSE).

## Usage

This example connects the client to an imap server:

```dart
import 'package:imap_client/imap_client.dart';

main() async {
  ImapClient client = new ImapClient();
  
  await client.connect("imap.gmail.com", 993, true).then((response) {
    print(response.fullResponse);
  });
}
```

All commands are async methods that can be `await`ed for. On completion,
they return an `ImapResponse` object, which holds all data that was returned
by the server until command completion. It also holds the command completion
status:
* OK: success
* NO: command was unsuccessful
* BAD: command not accepted by the server

Update responses are handled as soon as they arrive and don't show up
in the `ImapResponse`. To get EXISTS responses, you must supply a handler
function, that takes care of it. Other update responses are: EXPUNGE,
RECENT, FETCH and ALERT. Handlers can be set by setting the client's
typeHandler attributes.

Example for EXISTS:
```dart
client.existsHandler = (String mailboxName, int messageNumber) { ... }
```

## Features and bugs
Please file feature requests and bugs at the [issue tracker](https://github.com/michaelspiss/ImapClient/issues).
