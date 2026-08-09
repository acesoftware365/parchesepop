import 'package:flutter_test/flutter_test.dart';
import 'package:parchesepop/safe_chat.dart';

void main() {
  test('realtime wire catalog contains exactly the reviewed phrases', () {
    expect(safeChatPhraseNames, <String>{
      'hello',
      'goodLuck',
      'goodGame',
      'greatMove',
      'wellPlayed',
      'wow',
      'yourTurn',
      'thanks',
      'almost',
      'oops',
      'rematch',
      'funGame',
    });
  });

  test('realtime message round-trips without rendered free text', () {
    const message = OnlineSafeChatMessage(
      messageId: 'm_123_456',
      senderUid: 'guest_green',
      phraseId: SafeChatPhraseId.wellPlayed,
      sentAtMs: 1775689984000,
    );

    expect(message.toJson(), <String, Object?>{
      'messageId': 'm_123_456',
      'senderUid': 'guest_green',
      'phraseId': 'wellPlayed',
      'sentAt': 1775689984000,
    });
    final decoded = OnlineSafeChatMessage.fromJson(
      message.toJson(),
      pathMessageId: message.messageId,
    );
    expect(decoded.messageId, message.messageId);
    expect(decoded.senderUid, message.senderUid);
    expect(decoded.phraseId, message.phraseId);
    expect(decoded.sentAtMs, message.sentAtMs);
    expect(decoded.toSafeChatMessage().textForLanguage('es'), '¡Bien jugado!');
  });

  test('realtime message parser rejects spoofable or unreviewed records', () {
    Map<String, Object?> valid() => <String, Object?>{
      'messageId': 'm_valid',
      'senderUid': 'guest_green',
      'phraseId': 'hello',
      'sentAt': 1775689984000,
    };

    final badRecords = <Map<String, Object?>>[
      {...valid(), 'messageId': 'm_other'},
      {...valid(), 'senderUid': 'bad/sender'},
      {...valid(), 'phraseId': 'custom free text'},
      {...valid(), 'sentAt': 1.5},
      {...valid(), 'renderedText': 'not allowed'},
    ];
    for (final record in badRecords) {
      expect(
        () => OnlineSafeChatMessage.fromJson(record, pathMessageId: 'm_valid'),
        throwsFormatException,
      );
    }
  });

  test('every approved phrase has Spanish and English copy', () {
    expect(SafeChatCatalog.phrases, hasLength(SafeChatPhraseId.values.length));
    expect(
      SafeChatCatalog.phrases.map((phrase) => phrase.id).toSet(),
      SafeChatPhraseId.values.toSet(),
    );
    for (final phrase in SafeChatCatalog.phrases) {
      expect(phrase.spanish.trim(), isNotEmpty);
      expect(phrase.english.trim(), isNotEmpty);
    }
  });

  test('controller stores catalog IDs and applies per-sender cooldown', () {
    var now = DateTime.utc(2026, 7, 28, 12);
    final chat = SafeChatController(clock: () => now);

    expect(
      chat.send(senderId: 'juan', phraseId: SafeChatPhraseId.greatMove),
      SafeChatSendResult.sent,
    );
    expect(
      chat.send(senderId: 'juan', phraseId: SafeChatPhraseId.wow),
      SafeChatSendResult.cooldownActive,
    );
    expect(
      chat.send(senderId: 'sofia', phraseId: SafeChatPhraseId.wow),
      SafeChatSendResult.sent,
    );

    now = now.add(const Duration(seconds: 2));
    expect(
      chat.send(senderId: 'juan', phraseId: SafeChatPhraseId.goodGame),
      SafeChatSendResult.sent,
    );
    expect(chat.messages, hasLength(3));
    expect(chat.messages.first.textForLanguage('es'), '¡Gran jugada!');
    expect(chat.messages.first.textForLanguage('en'), 'Great move!');
  });

  test('chat rejects an empty sender and retains only the latest messages', () {
    var now = DateTime.utc(2026, 7, 28, 12);
    final chat = SafeChatController(
      cooldown: Duration.zero,
      maxMessages: 2,
      clock: () => now,
    );

    expect(
      chat.send(senderId: ' ', phraseId: SafeChatPhraseId.hello),
      SafeChatSendResult.invalidSender,
    );
    for (final phrase in [
      SafeChatPhraseId.hello,
      SafeChatPhraseId.goodLuck,
      SafeChatPhraseId.goodGame,
    ]) {
      now = now.add(const Duration(seconds: 1));
      expect(
        chat.send(senderId: 'juan', phraseId: phrase),
        SafeChatSendResult.sent,
      );
    }
    expect(chat.messages.map((message) => message.phraseId), [
      SafeChatPhraseId.goodLuck,
      SafeChatPhraseId.goodGame,
    ]);
  });

  test('automated reactions can only return reviewed phrase IDs', () {
    const policy = SafeChatReactionPolicy();
    for (final moment in SafeChatMoment.values) {
      for (var variation = 0; variation < 4; variation++) {
        final phraseId = policy.phraseFor(moment, variation: variation);
        expect(SafeChatCatalog.contains(phraseId), isTrue);
      }
    }
  });
}
