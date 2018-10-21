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
  flag, // Any flags sent by the server
  eol, // "\n" ("\r" are ignored and treated as whitespace characters)
  parenOpen, // "("
  parenClose, // ")"
  bracketOpen, // "["
  bracketClose, // "]"
}
