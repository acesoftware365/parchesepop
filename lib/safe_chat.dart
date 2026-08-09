import 'dart:collection';

/// The only phrases that a player can send during a match.
///
/// Keeping this as an enum (instead of accepting arbitrary text) makes it
/// impossible for the UI or an automated opponent to inject unmoderated text.
enum SafeChatPhraseId {
  hello,
  goodLuck,
  goodGame,
  greatMove,
  wellPlayed,
  wow,
  yourTurn,
  thanks,
  almost,
  oops,
  rematch,
  funGame,
}

/// Stable wire names accepted by the realtime safe-chat contract.
///
/// The server stores only these reviewed identifiers, never rendered text.
final Set<String> safeChatPhraseNames = Set<String>.unmodifiable(
  SafeChatPhraseId.values.map((phrase) => phrase.name),
);

class SafeChatPhrase {
  const SafeChatPhrase({
    required this.id,
    required this.spanish,
    required this.english,
  });

  final SafeChatPhraseId id;
  final String spanish;
  final String english;

  String textForLanguage(String languageCode) =>
      languageCode.toLowerCase() == 'en' ? english : spanish;
}

class SafeChatCatalog {
  const SafeChatCatalog._();

  static const phrases = <SafeChatPhrase>[
    SafeChatPhrase(
      id: SafeChatPhraseId.hello,
      spanish: '¡Hola!',
      english: 'Hello!',
    ),
    SafeChatPhrase(
      id: SafeChatPhraseId.goodLuck,
      spanish: '¡Buena suerte!',
      english: 'Good luck!',
    ),
    SafeChatPhrase(
      id: SafeChatPhraseId.goodGame,
      spanish: '¡Buena partida!',
      english: 'Good game!',
    ),
    SafeChatPhrase(
      id: SafeChatPhraseId.greatMove,
      spanish: '¡Gran jugada!',
      english: 'Great move!',
    ),
    SafeChatPhrase(
      id: SafeChatPhraseId.wellPlayed,
      spanish: '¡Bien jugado!',
      english: 'Well played!',
    ),
    SafeChatPhrase(id: SafeChatPhraseId.wow, spanish: '¡Wow!', english: 'Wow!'),
    SafeChatPhrase(
      id: SafeChatPhraseId.yourTurn,
      spanish: '¡Te toca!',
      english: 'Your turn!',
    ),
    SafeChatPhrase(
      id: SafeChatPhraseId.thanks,
      spanish: '¡Gracias!',
      english: 'Thanks!',
    ),
    SafeChatPhrase(
      id: SafeChatPhraseId.almost,
      spanish: '¡Casi!',
      english: 'So close!',
    ),
    SafeChatPhrase(
      id: SafeChatPhraseId.oops,
      spanish: '¡Ups!',
      english: 'Oops!',
    ),
    SafeChatPhrase(
      id: SafeChatPhraseId.rematch,
      spanish: '¿Revancha?',
      english: 'Rematch?',
    ),
    SafeChatPhrase(
      id: SafeChatPhraseId.funGame,
      spanish: '¡Qué partida tan divertida!',
      english: 'This is fun!',
    ),
  ];

  static final Map<SafeChatPhraseId, SafeChatPhrase> _byId =
      UnmodifiableMapView({for (final phrase in phrases) phrase.id: phrase});

  static SafeChatPhrase phrase(SafeChatPhraseId id) => _byId[id]!;

  static bool contains(SafeChatPhraseId id) => _byId.containsKey(id);
}

class SafeChatMessage {
  const SafeChatMessage({
    required this.senderId,
    required this.phraseId,
    required this.sentAt,
  });

  final String senderId;
  final SafeChatPhraseId phraseId;
  final DateTime sentAt;

  String textForLanguage(String languageCode) =>
      SafeChatCatalog.phrase(phraseId).textForLanguage(languageCode);
}

/// Immutable realtime envelope for one reviewed quick message.
///
/// [senderUid] is always the authenticated human who submitted the record.
/// There is deliberately no API for publishing as a CPU participant.
class OnlineSafeChatMessage {
  const OnlineSafeChatMessage({
    required this.messageId,
    required this.senderUid,
    required this.phraseId,
    required this.sentAtMs,
  });

  final String messageId;
  final String senderUid;
  final SafeChatPhraseId phraseId;
  final int sentAtMs;

  DateTime get sentAt =>
      DateTime.fromMillisecondsSinceEpoch(sentAtMs, isUtc: true);

  SafeChatMessage toSafeChatMessage() =>
      SafeChatMessage(senderId: senderUid, phraseId: phraseId, sentAt: sentAt);

  Map<String, Object?> toJson() => <String, Object?>{
    'messageId': messageId,
    'senderUid': senderUid,
    'phraseId': phraseId.name,
    'sentAt': sentAtMs,
  };

  factory OnlineSafeChatMessage.fromJson(
    Object? raw, {
    required String pathMessageId,
  }) {
    if (raw is! Map) {
      throw const FormatException('Invalid online safe-chat message.');
    }
    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw const FormatException('Invalid online safe-chat field.');
      }
      map[key] = entry.value;
    }
    const fields = <String>{'messageId', 'senderUid', 'phraseId', 'sentAt'};
    if (map.length != fields.length || !map.keys.toSet().containsAll(fields)) {
      throw const FormatException('Invalid online safe-chat schema.');
    }

    final messageId = map['messageId'];
    final senderUid = map['senderUid'];
    final phraseName = map['phraseId'];
    final sentAt = map['sentAt'];
    final phraseId = phraseName is String
        ? SafeChatPhraseId.values
              .where((candidate) => candidate.name == phraseName)
              .firstOrNull
        : null;
    if (messageId is! String ||
        messageId.isEmpty ||
        messageId.contains('/') ||
        messageId != pathMessageId ||
        senderUid is! String ||
        senderUid.trim().isEmpty ||
        senderUid.contains('/') ||
        phraseId == null ||
        sentAt is! num ||
        !sentAt.isFinite ||
        sentAt != sentAt.roundToDouble()) {
      throw const FormatException('Invalid online safe-chat message.');
    }
    return OnlineSafeChatMessage(
      messageId: messageId,
      senderUid: senderUid,
      phraseId: phraseId,
      sentAtMs: sentAt.toInt(),
    );
  }
}

enum SafeChatSendResult { sent, cooldownActive, invalidSender }

typedef SafeChatClock = DateTime Function();

/// Local cooldown/history guard that accepts catalog identifiers only.
///
/// Online rooms serialize [SafeChatPhraseId.name], never rendered text. This
/// keeps moderation and translations controlled by the clients while Firebase
/// validates the same closed catalog.
class SafeChatController {
  SafeChatController({
    this.cooldown = const Duration(seconds: 2),
    this.maxMessages = 30,
    SafeChatClock? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration cooldown;
  final int maxMessages;
  final SafeChatClock _clock;
  final List<SafeChatMessage> _messages = [];
  final Map<String, DateTime> _lastSentAt = {};

  UnmodifiableListView<SafeChatMessage> get messages =>
      UnmodifiableListView(_messages);

  SafeChatSendResult send({
    required String senderId,
    required SafeChatPhraseId phraseId,
  }) {
    final cleanSenderId = senderId.trim();
    if (cleanSenderId.isEmpty) return SafeChatSendResult.invalidSender;

    final now = _clock();
    final lastSentAt = _lastSentAt[cleanSenderId];
    if (lastSentAt != null && now.difference(lastSentAt) < cooldown) {
      return SafeChatSendResult.cooldownActive;
    }

    // phraseId is strongly typed and every enum member must have a catalog
    // entry; this assertion catches a missing reviewed translation in tests.
    assert(SafeChatCatalog.contains(phraseId));
    _messages.add(
      SafeChatMessage(senderId: cleanSenderId, phraseId: phraseId, sentAt: now),
    );
    _lastSentAt[cleanSenderId] = now;
    if (_messages.length > maxMessages) {
      _messages.removeRange(0, _messages.length - maxMessages);
    }
    return SafeChatSendResult.sent;
  }
}

enum SafeChatMoment {
  matchStarted,
  greatMove,
  capturedOpponent,
  wasCaptured,
  reachedGoal,
  fellIntoTrap,
  returnedToBase,
  matchEnded,
}

/// Restricts automated reactions to the same reviewed phrase catalog.
class SafeChatReactionPolicy {
  const SafeChatReactionPolicy();

  SafeChatPhraseId phraseFor(SafeChatMoment moment, {required int variation}) {
    return switch (moment) {
      SafeChatMoment.matchStarted =>
        variation.isEven ? SafeChatPhraseId.hello : SafeChatPhraseId.goodLuck,
      SafeChatMoment.greatMove =>
        variation.isEven ? SafeChatPhraseId.greatMove : SafeChatPhraseId.wow,
      SafeChatMoment.capturedOpponent =>
        variation.isEven ? SafeChatPhraseId.wellPlayed : SafeChatPhraseId.oops,
      SafeChatMoment.wasCaptured =>
        variation.isEven
            ? SafeChatPhraseId.almost
            : SafeChatPhraseId.wellPlayed,
      SafeChatMoment.reachedGoal =>
        variation.isEven ? SafeChatPhraseId.wow : SafeChatPhraseId.greatMove,
      SafeChatMoment.fellIntoTrap =>
        variation.isEven ? SafeChatPhraseId.oops : SafeChatPhraseId.almost,
      SafeChatMoment.returnedToBase =>
        variation.isEven ? SafeChatPhraseId.oops : SafeChatPhraseId.wow,
      SafeChatMoment.matchEnded =>
        variation.isEven ? SafeChatPhraseId.goodGame : SafeChatPhraseId.rematch,
    };
  }
}
