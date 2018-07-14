part of imap_client;

class _ImapResponse {
  /// The command completion status (OK/NO - error/BAD - command invalid)
  final String status;

  /// Additional information sent with the command completion status
  final String statusInformation;

  /// Status responses sent by the server (tagged and untagged).
  final Map<String, String> responseCodes;

  /// All untagged responses that are not OK/NO/BAD
  final Map<String, String> untagged;

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

  /// Holds all literals sent by the server
  final Map<String, String> literals;

  _ImapResponse(
      {this.status,
      this.statusInformation,
      this.responseCodes,
      this.untagged,
      this.fullResponse,
      this.unrecognizedLines,
      this.notices,
      this.warnings,
      this.errors,
      this.literals});

  /// Returns a blueprint of the map used for the [fromMap] method.
  static Map<String, dynamic> getResponseBlueprint() {
    return <String, dynamic>{
      'status': 'BAD',
      'responseCodes': <String, String>{},
      'untagged': <String, String>{},
      'unrecognizedLines': <String>[],
      'fullResponse': '',
      'notices': <String>[],
      'warnings': <String>[],
      'errors': <String>[],
      'literals': <String, String>{}
    };
  }

  /// Creates a new ImapResponse from a map.
  ///
  /// The map must use the same keys as the [_ImapResponse] and their associated
  /// data types. A blueprint can be obtained from [getResponseBlueprint].
  /// Missing values are replaced by empty defaults. A missing "status"
  /// however, indicates an error!
  static _ImapResponse fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> responses = getResponseBlueprint();
    responses.addAll(map);
    return new _ImapResponse(
        status: responses['status'],
        statusInformation: responses['statusInformation'],
        responseCodes: responses['responseCodes'],
        untagged: responses['untagged'],
        fullResponse: responses['fullResponse'],
        unrecognizedLines: responses['unrecognizedLines'],
        notices: responses['notices'],
        warnings: responses['warnings'],
        errors: responses['errors'],
        literals: responses['literals']);
  }

  /// Checks if the response status is OK (successful completion)
  bool isOK() => status.toUpperCase() == 'OK';
}