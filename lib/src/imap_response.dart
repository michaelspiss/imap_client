part of ImapClient;

class ImapResponse {
  final String status;
  final List<String> response;

  ImapResponse({this.status, this.response});

  bool isOK() => status.toUpperCase() == 'OK';
}