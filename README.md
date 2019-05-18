# imap_client

An interface to get emails via the imap protocol (version 4rev1) 

This interface implements the IMAP protocol (version 4 rev 1) as described in rfc 3501.
This package gives easy access to all commands and automatically analyzes responses.

Supported extensions:
* RFC 2177: IMAP4 IDLE command

This package is made available under the [GNU General Public License v3.0](https://github.com/michaelspiss/ImapClient/blob/master/LICENSE).

## Usage

This example connects the client to an imap server:

```dart
import 'package:imap_client/imap_client.dart';

main() async {
  ImapClient client = new ImapClient();
  
  await client.connect("imap.gmail.com", 993, true);
}
```

All commands are async methods that can be `await`ed for. On completion,
most return an enum `ImapTaggedResponse`, which can be either:
* OK: success
* NO: command was unsuccessful
* BAD: command not accepted by the server

Sometimes, there are commands which have  other return data, like `fetch` or `list`.

To select a folder, a simple call to `getFolder()` is sufficient:
```dart
import 'package:imap_client/imap_client.dart';

main() async {
  ImapClient client = new ImapClient();
  
  await client.connect("imap.gmail.com", 993, true);
  
  ImapFolder inbox = client.getFolder("inbox");
}
```
This `ImapFolder` instance allows for actions in this specific folder.
Folders can only exist once per name, so another call to `ImapClient.getFolder()` with
the same name will return **the same** `ImapFolder` instance! If an instance
is no longer needed, it can be marked for garbage collection via `ImapFolder.destroy()`.
This will free up some ram and should especially be considered when working with
many folders.

There are two types of handlers that are highly suggested to be implemented:
##### ALERT handler:
```dart
void Function(String message)
```
The messages passed to this function are directly from the server and must be
shown to the user (as defined in the protocol).

##### EXPUNGE handler:
```dart
void Function(int number)
```
This function receives message numbers of messages that have been deleted.

Both can be set directly via the client instance, either via `client.expungeHandler = ...`
or `client.alertHandler = ...`

`ImapFolder.store()`, `ImapFolder.fetch()` and `ImapFolder.copy()` need messages to work with.
Those messages can either be provided via the optional `messageId` parameter, or if ranges are needed,
via the optional `messageIdRanges`. One of the two must always be given.

Ranges have the following format: `start:end`, whereas `end` can also be `*`, which matches the
highest possible number as determined by the server. This means that `1:*` would match every mail in this folder.

To use message `uid`s instead of relative numbers, the optional parameter `uid` can be set to `true`.
Please note that responses from the server will also use `uid`s instead of relative numbers.

Example:
```dart
await inbox.fetch(["BODY"], messageIds: [1]);
```

### Authentication
The last important thing would be logging in. There are three possible ways:

##### Preauth
Preauth means that the client is already registered, this might be because credentials were
already submitted via the url on connect.

##### Login
The `login` command takes a username and password as parameters.
```dart
await client.login("username", "password");
``` 

##### Authenticate
The `authenticate` command is used for any other authentication mechanisms. It takes an
`ImapSaslMechanism` object and logs in via the mechanism defined there. "login" and "plain"
are both already implemented, a short walk through on how to create a custom mechanism can
be found [in the wiki](https://github.com/michaelspiss/imap_client/wiki/Create-custom-SASL-(authentication)-mechanism).

```dart
await client.authenticate(new ImapPlainAuth("username", "password"));
```
### Closing the connection
To close the connection, `logout` can either be called in a folder or the client itself.

## Features and bugs
Feel free to contribute to this project.

If you find a bug or think of a new feature, but don't know how to fix/implement it, please [open an issue](https://github.com/michaelspiss/imap_client/issues).

If you fixed a bug or implemented a new feature, please send a [pull request](https://github.com/michaelspiss/imap_client/pulls).
