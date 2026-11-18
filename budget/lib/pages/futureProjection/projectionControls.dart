import 'package:budget/database/tables.dart';
import 'package:budget/struct/futureProjection.dart';
import 'package:budget/widgets/categoryIcon.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

const _amountLimit = 1000000000000.0;
const _rateLimit = 1000.0;

class ProjectionScenario {
  const ProjectionScenario({
    required this.history,
    required this.annualReserve,
    required this.investments,
  });

  final DateTimeRange history;
  final double annualReserve;
  final List<ProjectionInvestment> investments;

  factory ProjectionScenario.restore(Object? saved, DateTime today) {
    var history = DateTimeRange(
      start: DateTime(today.year - 1, today.month),
      end: DateTime(today.year, today.month, 0),
    );
    var reserve = 0.0;
    final plans = <ProjectionInvestment>[];
    if (saved is Map) {
      final start = DateTime.tryParse(saved['start']?.toString() ?? '');
      final end = DateTime.tryParse(saved['end']?.toString() ?? '');
      if (start != null &&
          end != null &&
          !start.isBefore(DateTime(1900)) &&
          !end.isBefore(start) &&
          !end.isAfter(today)) {
        history = DateTimeRange(start: start, end: end);
      }
      reserve = _number(saved['annualReserve'], 0, _amountLimit) ?? 0;
      final entries = saved['investments'];
      if (entries is List) {
        for (final plan in entries.whereType<Map>()) {
          final name = plan['name'];
          final amount = _number(plan['contribution'], 0, _amountLimit);
          final rate = _number(plan['rate'], -100, _rateLimit);
          if (name is String && amount != null && rate != null) {
            plans.add(
                (name: name, monthlyContribution: amount, annualReturn: rate));
          }
        }
      }
    }
    return ProjectionScenario(
        history: history, annualReserve: reserve, investments: plans);
  }

  Map<String, Object> toSettings() => {
        'start': history.start.toIso8601String(),
        'end': history.end.toIso8601String(),
        'annualReserve': annualReserve,
        'investments': [
          for (final plan in investments)
            {
              'name': plan.name,
              'contribution': plan.monthlyContribution,
              'rate': plan.annualReturn
            },
        ],
      };
}

double? _number(Object? value, double minimum, double maximum) {
  if (value is! num || !value.isFinite || value < minimum || value > maximum)
    return null;
  return value.toDouble();
}

double? _input(String? text,
        {double minimum = 0, double maximum = _amountLimit}) =>
    _number(double.tryParse((text ?? '').trim().replaceAll(',', '.')), minimum,
        maximum);

enum ProjectionSource { all, ordinary, scheduled }

class ProjectionFilters {
  const ProjectionFilters({
    this.accounts = const {},
    this.categories = const {},
    this.source = ProjectionSource.all,
    this.investments = true,
    this.reserve = true,
  });

  final Set<String> accounts;
  final Set<String> categories;
  final ProjectionSource source;
  final bool investments;
  final bool reserve;

  int get activeCount =>
      accounts.length +
      categories.length +
      (source == ProjectionSource.all ? 0 : 1) +
      (investments ? 0 : 1) +
      (reserve ? 0 : 1);

  bool includesAccount(String pk) => accounts.isEmpty || accounts.contains(pk);

  bool includes(Transaction transaction) =>
      includesAccount(transaction.walletFk) &&
      (categories.isEmpty || categories.contains(transaction.categoryFk)) &&
      (source == ProjectionSource.all ||
          (transaction.paid
              ? source == ProjectionSource.ordinary
              : source == ProjectionSource.scheduled));
}

Future<T?> showProjectionSheet<T>(BuildContext context, Widget sheet) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    constraints: const BoxConstraints(maxWidth: 600),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => sheet,
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody(
      {required this.title, required this.children, this.onApply, this.action});

  final String title;
  final List<Widget> children;
  final VoidCallback? onApply;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: (media.size.height - media.viewInsets.bottom) * .79),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(22, 0, 14, 8),
            child: Row(children: [
              Expanded(
                  child: Text(title,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800))),
              if (action != null) action!,
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children),
            ),
          ),
          if (onApply != null)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child:
                    FilledButton(onPressed: onApply, child: Text('apply'.tr())),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
      );
}

class ProjectionFilterSheet extends StatefulWidget {
  const ProjectionFilterSheet(
      {super.key,
      required this.initial,
      required this.wallets,
      required this.categories});
  final ProjectionFilters initial;
  final List<TransactionWallet> wallets;
  final List<TransactionCategory> categories;

  @override
  State<ProjectionFilterSheet> createState() => _ProjectionFilterSheetState();
}

class _ProjectionFilterSheetState extends State<ProjectionFilterSheet> {
  late final _accounts = {...widget.initial.accounts};
  late final _categories = {...widget.initial.categories};
  late var _source = widget.initial.source;
  late var _investments = widget.initial.investments;
  late var _reserve = widget.initial.reserve;
  String _query = '';

  void _toggle(Set<String> selection, String id) => setState(() {
        if (!selection.remove(id)) selection.add(id);
      });

  void _reset() => setState(() {
        _accounts.clear();
        _categories.clear();
        _source = ProjectionSource.all;
        _investments = true;
        _reserve = true;
      });

  @override
  Widget build(BuildContext context) {
    final shown =
        widget.categories.where((c) => c.name.toLowerCase().contains(_query));
    return _SheetBody(
      title: 'filters'.tr(),
      action:
          TextButton(onPressed: _reset, child: Text('projection-clear'.tr())),
      onApply: () => Navigator.pop(
          context,
          ProjectionFilters(
            accounts: Set.unmodifiable(_accounts),
            categories: Set.unmodifiable(_categories),
            source: _source,
            investments: _investments,
            reserve: _reserve,
          )),
      children: [
        _Section('projection-accounts'.tr()),
        Wrap(spacing: 7, runSpacing: 3, children: [
          ChoiceChip(
              label: Text('projection-all-accounts'.tr()),
              selected: _accounts.isEmpty,
              onSelected: (_) => setState(_accounts.clear)),
          for (final wallet in widget.wallets)
            FilterChip(
                label: Text(wallet.name),
                selected: _accounts.contains(wallet.walletPk),
                onSelected: (_) => _toggle(_accounts, wallet.walletPk)),
        ]),
        _Section('categories'.tr()),
        if (widget.categories.length > 9)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'search'.tr()),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase())),
          ),
        Wrap(spacing: 7, runSpacing: 3, children: [
          ChoiceChip(
              label: Text('projection-all-categories'.tr()),
              selected: _categories.isEmpty,
              onSelected: (_) => setState(_categories.clear)),
          for (final category in shown)
            FilterChip(
              avatar: CategoryIcon(
                  category: category,
                  size: 16,
                  sizePadding: 4,
                  borderRadius: 6,
                  margin: EdgeInsetsDirectional.zero,
                  canEditByLongPress: false),
              label: Text(category.name),
              selected: _categories.contains(category.categoryPk),
              onSelected: (_) => _toggle(_categories, category.categoryPk),
            ),
        ]),
        _Section('projection-movement-source'.tr()),
        Wrap(spacing: 7, runSpacing: 3, children: [
          for (final source in ProjectionSource.values)
            ChoiceChip(
                label: Text(('projection-source-' + source.name).tr()),
                selected: _source == source,
                onSelected: (_) => setState(() => _source = source)),
        ]),
        _Section('projection-scenario'.tr()),
        SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('future-projection-investments'.tr()),
            value: _investments,
            onChanged: (v) => setState(() => _investments = v)),
        SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text('future-projection-monthly-reserve'.tr()),
            value: _reserve,
            onChanged: (v) => setState(() => _reserve = v)),
        Text('projection-filter-scope'.tr(),
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class ProjectionScenarioSheet extends StatefulWidget {
  const ProjectionScenarioSheet(
      {super.key,
      required this.initial,
      required this.today,
      required this.money,
      required this.currency});
  final ProjectionScenario initial;
  final DateTime today;
  final String Function(double) money;
  final String currency;

  @override
  State<ProjectionScenarioSheet> createState() =>
      _ProjectionScenarioSheetState();
}

class _ProjectionScenarioSheetState extends State<ProjectionScenarioSheet> {
  late DateTimeRange _range = widget.initial.history;
  late final _plans = [...widget.initial.investments];
  final _form = GlobalKey<FormState>();
  late double _reserve = widget.initial.annualReserve;

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
        context: context,
        initialDateRange: _range,
        firstDate: DateTime(1900),
        lastDate: widget.today);
    if (mounted && range != null) setState(() => _range = range);
  }

  Future<void> _editPlan([int? index]) async {
    final plan = index == null ? null : _plans[index];
    var name = plan?.name ?? '';
    var amount = plan?.monthlyContribution ?? 0.0;
    var rate = plan?.annualReturn ?? 0.0;
    final form = GlobalKey<FormState>();
    final fmt = NumberFormat(
        '0.############', Localizations.localeOf(context).toString());
    final result = await showDialog<ProjectionInvestment>(
        context: context,
        builder: (dialog) => AlertDialog(
              scrollable: true,
              title: Text((plan == null
                      ? 'future-projection-add-investment'
                      : 'projection-edit-plan')
                  .tr()),
              content: Form(
                  key: form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        initialValue: name,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 80,
                        decoration: InputDecoration(labelText: 'name'.tr()),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'future-projection-name-required'.tr()
                            : null,
                        onSaved: (v) => name = v!.trim()),
                    TextFormField(
                        initialValue: fmt.format(amount),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText:
                                'future-projection-monthly-contribution'.tr(),
                            suffixText: widget.currency),
                        validator: (v) => _input(v) == null
                            ? 'future-projection-invalid-number'.tr()
                            : null,
                        onSaved: (v) => amount = _input(v)!),
                    TextFormField(
                        initialValue: fmt.format(rate),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: InputDecoration(
                            labelText: 'future-projection-expected-return'.tr(),
                            suffixText: '%'),
                        validator: (v) =>
                            _input(v, minimum: -100, maximum: _rateLimit) ==
                                    null
                                ? 'future-projection-invalid-number'.tr()
                                : null,
                        onSaved: (v) => rate =
                            _input(v, minimum: -100, maximum: _rateLimit)!),
                  ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: Text('cancel'.tr())),
                FilledButton(
                    onPressed: () {
                      if (!form.currentState!.validate()) return;
                      form.currentState!.save();
                      Navigator.pop(dialog, (
                        name: name,
                        monthlyContribution: amount,
                        annualReturn: rate
                      ));
                    },
                    child: Text('save'.tr())),
              ],
            ));
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        _plans.add(result);
      } else {
        _plans[index] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final dates = DateFormat.yMMMd(locale);
    final numeric = NumberFormat('0.############', locale);
    return _SheetBody(
      title: 'projection-scenario'.tr(),
      onApply: () {
        if (!_form.currentState!.validate()) return;
        Navigator.pop(
            context,
            ProjectionScenario(
                history: _range,
                annualReserve: _reserve,
                investments: List.unmodifiable(_plans)));
      },
      children: [
        _Section('future-projection-history'.tr()),
        OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range_rounded),
            label: Text(
                dates.format(_range.start) + ' – ' + dates.format(_range.end))),
        Text('projection-history-help'.tr(),
            style: Theme.of(context).textTheme.bodySmall),
        _Section('future-projection-annual-reserve'.tr()),
        Form(
            key: _form,
            child: TextFormField(
              initialValue: numeric.format(_reserve),
              decoration: InputDecoration(
                  suffixText: widget.currency,
                  prefixIcon: const Icon(Icons.savings_outlined)),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => _input(v) == null
                  ? 'future-projection-invalid-number'.tr()
                  : null,
              onChanged: (v) {
                final number = _input(v);
                if (number != null) setState(() => _reserve = number);
              },
            )),
        const SizedBox(height: 6),
        Text(
            'projection-reserve-help'
                .tr(namedArgs: {'amount': widget.money(_reserve / 12)}),
            style: Theme.of(context).textTheme.bodySmall),
        _Section('future-projection-investments'.tr()),
        for (var i = 0; i < _plans.length; i++)
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.trending_up_rounded),
              title: Text(_plans[i].name),
              subtitle:
                  Text('future-projection-investment-terms'.tr(namedArgs: {
                'amount': widget.money(_plans[i].monthlyContribution),
                'rate': numeric.format(_plans[i].annualReturn),
              })),
              onTap: () => _editPlan(i),
              trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'delete'.tr(),
                  onPressed: () => setState(() => _plans.removeAt(i)))),
        Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
                onPressed: _editPlan,
                icon: const Icon(Icons.add),
                label: Text('future-projection-add-investment'.tr()))),
        Text('projection-investment-help'.tr(),
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class ProjectionMonthPicker extends StatefulWidget {
  const ProjectionMonthPicker(
      {super.key,
      required this.initial,
      required this.first,
      required this.last});
  final DateTime initial;
  final DateTime first;
  final DateTime last;

  @override
  State<ProjectionMonthPicker> createState() => _ProjectionMonthPickerState();
}

class _ProjectionMonthPickerState extends State<ProjectionMonthPicker> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.MMM(Localizations.localeOf(context).toString());
    return _SheetBody(title: 'future-projection-go-to-month'.tr(), children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton(
            tooltip: 'projection-previous-year'.tr(),
            onPressed: _year > widget.first.year
                ? () => setState(() => _year--)
                : null,
            icon: const Icon(Icons.chevron_left_rounded)),
        DropdownButton<int>(
            value: _year,
            menuMaxHeight: 320,
            underline: const SizedBox.shrink(),
            items: [
              for (var y = widget.first.year; y <= widget.last.year; y++)
                DropdownMenuItem(value: y, child: Text(y.toString()))
            ],
            onChanged: (y) {
              if (y != null) setState(() => _year = y);
            }),
        IconButton(
            tooltip: 'projection-next-year'.tr(),
            onPressed:
                _year < widget.last.year ? () => setState(() => _year++) : null,
            icon: const Icon(Icons.chevron_right_rounded)),
      ]),
      GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              mainAxisExtent: 48),
          children: [
            for (var m = 1; m <= 12; m++)
              Builder(builder: (context) {
                final date = DateTime(_year, m);
                final enabled =
                    !date.isBefore(widget.first) && !date.isAfter(widget.last);
                final selected = date == widget.initial;
                return OutlinedButton(
                  style: selected
                      ? OutlinedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer)
                      : null,
                  onPressed:
                      enabled ? () => Navigator.pop(context, date) : null,
                  child: Text(fmt.format(date)),
                );
              })
          ]),
    ]);
  }
}
