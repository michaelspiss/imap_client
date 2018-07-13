part of imap_client;

/// Needed to pass the iteration number by reference
class _IterationWrapper {
  int _iteration = 0;

  int get iteration => _iteration;

  void increaseIteration() => _iteration++;
}

/// Authenticates using the "plain" protocol
void _authPlain(ImapConnection connection, List<int> username,
    List<int> password, _IterationWrapper iterationWrapper) {
  // Concatenate byte parts with prefixed zero bytes
  var bytes = [0]
    ..addAll(username)
    ..add(0)
    ..addAll(password);
  connection.writeln(base64.encode(bytes));
}

/// Authenticates by providing a username and password upon request
void _authLogin(ImapConnection connection, List<int> username,
    List<int> password, _IterationWrapper iterationWrapper) {
  if (iterationWrapper.iteration == 0) {
    // first request is for the username
    connection.writeln(base64.encode(username));
    iterationWrapper.increaseIteration();
  } else {
    // second request for the password
    connection.writeln(base64.encode(password));
  }
}
