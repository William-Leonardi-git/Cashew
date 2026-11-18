import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart' show convertToMoney;
import 'package:budget/pages/futureProjection/projectionControls.dart';
import 'package:budget/pages/futureProjection/projectionDashboard.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/futureProjection.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _settingsKey = 'futureProjection';

class FutureProjectionPage extends StatefulWidget {
  const FutureProjectionPage({super.key});

  @override
  State<FutureProjectionPage> createState() => _FutureProjectionPageState();
}

class _FutureProjectionPageState extends State<FutureProjectionPage> {
  late final DateTime _today = DateUtils.dateOnly(DateTime.now());
  late final DateTime _startMonth = DateTime(_today.year, _today.month + 1);
  late ProjectionScenario _scenario;
  var _filters = const ProjectionFilters();
  late Stream<List<(Transaction, String)>> _transactions;
  late Stream<Map<String, double>> _balances;

  @override
  void initState() {
    super.initState();
    _scenario =
        ProjectionScenario.restore(appStateSettings[_settingsKey], _today);
    _watchHistory();
    _balances = database.watchProjectionOpeningBalances(_startMonth);
  }

  void _watchHistory() {
    final end = _scenario.history.end;
    _transactions = database.watchFutureProjectionTransactions(
        historyStart: _scenario.history.start,
        historyEndExclusive: DateTime(end.year, end.month, end.day + 1));
  }

  Future<void> _editScenario(AllWallets wallets) async {
    final result = await showProjectionSheet<ProjectionScenario>(
        context,
        ProjectionScenarioSheet(
            initial: _scenario,
            today: _today,
            currency: getCurrencyString(wallets),
            money: (value) =>
                convertToMoney(wallets, value, allDecimals: true)));
    if (!mounted || result == null) return;
    setState(() {
      final changed = _scenario.history != result.history;
      _scenario = result;
      if (changed) _watchHistory();
    });
    await updateSettings(_settingsKey, result.toSettings(),
        updateGlobalState: false);
  }

  Future<void> _editFilters(AllWallets wallets) async {
    final categories = await database.getAllCategories();
    if (!mounted) return;
    final result = await showProjectionSheet<ProjectionFilters>(
        context,
        ProjectionFilterSheet(
            initial: _filters,
            wallets: wallets.list,
            categories: categories.where((c) => c.categoryPk != '0').toList()));
    if (mounted && result != null) setState(() => _filters = result);
  }

  Widget _dashboard(List<(Transaction, String)> rows,
      Map<String, double> balances, AllWallets wallets) {
    final amounts = <double>[];
    final schedules = <ProjectionSchedule>[];
    final rates = <String, double>{};
    double convert(double value, String wallet) =>
        value *
        rates.putIfAbsent(
            wallet, () => amountRatioToPrimaryCurrencyGivenPk(wallets, wallet));
    for (final (t, title) in rows) {
      if (!_filters.includes(t)) continue;
      final value = convert(t.amount, t.walletFk);
      if (!value.isFinite) continue;
      if (t.paid) {
        amounts.add(value);
      } else {
        schedules.add(ProjectionSchedule(
            payment: (
              name: title.isEmpty ? 'future-projection-untitled'.tr() : title,
              amount: value,
              date: DateUtils.dateOnly(t.dateCreated)
            ),
            frequency: t.type == TransactionSpecialType.upcoming
                ? ProjectionFrequency.once
                : _frequency(t.reoccurrence),
            interval: t.periodLength ?? 0,
            endDate: t.endDate));
      }
    }
    final opening = balances.entries
        .where((e) => _filters.includesAccount(e.key))
        .map((e) => convert(e.value, e.key))
        .where((v) => v.isFinite)
        .fold(0.0, (double a, double b) => a + b);
    return ProjectionDashboard(
      startMonth: _startMonth,
      openingBalance: opening,
      history: ProjectionHistory(
          start: _scenario.history.start,
          endInclusive: _scenario.history.end,
          amounts: amounts),
      hasHistory: amounts.isNotEmpty,
      schedules: schedules,
      investments: _filters.investments ? _scenario.investments : const [],
      annualReserve: _filters.reserve ? _scenario.annualReserve : 0,
      money: (v) => convertToMoney(wallets, v, allDecimals: true),
      filters: _filters,
      onFilters: () => _editFilters(wallets),
      onScenario: () => _editScenario(wallets),
      onClear: () => setState(() => _filters = const ProjectionFilters()),
    );
  }

  Widget _error() => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Text('future-projection-load-error'.tr()),
        TextButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text('projection-retry'.tr()),
            onPressed: () => setState(() {
                  _watchHistory();
                  _balances =
                      database.watchProjectionOpeningBalances(_startMonth);
                })),
      ]));

  @override
  Widget build(BuildContext context) {
    final wallets = context.watch<AllWallets>();
    return PageFramework(
        expandedHeight: 112,
        title: 'future-projection'.tr(),
        horizontalPaddingConstrained: true,
        listWidgets: [
          StreamBuilder<Map<String, double>>(
              stream: _balances,
              builder: (context, balances) {
                if (balances.hasError) return _error();
                return StreamBuilder<List<(Transaction, String)>>(
                    stream: _transactions,
                    builder: (context, transactions) {
                      if (transactions.hasError) return _error();
                      if (!balances.hasData || !transactions.hasData)
                        return const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()));
                      return _dashboard(
                          transactions.data!, balances.data!, wallets);
                    });
              }),
        ]);
  }
}

ProjectionFrequency _frequency(BudgetReoccurence? recurrence) =>
    switch (recurrence) {
      BudgetReoccurence.daily => ProjectionFrequency.daily,
      BudgetReoccurence.weekly => ProjectionFrequency.weekly,
      BudgetReoccurence.monthly => ProjectionFrequency.monthly,
      BudgetReoccurence.yearly => ProjectionFrequency.yearly,
      BudgetReoccurence.custom || null => ProjectionFrequency.once,
    };
