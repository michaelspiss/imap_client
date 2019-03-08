part of imap_client;

/// Collects data associated for a folder from a "LIST" response
class ImapListResponse {
  final List<String> attributes;
  final String name;
  final String hierarchyDelimiter;

  ImapListResponse(this.attributes, this.name, this.hierarchyDelimiter);
}
