part of imap_client;

/// Special instruction, because it has no tag. Handles the server greeting.
class ImapGreeting extends ImapCommand {
  ImapGreeting(ImapEngine engine) : super(engine, null, null);

  @override
  Future<ImapTaggedResponse> run(ImapBuffer responses) async {
    ImapWord word = await responses.readWord();
    // untagged response
    if (word.type == ImapWordType.tokenAsterisk) {
      await _engine.handleUntaggedResponse();
    } else {
      throw new SyntaxErrorException(
          "Expected untagged greeting, but got " + word.value);
    }
    return ImapTaggedResponse.ok;
  }

  @override
  String toString() {
    return "[ImapGreeting]";
  }
}
