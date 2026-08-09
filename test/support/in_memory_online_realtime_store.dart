import 'dart:async';

import 'package:parchesepop/online_transport.dart';
import 'package:parchesepop/online_transport_models.dart';

enum InMemoryStoreOperationKind {
  set,
  update,
  transaction,
  onDisconnect,
  cancel,
}

final class InMemoryStoreOperation {
  const InMemoryStoreOperation(this.kind, this.path);

  final InMemoryStoreOperationKind kind;
  final String path;
}

final class InMemoryOnlineRealtimeStore implements OnlineRealtimeStore {
  InMemoryOnlineRealtimeStore({int initialNowMs = 0}) : _nowMs = initialNowMs;

  final Map<String, Object?> _root = <String, Object?>{};
  final Map<String, Object?> _disconnectValues = <String, Object?>{};
  final Map<String, List<StreamController<Object?>>> _watchers = {};
  final List<InMemoryStoreOperation> operations = <InMemoryStoreOperation>[];
  int _nowMs;

  int get nowMs => _nowMs;
  Map<String, Object?> get debugSnapshot => _cloneMap(_root);

  void setNowMs(int value) => _nowMs = value;

  void advance(Duration duration) => _nowMs += duration.inMilliseconds;

  void clearOperations() => operations.clear();

  Future<void> simulateDisconnect({String? path}) async {
    final registrations = Map<String, Object?>.of(_disconnectValues);
    for (final entry in registrations.entries) {
      if (path != null && entry.key != path) continue;
      _setSync(entry.key, _clone(entry.value));
      _disconnectValues.remove(entry.key);
    }
  }

  @override
  Future<Object?> read(String path) async => _clone(_readSync(path));

  @override
  Stream<Object?> watch(String path) {
    late StreamController<Object?> controller;
    controller = StreamController<Object?>.broadcast(
      sync: true,
      onListen: () => scheduleMicrotask(() {
        if (!controller.isClosed) controller.add(_clone(_readSync(path)));
      }),
      onCancel: () {
        _watchers[path]?.remove(controller);
      },
    );
    _watchers.putIfAbsent(path, () => []).add(controller);
    return controller.stream;
  }

  @override
  Future<void> set(String path, Object? value) async {
    operations.add(
      InMemoryStoreOperation(InMemoryStoreOperationKind.set, path),
    );
    _setSync(path, _clone(value));
  }

  @override
  Future<void> update(String path, Map<String, Object?> values) async {
    operations.add(
      InMemoryStoreOperation(InMemoryStoreOperationKind.update, path),
    );
    for (final entry in values.entries) {
      final childPath = path.isEmpty ? entry.key : '$path/${entry.key}';
      _setSync(childPath, _clone(entry.value), notify: false);
    }
    _notify(path);
  }

  @override
  Future<OnlineStoreTransactionResult> transaction(
    String path,
    OnlineStoreTransactionUpdater updater,
  ) async {
    operations.add(
      InMemoryStoreOperation(InMemoryStoreOperationKind.transaction, path),
    );
    final current = _clone(_readSync(path));
    final decision = updater(current);
    return switch (decision) {
      OnlineStoreCommit(:final value) => () {
        _setSync(path, _clone(value));
        return OnlineStoreTransactionResult(
          committed: true,
          value: _clone(_readSync(path)),
        );
      }(),
      OnlineStoreAbort() => OnlineStoreTransactionResult(
        committed: false,
        value: current,
      ),
    };
  }

  @override
  Future<void> setOnDisconnect(String path, Object? value) async {
    operations.add(
      InMemoryStoreOperation(InMemoryStoreOperationKind.onDisconnect, path),
    );
    _disconnectValues[path] = _clone(value);
  }

  @override
  Future<void> cancelOnDisconnect(String path) async {
    operations.add(
      InMemoryStoreOperation(InMemoryStoreOperationKind.cancel, path),
    );
    _disconnectValues.remove(path);
  }

  @override
  Future<int> serverNowMs() async => _nowMs;

  Object? _readSync(String path) {
    Object? current = _root;
    for (final segment in _segments(path)) {
      if (current is! Map || !current.containsKey(segment)) return null;
      current = current[segment];
    }
    return current;
  }

  void _setSync(String path, Object? value, {bool notify = true}) {
    final segments = _segments(path);
    if (segments.isEmpty) {
      _root.clear();
      if (value is Map) _root.addAll(onlineMap(value));
      if (notify) _notify(path);
      return;
    }
    Map<String, Object?> parent = _root;
    for (final segment in segments.take(segments.length - 1)) {
      final child = parent[segment];
      if (child is Map<String, Object?>) {
        parent = child;
      } else if (child is Map) {
        final normalized = onlineMap(child);
        parent[segment] = normalized;
        parent = normalized;
      } else {
        final created = <String, Object?>{};
        parent[segment] = created;
        parent = created;
      }
    }
    final leaf = segments.last;
    if (value == null) {
      parent.remove(leaf);
    } else {
      parent[leaf] = value;
    }
    if (notify) _notify(path);
  }

  void _notify(String changedPath) {
    for (final entry in _watchers.entries) {
      final watchedPath = entry.key;
      final overlaps =
          watchedPath.isEmpty ||
          changedPath.isEmpty ||
          watchedPath == changedPath ||
          watchedPath.startsWith('$changedPath/') ||
          changedPath.startsWith('$watchedPath/');
      if (!overlaps) continue;
      final value = _clone(_readSync(watchedPath));
      for (final controller in List.of(entry.value)) {
        if (!controller.isClosed) controller.add(value);
      }
    }
  }

  static List<String> _segments(String path) => path
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);

  static Object? _clone(Object? value) {
    if (value is Map) return _cloneMap(onlineMap(value));
    if (value is List) return value.map(_clone).toList(growable: false);
    return value;
  }

  static Map<String, Object?> _cloneMap(Map<String, Object?> value) =>
      <String, Object?>{
        for (final entry in value.entries) entry.key: _clone(entry.value),
      };
}
