import 'dart:async';
import 'package:flutter/widgets.dart';

/// Fires whenever ledger data may have changed (poll tick, push notification, or a local action).
final ValueNotifier<int> ledgerChanged = ValueNotifier<int>(0);

void notifyLedgerChanged() => ledgerChanged.value++;

/// Reloads a screen whenever [ledgerChanged] fires. Implement [onLedgerChanged] with a quiet reload.
mixin LedgerAutoRefresh<T extends StatefulWidget> on State<T> {
  void onLedgerChanged();

  @override
  void initState() {
    super.initState();
    ledgerChanged.addListener(_listener);
  }

  void _listener() {
    if (mounted) onLedgerChanged();
  }

  @override
  void dispose() {
    ledgerChanged.removeListener(_listener);
    super.dispose();
  }
}

/// Polls while a ledger screen is open; the home screen owns one of these.
class LedgerPoller {
  Timer? _timer;

  void start({Duration every = const Duration(seconds: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => notifyLedgerChanged());
  }

  void stop() => _timer?.cancel();
}
