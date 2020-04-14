## 0.2.9

- Move pedantic to dev-dependencies (issue #22)

## 0.2.8

- Fix #21 - searching for UNSEEN emails is returning empty list

## 0.2.7

- Fix test cases for `Socket`'s new usage of `Uint8List` instead of `List<int>` 
- Update dependencies

## 0.2.6

- Fix #15 by translating folder names to utf-7 before sending it them to the server

## 0.2.5

- Fix bodystructure parsing errors (issues #16, #18)

## 0.2.4

- Fix #14 by using `utf8.decode` instead of standard `String.fromCharCodes`
- Code cleanup: Follow latest best practices

## 0.2.3

- Fix #13 by refreshing capabilities list after successful tls negotiation
- Expose capabilities list and accepted auth methods

## 0.2.2

- Merge #10, fix string with leading escaped character

## 0.2.1

- Fix #4, bug that prevented mailboxes with spaces from being opened
- Fix #7, bug that did not acknowledge escaped characters
- Fix #8, add missing imap 4 rev 1 commands (subscribe, unsubscribe, lsub)

## 0.2.0

- Version change, 1.0.0-alpha is lower than 0.1.3, which causes updates to fail

## 1.0.0-alpha

- Complete rewrite
- Now easier to use and extend
- Fix #2, a bug that prevents fetches
- Change concept of folders to representation based instead of internal handling

## 0.1.3

- Update test package to latest version
- Do travis tests on stable, now that dart v2 is out of dev

## 0.1.2

- Implement logging. Use printImapClientDebugLog() to display it.

## 0.1.1

- Fix errors caused by older dart version 2.0.0-dev.63.0
- Set minimum required sdk version to 2.0.0-dev.63.0

## 0.1.0

- Initial version
