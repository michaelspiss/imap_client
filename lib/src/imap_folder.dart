part of imap_client;

/// Represents a folder ("mailbox"), "selected state" commands are called here
class ImapFolder {
  final ImapEngine engine;
  String _name;
  String _path;

  get name => _name;

  get path => _path;

  ImapFolder(this.engine, String name, String path) {
    _name = name;
    _path = path;
  }
}
