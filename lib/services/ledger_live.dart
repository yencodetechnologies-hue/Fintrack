import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/app_config.dart';
import 'ledger_events.dart';

/// One live connection to the backend (backend/services/realtime.js). The open company's screen joins its room;
/// when someone else changes something there the server sends { companyId, topics } and only the screens showing
/// those topics reload (via [notifyLedgerChanged]).
class LedgerLive {
  static io.Socket? _socket;
  static String? _companyId;
  static String? _userId;
  static bool _connectedOnce = false;

  /// Sent with this device's writes so the server doesn't announce them back to us.
  static String? get socketId => (_socket?.connected ?? false) ? _socket!.id : null;

  static io.Socket _ensure() {
    final existing = _socket;
    if (existing != null) return existing;
    final s = io.io(
      AppConfig.baseUrl,
      io.OptionBuilder().setTransports(["websocket"]).enableReconnection().setReconnectionDelayMax(10000).disableAutoConnect().build(),
    );
    s.onConnect((_) {
      _join();
      // after a drop, anything may have changed while we were offline
      if (_connectedOnce) notifyLedgerChanged();
      _connectedOnce = true;
    });
    s.on("company:changed", (data) {
      if (data is! Map) return;
      if (data["companyId"]?.toString() != _companyId) return;
      final topics = data["topics"];
      notifyLedgerChanged(topics is List ? topics.map((t) => t.toString()) : null);
    });
    s.connect();
    _socket = s;
    return s;
  }

  static void _join() {
    final s = _socket;
    if (s == null || !s.connected || _companyId == null || _userId == null) return;
    s.emit("join", {"companyId": _companyId, "userId": _userId});
  }

  /// Listen to this company (replaces any previous one).
  static void watch(String companyId, String userId) {
    _companyId = companyId;
    _userId = userId;
    final s = _ensure();
    if (s.connected) _join();
  }

  /// Stop listening when the company screen closes.
  static void stop(String companyId) {
    if (_companyId != companyId) return;
    _socket?.emit("leave", {"companyId": companyId});
    _companyId = null;
  }
}
