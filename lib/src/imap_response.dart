part of ImapClient;

class ImapResponse {
  /// The command completion status (OK/NO - error/BAD - command invalid)
  final String status;
  /// Additional information sent with the command completion status
  final String statusInformation;
  /// Status responses sent by the server (tagged and untagged).
  final Map<String, String> responseCodes;
  /// All untagged responses that are not OK/NO/BAD
  final List<MapEntry<String, String>> untagged;
  /// The full test response as sent by the server.
  final String fullResponse;
  /// Lines that couldn't be resolved automatically
  final List<String> unrecognizedLines;
  /// Information sent with untagged OKs
  final List<String> notices;
  /// Information sent with untagged NOs
  final List<String> warnings;
  /// Information sent with untagged BADs
  final List<String> errors;

  ImapResponse({this.status, this.statusInformation, this.responseCodes,
    this.untagged, this.fullResponse, this.unrecognizedLines,
    this.notices, this.warnings, this.errors});

  /// Creates a new ImapResponse from a map.
  ///
  /// The map must use the same keys as the [ImapResponse] and their associated
  /// data types. Missing values are replaced by empty defaults.
  /// A missing "status" indicates an error!
  static ImapResponse fromMap(Map<String, dynamic> map) {
    return new ImapResponse(
      status: map['status'] ?? 'BAD',
      statusInformation: map['statusInformation'] ?? '',
      responseCodes: map['responseCodes'] ?? {},
      untagged: map['untagged'] ?? [],
      fullResponse: map['fullResponse'],
      unrecognizedLines: map['unrecognizedLines'] ?? [],
      notices: map['notices'] ?? [],
      warnings: map['warnings'] ?? [],
      errors: map['errors'] ?? []
    );
  }

  bool isOK() => status.toUpperCase() == 'OK';
}