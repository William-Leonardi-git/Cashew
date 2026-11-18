import 'dart:convert';
import 'dart:io';

import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/pages/futureProjection/projectionControls.dart';
import 'package:budget/pages/futureProjection/projectionCharts.dart';
import 'package:budget/pages/futureProjection/projectionDashboard.dart';
import 'package:budget/struct/futureProjection.dart';
import 'package:budget/struct/settings.dart';
import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final _first = DateTime(2029);
final _scenario = ProjectionScenario(
  history: DateTimeRange(start: DateTime(2028, 1), end: DateTime(2028, 12, 31)),
  annualReserve: 1200,
  investments: [
    (name: 'Piano mensile', monthlyContribution: 200, annualReturn: 6)
  ],
);
final _insurance = ProjectionSchedule(payment: (
  name: 'Assicurazione auto',
  amount: -800,
  date: DateTime(2028, 7, 20)
), frequency: ProjectionFrequency.yearly, interval: 1);
final _numbers =
    NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);
String _money(double v) => _numbers.format(v);

ThemeData projectionTestTheme(Brightness brightness) => ThemeData(
      useMaterial3: true,
      fontFamily: 'Avenir',
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff68865a), brightness: brightness),
      extensions: const [
        AppColors(colors: {
          'incomeAmount': Color(0xff59a849),
          'expenseAmount': Color(0xffca5a5a)
        })
      ],
    );

Widget projectionTestApp(Widget child,
        {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      locale: const Locale('it'),
      supportedLocales: const [Locale('it')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: projectionTestTheme(brightness),
      home: Scaffold(
          appBar: AppBar(title: const Text('Proiezione futura')),
          body: SingleChildScrollView(child: child)),
    );

Future<void> loadProjectionTestLocale() async {
  await initializeDateFormatting('it');
  Localization.load(const Locale('it'),
      translations: Translations(jsonDecode(
          File('assets/translations/generated/it.json').readAsStringSync())));
  appStateSettings['colorTintCategoryIcon'] = false;
}

Widget projectionTestDashboard({bool empty = false}) => ProjectionDashboard(
      startMonth: _first,
      history: ProjectionHistory(
          start: _scenario.history.start,
          endInclusive: _scenario.history.end,
          amounts: empty ? [] : [24000, -12000]),
      hasHistory: !empty,
      schedules: empty ? [] : [_insurance],
      investments: empty ? [] : _scenario.investments,
      openingBalance: empty ? 0 : 5000,
      annualReserve: empty ? 0 : 1200,
      money: _money,
      filters: const ProjectionFilters(),
      onClear: () {},
      onFilters: () {},
      onScenario: () {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadProjectionTestLocale);

  testWidgets(
      'month picker, arrows and chart select the same dated payments and totals',
      (t) async {
    await t.pumpWidget(projectionTestApp(projectionTestDashboard()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('projection-month')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(OutlinedButton, 'giu'));
    await t.pumpAndSettle();
    expect(find.text('Giugno 2029'), findsOneWidget);
    expect(find.text('Assicurazione auto'), findsNothing);
    await t.tap(find.byTooltip('Mese successivo'));
    await t.pumpAndSettle();
    expect(find.text('Luglio 2029'), findsOneWidget);
    expect(find.text('Assicurazione auto'), findsOneWidget);
    expect(find.text(_money(-800)), findsOneWidget);
    final bars = find.byKey(
        ValueKey('projection-bars-' + DateTime(2029, 6).toIso8601String()));
    await t.ensureVisible(bars);
    await t.tap(bars);
    await t.pumpAndSettle();
    expect(find.text('Giugno 2029'), findsOneWidget);
    expect(find.text('Assicurazione auto'), findsNothing);
    final trend = find.byKey(const ValueKey('projection-trend-plot'));
    await t.ensureVisible(trend);
    final rect = t.getRect(trend);
    await t.tapAt(Offset(rect.left + rect.width * 6 / 11, rect.center.dy));
    await t.pumpAndSettle();
    expect(find.text('Luglio 2029'), findsOneWidget);
    expect(find.text('Assicurazione auto'), findsOneWidget);
    await t.ensureVisible(find.byTooltip('Mese precedente'));
    await t.tap(find.byTooltip('Mese precedente'));
    await t.pumpAndSettle();
    expect(find.text('Giugno 2029'), findsOneWidget);
  });

  testWidgets(
      'changing time span preserves the month and the metric changes the balance',
      (t) async {
    await t.pumpWidget(projectionTestApp(projectionTestDashboard()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('projection-hero-value')), findsOneWidget);
    expect(
        t
            .widget<Text>(find.byKey(const ValueKey('projection-hero-value')))
            .data,
        _money(5900));
    await t.tap(find.text('5 anni'));
    await t.pumpAndSettle();
    expect(find.text('Gennaio 2029'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('projection-metric')));
    await t.pumpAndSettle();
    final metricOption = find.widgetWithText(
        CheckedPopupMenuItem<ProjectionMetric>, 'Valore investito');
    await t.ensureVisible(metricOption);
    await t.tap(metricOption);
    await t.pumpAndSettle();
    expect(
        t
            .widget<Text>(find.byKey(const ValueKey('projection-hero-value')))
            .data,
        _money(200));
    final plot = find.byKey(const ValueKey('projection-trend-plot'));
    await t.dragFrom(t.getCenter(plot), const Offset(100, 0));
    await t.pumpAndSettle();
    expect(find.text('Gennaio 2029'), findsNothing);
  });

  testWidgets(
      'a flat empty projection works on a narrow dark screen and on a tablet',
      (t) async {
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    for (final size in [const Size(320, 660), const Size(1024, 768)]) {
      t.view.physicalSize = size;
      await t.pumpWidget(projectionTestApp(projectionTestDashboard(empty: true),
          brightness: Brightness.dark));
      await t.pumpAndSettle();
      expect(find.text('Nessuna transazione ordinaria nel periodo scelto'),
          findsOneWidget);
      expect(find.text('Nessuna scadenza nel mese'), findsOneWidget);
      expect(t.takeException(), isNull);
    }
  });

  testWidgets(
      'scenario accepts comma decimals, updates the reserve and preserves existing plans',
      (t) async {
    ProjectionScenario? result;
    await t.pumpWidget(projectionTestApp(Builder(
        builder: (context) => TextButton(
            onPressed: () async {
              result = await showProjectionSheet<ProjectionScenario>(
                  context,
                  ProjectionScenarioSheet(
                      initial: _scenario,
                      today: DateTime(2029, 1, 1),
                      currency: '€',
                      money: _money));
            },
            child: const Text('Apri')))));
    await t.pumpAndSettle();
    await t.tap(find.text('Apri'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), '600,00');
    await t.pumpAndSettle();
    expect(find.text(_money(50) + ' accantonati ogni mese'), findsOneWidget);
    await t.ensureVisible(find.text('Aggiungi investimento'));
    await t.tap(find.text('Aggiungi investimento'));
    await t.pumpAndSettle();
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextFormField));
    await t.enterText(fields.at(0), 'Secondo PAC');
    await t.enterText(fields.at(1), '75,50');
    await t.enterText(fields.at(2), '3,5');
    await t.tap(find.widgetWithText(FilledButton, 'Salva'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Applica'));
    await t.pumpAndSettle();
    expect(result!.annualReserve, 600);
    expect(result!.investments.last.monthlyContribution, 75.5);
    expect(result!.investments.last.annualReturn, 3.5);
    expect(
        ProjectionScenario.restore(result!.toSettings(), DateTime(2029))
            .investments,
        result!.investments);
    expect(result!.investments.first.name, 'Piano mensile');
  });

  testWidgets(
      'filter sheet applies account, category and movement type and clears all',
      (t) async {
    var filters = const ProjectionFilters();
    final wallet = TransactionWallet(
        walletPk: 'w',
        name: 'Banca',
        dateCreated: _first,
        order: 0,
        decimals: 2);
    final category = TransactionCategory(
        categoryPk: 'c',
        name: 'Auto',
        dateCreated: _first,
        order: 0,
        income: false);
    await t.pumpWidget(projectionTestApp(Builder(
        builder: (context) => TextButton(
            onPressed: () async {
              final value = await showProjectionSheet<ProjectionFilters>(
                  context,
                  ProjectionFilterSheet(
                      initial: filters,
                      wallets: [wallet],
                      categories: [category]));
              if (value != null) filters = value;
            },
            child: const Text('Apri')))));
    await t.pumpAndSettle();
    await t.tap(find.text('Apri'));
    await t.pumpAndSettle();
    for (final label in ['Banca', 'Auto', 'Solo scadenze']) {
      await t.ensureVisible(find.text(label));
      await t.tap(find.text(label));
      await t.pumpAndSettle();
    }
    await t.tap(find.widgetWithText(FilledButton, 'Applica'));
    await t.pumpAndSettle();
    expect(filters.accounts, {'w'});
    expect(filters.categories, {'c'});
    expect(filters.source, ProjectionSource.scheduled);
    expect(
        filters.includes(_transaction('1', -800, _first, paid: false)), isTrue);
    expect(filters.includes(_transaction('2', -800, _first)), isFalse);
    expect(
        filters.includes(
            _transaction('3', -800, _first, paid: false, wallet: 'other')),
        isFalse);
    await t.tap(find.text('Apri'));
    await t.pumpAndSettle();
    await t.tap(find.text('Azzera filtri'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Applica'));
    await t.pumpAndSettle();
    expect(filters.activeCount, 0);
  });

  test(
      'opening cash follows posted balances by account and time, and due payments stay in the forecast',
      () async {
    final db = FinanceDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    for (final t in [
      _transaction('1', 5000, DateTime(2028, 11), category: '0'),
      _transaction('2', -200, DateTime(2028, 12)),
      _transaction('3', 650, DateTime(2028, 12), wallet: 'savings'),
      _transaction('4', -800, DateTime(2029, 7),
          paid: false, type: TransactionSpecialType.subscription),
      _transaction('5', 400, DateTime(2029, 1, 5)),
    ]) {
      await db.into(db.transactions).insert(t);
    }
    expect(await db.watchProjectionOpeningBalances(_first).first,
        {'w': 4800.0, 'savings': 650.0});
    final projected = await db
        .watchFutureProjectionTransactions(
            historyStart: DateTime(2028), historyEndExclusive: _first)
        .first;
    expect(projected.map((r) => r.$1.transactionPk),
        unorderedEquals(['2', '3', '4']));
  });
}

Transaction _transaction(String id, double amount, DateTime date,
        {bool paid = true,
        String wallet = 'w',
        String category = 'c',
        TransactionSpecialType? type}) =>
    Transaction(
        transactionPk: id,
        name: 'Movimento',
        note: '',
        categoryFk: category,
        walletFk: wallet,
        amount: amount,
        dateCreated: date,
        income: amount > 0,
        skipPaid: false,
        paid: paid,
        type: type);
