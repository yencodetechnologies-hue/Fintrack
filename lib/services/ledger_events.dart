import 'package:flutter/widgets.dart';

/// Fires when ledger data changed: after this device's own actions, or when the server announces a change
/// (live connection, see ledger_live.dart).
final ValueNotifier<int> ledgerChanged = ValueNotifier<int>(0);

/// What the last change touched: expenses, balances, funds, vouchers, loans, members, company, permissions,
/// ledger. "*" means anything (this device's own actions, a reconnect).
Set<String> lastLedgerTopics = const {"*"};

void notifyLedgerChanged([Iterable<String>? topics]) {
  lastLedgerTopics = topics == null ? const {"*"} : topics.toSet();
  ledgerChanged.value++;
}

/// Reloads a screen whenever [ledgerChanged] fires for one of its [ledgerTopics]. Implement [onLedgerChanged]
/// with a quiet reload.
mixin LedgerAutoRefresh<T extends StatefulWidget> on State<T> {
  void onLedgerChanged();

  /// The kinds of data this screen shows; it ignores changes to anything else. Default: everything.
  Set<String> get ledgerTopics => const {"*"};

  @override
  void initState() {
    super.initState();
    ledgerChanged.addListener(_listener);
  }

  void _listener() {
    if (!mounted) return;
    final changed = lastLedgerTopics;
    if (changed.contains("*") || ledgerTopics.contains("*") || changed.any(ledgerTopics.contains)) onLedgerChanged();
  }

  @override
  void dispose() {
    ledgerChanged.removeListener(_listener);
    super.dispose();
  }
}
