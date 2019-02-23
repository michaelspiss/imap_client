part of imap_client;

/// Represents a folder ("mailbox"), "selected state" commands are called here
class ImapFolder {
  final ImapEngine _engine;

  /// Folder ("mailbox") name - acts as id
  String _name;

  get name => _name;

  ImapFolder(this._engine, String name) {
    _name = name;
  }
}
