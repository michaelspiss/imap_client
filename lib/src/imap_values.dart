part of imap_client;

/// All possible tagged responses
enum ImapTaggedResponse { ok, bad, no }

/// The types an imap word can have
enum ImapWordType {
  atom, // single word with limited available characters
  tokenAsterisk, // "*"
  tokenPlus, // "+"
  string, // single word, quoted string, literal
  nil, // NIL
  flag, // Any standard flags sent by the server (starting with "\")
  eol, // "\n" ("\r" are ignored and treated as whitespace characters)
  parenOpen, // "("
  parenClose, // ")"
  bracketOpen, // "["
  bracketClose, // "]"
}

/// Options for flags methods - see [ImapFolder.store]
enum ImapFlagsOption { add, remove, replace }

/// Items that can be requested by [_ImapCommandable.status]
enum ImapStatusDataItem {
  messages, // number of messages
  recent, // number of messages with \Recent flag
  uidnext, // uid for next incoming message
  uidvalidity, // uid for folder
  unseen // number of messages without \Seen flag
}
