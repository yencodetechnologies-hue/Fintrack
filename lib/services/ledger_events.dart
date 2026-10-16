import 'package:flutter/widgets.dart';

/// Fires when the server sends a ledger change event.
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
