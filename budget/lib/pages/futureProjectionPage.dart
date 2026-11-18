import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart' show convertToMoney;
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/futureProjection.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _settingsKey = 'futureProjection';
const _maximumAmount = 1000000000000.0;
const _maximumReturn = 1000.0;

class FutureProjectionPage extends StatefulWidget {
  const FutureProjectionPage({super.key});

  @override
  State<FutureProjectionPage> createState() => _FutureProjectionPageState();
}

class _FutureProjectionPageState extends State<FutureProjectionPage> {
  late final DateTime _today;
  late final DateTime _startMonth;
  late final DateTime _lastMonth;
  late DateTime _targetMonth;
  late DateTimeRange _history;
  late Stream<List<(Transaction, String)>> _transactions;
  final _investments = <ProjectionInvestment>[];
  double _annualReserve = 0;

  @override
  void initState() {
    super.initState();
    _today = DateUtils.dateOnly(DateTime.now());
    _startMonth = DateTime(_today.year, _today.month + 1);
    _lastMonth = DateTime(_startMonth.year + 50, 12);
    _targetMonth = _startMonth;
    _history = DateTimeRange(
      start: DateTime(_today.year - 1, _today.month),
      end: DateTime(_today.year, _today.month, 0),
    );
    _restoreSettings();
    _watchTransactions();
  }

  void _restoreSettings() {
    final saved = appStateSettings[_settingsKey];
    if (saved is! Map) return;

    final start = _storedDate(saved['start']);
    final end = _storedDate(saved['end']);
    if (start != null &&
        end != null &&
        !start.isBefore(DateTime(1900)) &&
        !end.isBefore(start) &&
        !end.isAfter(_today)) {
      _history = DateTimeRange(start: start, end: end);
    }

    _annualReserve = _readNumber(saved['annualReserve'], 0, _maximumAmount) ?? 0;
    final plans = saved['investments'];
    if (plans is! List) return;
    for (final plan in plans.whereType<Map>()) {
      final name = plan['name'];
      final contribution = _readNumber(plan['contribution'], 0, _maximumAmount);
      final rate = _readNumber(plan['rate'], -100, _maximumReturn);
      if (name is String && contribution != null && rate != null) {
        _investments.add(
          (name: name, monthlyContribution: contribution, annualReturn: rate),
        );
      }
    }
  }

  void _watchTransactions() {
    final end = _history.end;
    _transactions = database.watchFutureProjectionTransactions(
      historyStart: _history.start,
      historyEndExclusive: DateTime(end.year, end.month, end.day + 1),
    );
  }

  Future<void> _save() async {
    await updateSettings(
      _settingsKey,
      {
        'start': _history.start.toIso8601String(),
        'end': _history.end.toIso8601String(),
        'annualReserve': _annualReserve,
        'investments': [
          for (final plan in _investments)
            {
              'name': plan.name,
              'contribution': plan.monthlyContribution,
              'rate': plan.annualReturn,
            },
        ],
      },
      updateGlobalState: false,
    );
  }

  Future<void> _pickHistory() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: _today,
      initialDateRange: _history,
    );
    if (!mounted || range == null) return;
    setState(() {
      _history = range;
      _watchTransactions();
    });
    await _save();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetMonth,
      firstDate: _startMonth,
      lastDate: DateTime(_lastMonth.year + 1, 1, 0),
      helpText: 'future-projection-go-to-month'.tr(),
    );
    if (!mounted || picked == null) return;
    setState(() => _targetMonth = DateTime(picked.year, picked.month));
  }

  void _moveMonth(int months) {
    setState(() {
      _targetMonth = DateTime(_targetMonth.year, _targetMonth.month + months);
    });
  }

  Future<void> _editReserve() async {
    var amount = _annualReserve;
    final result = await _showEditor<double>(
      title: 'future-projection-annual-reserve'.tr(),
      fields: [
        _numberField(
          label: 'future-projection-annual-reserve'.tr(),
          initialValue: amount,
          onSaved: (value) => amount = value,
        ),
      ],
      result: () => amount,
    );
    if (!mounted || result == null) return;
    setState(() => _annualReserve = result);
    await _save();
  }

  Future<void> _editInvestment([int? index]) async {
    final plan = index == null ? null : _investments[index];
    var name = plan?.name ?? '';
    var contribution = plan?.monthlyContribution ?? 0.0;
    var rate = plan?.annualReturn ?? 0.0;
    final result = await _showEditor<ProjectionInvestment>(
      title: (plan == null ? 'future-projection-add-investment' : 'edit').tr(),
      fields: [
        TextFormField(
          initialValue: name,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 80,
          decoration: InputDecoration(labelText: 'name'.tr()),
          validator: (value) => (value ?? '').trim().isEmpty
              ? 'future-projection-name-required'.tr()
              : null,
          onSaved: (value) => name = (value ?? '').trim(),
        ),
        _numberField(
          label: 'future-projection-monthly-contribution'.tr(),
          initialValue: contribution,
          onSaved: (value) => contribution = value,
        ),
        _numberField(
          label: 'future-projection-expected-return'.tr(),
          initialValue: rate,
          minimum: -100,
          maximum: _maximumReturn,
          suffix: '%',
          onSaved: (value) => rate = value,
        ),
      ],
      result: () => (
        name: name,
        monthlyContribution: contribution,
        annualReturn: rate,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        _investments.add(result);
      } else {
        _investments[index] = result;
      }
    });
    await _save();
  }

  Future<T?> _showEditor<T>({
    required String title,
    required List<Widget> fields,
    required T Function() result,
  }) {
    final formKey = GlobalKey<FormState>();
    return showDialog<T>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        scrollable: true,
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: fields),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              final form = formKey.currentState!;
              if (!form.validate()) return;
              form.save();
              Navigator.pop(dialogContext, result());
            },
            child: Text('save'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required String label,
    required double initialValue,
    required ValueChanged<double> onSaved,
    double minimum = 0,
    double maximum = _maximumAmount,
    String? suffix,
  }) {
    double? parse(String? value) {
      final number = double.tryParse(value?.trim().replaceAll(',', '.') ?? '');
      return _readNumber(number, minimum, maximum);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        initialValue: initialValue.toString(),
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: minimum < 0,
        ),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        validator: (value) => parse(value) == null
            ? 'future-projection-invalid-number'.tr()
            : null,
        onSaved: (value) => onSaved(parse(value)!),
      ),
    );
  }

  Widget _buildForecast(
    List<(Transaction, String)> transactions,
    AllWallets wallets,
    DateFormat shortDate,
    String firstMonth,
  ) {
    final amounts = <double>[];
    final schedules = <ProjectionSchedule>[];
    for (final (transaction, title) in transactions) {
      final amount = transaction.amount *
          amountRatioToPrimaryCurrencyGivenPk(wallets, transaction.walletFk);
      if (!amount.isFinite) continue;
      if (transaction.paid) {
        amounts.add(amount);
        continue;
      }
      final frequency = transaction.type == TransactionSpecialType.upcoming
          ? ProjectionFrequency.once
          : _projectionFrequency(transaction.reoccurrence);
      schedules.add(ProjectionSchedule(
        payment: (
          name: title.isEmpty ? 'future-projection-untitled'.tr() : title,
          amount: amount,
          date: DateUtils.dateOnly(transaction.dateCreated),
        ),
        frequency: frequency,
        interval: transaction.periodLength ?? 0,
        endDate: transaction.endDate,
      ));
    }

    final projection = projectMonth(
      history: ProjectionHistory(
        start: _history.start,
        endInclusive: _history.end,
        amounts: amounts,
      ),
      startMonth: _startMonth,
      targetMonth: _targetMonth,
      schedules: schedules,
      investments: _investments,
      annualReserve: _annualReserve,
    );

    String money(double value) =>
        convertToMoney(wallets, value, allDecimals: true);
    Widget total(String label, double value, {String? subtitle}) => ListTile(
          title: Text(label.tr()),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: Text(money(value)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (amounts.isEmpty)
          ListTile(title: Text('future-projection-empty-history'.tr())),
        Card(
          child: Column(
            children: [
              total('future-projection-income', projection.income),
              total('future-projection-expenses', projection.expenses),
              total(
                'future-projection-monthly-reserve',
                projection.monthlyReserve,
              ),
              total(
                'future-projection-monthly-contribution',
                projection.monthlyContribution,
              ),
              const Divider(height: 1),
              total('future-projection-monthly-cash', projection.cashFlow),
              total(
                'future-projection-total-cash',
                projection.cumulativeCashFlow,
                subtitle: 'future-projection-since'.tr(
                  namedArgs: {'month': firstMonth},
                ),
              ),
            ],
          ),
        ),
        if (projection.investments.isNotEmpty)
          Card(
            child: Column(
              children: [
                total(
                  'future-projection-investment-value',
                  projection.investmentValue,
                ),
                total(
                  'future-projection-investment-gain',
                  projection.investmentGain,
                ),
                if (projection.investments.length > 1)
                  for (final position in projection.investments)
                    ListTile(
                      title: Text(position.plan.name),
                      trailing: Text(money(position.value)),
                    ),
              ],
            ),
          ),
        Card(
          child: Column(
            children: [
              ListTile(title: Text('future-projection-scheduled'.tr())),
              if (projection.payments.isEmpty)
                ListTile(title: Text('future-projection-empty-scheduled'.tr())),
              for (final payment in projection.payments)
                ListTile(
                  title: Text(payment.name),
                  subtitle: Text(shortDate.format(payment.date)),
                  trailing: Text(money(payment.amount)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallets = context.watch<AllWallets>();
    final locale = context.locale.toString();
    final shortDate = DateFormat.yMMMd(locale);
    final monthFormat = DateFormat.yMMMM(locale);
    final numberFormat = NumberFormat.decimalPattern(locale);
    String money(double value) =>
        convertToMoney(wallets, value, allDecimals: true);

    return PageFramework(
      title: 'future-projection'.tr(),
      horizontalPaddingConstrained: true,
      listWidgets: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: Text('future-projection-history'.tr()),
            subtitle: Text(
              shortDate.format(_history.start) +
                  ' – ' +
                  shortDate.format(_history.end),
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _pickHistory,
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: Text('future-projection-annual-reserve'.tr()),
            subtitle: Text(money(_annualReserve)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _editReserve,
          ),
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.trending_up),
                title: Text('future-projection-investments'.tr()),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'future-projection-add-investment'.tr(),
                  onPressed: _editInvestment,
                ),
              ),
              for (var index = 0; index < _investments.length; index++)
                ListTile(
                  title: Text(_investments[index].name),
                  subtitle: Text(
                    'future-projection-investment-terms'.tr(
                      namedArgs: {
                        'amount': money(_investments[index].monthlyContribution),
                        'rate':
                            numberFormat.format(_investments[index].annualReturn),
                      },
                    ),
                  ),
                  onTap: () => _editInvestment(index),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'delete'.tr(),
                    onPressed: () async {
                      setState(() => _investments.removeAt(index));
                      await _save();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              onPressed: _targetMonth.isAfter(_startMonth)
                  ? () => _moveMonth(-1)
                  : null,
              tooltip: 'future-projection-previous-month'.tr(),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: TextButton(
                onPressed: _pickMonth,
                child: Text(monthFormat.format(_targetMonth)),
              ),
            ),
            IconButton(
              onPressed: _targetMonth.isBefore(_lastMonth)
                  ? () => _moveMonth(1)
                  : null,
              tooltip: 'future-projection-next-month'.tr(),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        StreamBuilder<List<(Transaction, String)>>(
          stream: _transactions,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListTile(title: Text('future-projection-load-error'.tr()));
            }
            if (snapshot.connectionState == ConnectionState.waiting ||
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildForecast(
              snapshot.data!,
              wallets,
              shortDate,
              monthFormat.format(_startMonth),
            );
          },
        ),
      ],
    );
  }
}

DateTime? _storedDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

double? _readNumber(Object? value, double minimum, double maximum) {
  if (value is! num || !value.isFinite || value < minimum || value > maximum) {
    return null;
  }
  return value.toDouble();
}

ProjectionFrequency _projectionFrequency(BudgetReoccurence? recurrence) {
  return switch (recurrence) {
    BudgetReoccurence.daily => ProjectionFrequency.daily,
    BudgetReoccurence.weekly => ProjectionFrequency.weekly,
    BudgetReoccurence.monthly => ProjectionFrequency.monthly,
    BudgetReoccurence.yearly => ProjectionFrequency.yearly,
    BudgetReoccurence.custom || null => ProjectionFrequency.once,
  };
}
