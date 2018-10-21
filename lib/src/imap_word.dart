part of imap_client;

/// A word of any [ImapWordType] extracted from the server's response
class ImapWord {
  final ImapWordType type;
  final String value;

  ImapWord(this.type, this.value);
}
