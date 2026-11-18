import 'dart:math' as math;

import 'package:budget/colors.dart';
import 'package:budget/pages/futureProjection/projectionCharts.dart';
import 'package:budget/pages/futureProjection/projectionControls.dart';
import 'package:budget/struct/futureProjection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class ProjectionDashboard extends StatefulWidget {
  const ProjectionDashboard(
      {super.key,
      required this.startMonth,
      required this.history,
      required this.hasHistory,
      required this.schedules,
      required this.investments,
      required this.annualReserve,
      required this.openingBalance,
      required this.money,
      required this.filters,
      required this.onFilters,
      required this.onScenario,
      required this.onClear});
  final DateTime startMonth;
  final ProjectionHistory history;
  final bool hasHistory;
  final List<ProjectionSchedule> schedules;
  final List<ProjectionInvestment> investments;
  final double annualReserve;
  final double openingBalance;
  final String Function(double) money;
  final ProjectionFilters filters;
  final VoidCallback onFilters, onScenario, onClear;

  @override
  State<ProjectionDashboard> createState() => _ProjectionDashboardState();
}

class _ProjectionDashboardState extends State<ProjectionDashboard> {
  int _index = 0;
  int _span = 12;
  ProjectionMetric _metric = ProjectionMetric.total;
  late int _window;
  late List<ProjectedMonth> _months;
  ProjectedMonth? _prior;

  DateTime _date(int i) =>
      DateTime(widget.startMonth.year, widget.startMonth.month + i);
  DateTime get _last => DateTime(widget.startMonth.year + 50, 12);
  int _offset(DateTime d) =>
      (d.year - widget.startMonth.year) * 12 +
      d.month -
      widget.startMonth.month;
  int get _first => math.min(
      _index ~/ _span * _span, math.max(0, _offset(_last) + 1 - _span));
  int get _selected => _index - _window;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(ProjectionDashboard old) {
    super.didUpdateWidget(old);
    if (old.startMonth != widget.startMonth ||
        old.history != widget.history ||
        old.schedules != widget.schedules ||
        old.investments != widget.investments ||
        old.annualReserve != widget.annualReserve) _refresh();
  }

  void _refresh() {
    _window = _first;
    final includePrior = _window > 0;
    final rows = projectMonths(
        startMonth: widget.startMonth,
        firstVisibleMonth: _date(_window - (includePrior ? 1 : 0)),
        monthCount: math.min(_span, _offset(_last) + 1 - _window) +
            (includePrior ? 1 : 0),
        history: widget.history,
        schedules: widget.schedules,
        investments: widget.investments,
        annualReserve: widget.annualReserve);
    _prior = includePrior ? rows.first : null;
    _months = includePrior ? rows.sublist(1) : rows;
  }

  void _select(int index) {
    if (index == _index || index < 0 || index > _offset(_last)) return;
    setState(() {
      _index = index;
      if (_window != _first) _refresh();
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showProjectionSheet<DateTime>(
        context,
        ProjectionMonthPicker(
            initial: _date(_index), first: widget.startMonth, last: _last));
    if (mounted && picked != null) _select(_offset(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final month = _months[_selected];
    final previous = _selected == 0 ? _prior : _months[_selected - 1];
    final current = _metric.value(month, widget.openingBalance);
    final before = previous == null
        ? (_metric == ProjectionMetric.portfolio ? 0.0 : widget.openingBalance)
        : _metric.value(previous, widget.openingBalance);
    final delta = current - before;
    final incomeColor = getColor(context, 'incomeAmount');
    final expenseColor = getColor(context, 'expenseAmount');
    final monthLabel = DateFormat.yMMMM(locale).format(month.date);
    final money = widget.money;
    final count = widget.filters.activeCount;

    final trend = Container(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                    scheme.primary.withOpacity(.15), scheme.surface),
                Color.alphaBlend(
                    scheme.primary.withOpacity(.045), scheme.surface),
              ])),
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PopupMenuButton<ProjectionMetric>(
          key: const ValueKey('projection-metric'),
          tooltip: 'projection-choose-metric'.tr(),
          initialValue: _metric,
          onSelected: (m) => setState(() => _metric = m),
          itemBuilder: (_) => [
            for (final item in ProjectionMetric.values)
              CheckedPopupMenuItem(
                  value: item,
                  checked: item == _metric,
                  child: Text(item.label))
          ],
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.show_chart_rounded, color: scheme.primary, size: 20),
                const SizedBox(width: 7),
                Flexible(
                    child: Text(_metric.label,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700))),
                const SizedBox(width: 2),
                const Icon(Icons.expand_more_rounded, size: 19),
              ])),
        ),
        Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(money(current),
                    key: const ValueKey('projection-hero-value'),
                    style: theme.textTheme.displaySmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.2,
                        height: 1.12)))),
        Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 3,
            children: [
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: scheme.primary.withOpacity(.10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        delta < -.005
                            ? Icons.south_east_rounded
                            : delta > .005
                                ? Icons.north_east_rounded
                                : Icons.east_rounded,
                        size: 13,
                        color: scheme.primary),
                    const SizedBox(width: 3),
                    Text((delta > .005 ? '+' : '') + money(delta),
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold)),
                  ])),
              Text('projection-vs-last'.tr(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ]),
        const SizedBox(height: 18),
        ProjectionTrendChart(
            months: _months,
            selected: _selected,
            metric: _metric,
            opening: widget.openingBalance,
            money: money,
            onSelect: (i) => _select(_window + i)),
        const SizedBox(height: 13),
        Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
                color: scheme.surface.withOpacity(.8),
                borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              for (final span in [6, 12, 36, 60])
                Expanded(
                    child: Semantics(
                        button: true,
                        selected: span == _span,
                        child: Material(
                            color: span == _span
                                ? scheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () {
                                  if (span != _span)
                                    setState(() {
                                      _span = span;
                                      _refresh();
                                    });
                                },
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 2),
                                    child: Center(
                                        child: Text(
                                            ('projection-span-' +
                                                    span.toString())
                                                .tr(),
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: span == _span
                                                        ? scheme.onPrimary
                                                        : scheme
                                                            .onSurfaceVariant)))))))),
            ])),
      ]),
    );

    final schedule = _Panel(
        icon: Icons.event_note_rounded,
        title: 'projection-due'.tr(),
        aside: Text(month.payments.length.toString(),
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
        children: [
          if (month.payments.isEmpty)
            Text('future-projection-empty-scheduled'.tr(),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
          for (var i = 0; i < month.payments.length; i++) ...[
            if (i > 0) const Divider(height: 16),
            Row(children: [
              Container(
                  width: 43,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(.08),
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    Text(DateFormat.d(locale).format(month.payments[i].date),
                        style: theme.textTheme.titleMedium?.copyWith(
                            height: 1.05, fontWeight: FontWeight.bold)),
                    Text(DateFormat.MMM(locale).format(month.payments[i].date),
                        style: theme.textTheme.labelSmall),
                  ])),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(month.payments[i].name,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600))),
              const SizedBox(width: 6),
              Flexible(
                  child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(money(month.payments[i].amount),
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700))))),
            ]),
          ],
        ]);

    final flow = _Panel(
        icon: Icons.bar_chart_rounded,
        title: 'projection-flows'.tr(),
        aside: Text(DateFormat.yMMM(locale).format(month.date),
            style: theme.textTheme.labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        children: [
          Row(children: [
            Expanded(
                child: _FlowTotal('projection-in'.tr(), money(month.income),
                    incomeColor, Icons.south_west_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: _FlowTotal('projection-out'.tr(), money(month.expenses),
                    expenseColor, Icons.north_east_rounded)),
          ]),
          const SizedBox(height: 16),
          ProjectionFlowChart(
              months: _months,
              selected: _selected,
              incomeColor: incomeColor,
              expenseColor: expenseColor,
              money: money,
              onSelect: (i) => _select(_window + i)),
          const Divider(height: 24),
          _AmountRow(
              'projection-contingency'.tr(), money(month.monthlyReserve)),
          _AmountRow(
              'projection-deposits'.tr(), money(month.monthlyContribution)),
          _AmountRow('projection-net-flow'.tr(), money(month.cashFlow),
              emphasis: true),
        ]);

    final balances = _Panel(
        icon: Icons.account_balance_wallet_outlined,
        title: 'projection-balances'.tr(),
        children: [
          _AmountRow('projection-opening'.tr(), money(widget.openingBalance)),
          _AmountRow(
              'projection-cash-change'.tr(), money(month.cumulativeCashFlow)),
          _AmountRow('projection-metric-cash'.tr(),
              money(widget.openingBalance + month.cumulativeCashFlow),
              emphasis: true),
          if (month.investments.isNotEmpty) ...[
            const Divider(height: 20),
            for (final item in month.investments)
              _AmountRow(item.plan.name, money(item.value)),
            _AmountRow('projection-contributed'.tr(),
                money(month.investmentValue - month.investmentGain)),
            _AmountRow('projection-return'.tr(), money(month.investmentGain)),
            _AmountRow('projection-metric-portfolio'.tr(),
                money(month.investmentValue),
                emphasis: true),
          ],
        ]);

    return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
              spacing: 8,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                    onPressed: widget.onFilters,
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    style: count == 0
                        ? null
                        : OutlinedButton.styleFrom(
                            backgroundColor: scheme.secondaryContainer),
                    label: Text('filters'.tr() +
                        (count == 0 ? '' : ' · ' + count.toString()))),
                OutlinedButton.icon(
                    onPressed: widget.onScenario,
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: Text('projection-scenario'.tr())),
                if (count > 0)
                  TextButton(
                      onPressed: widget.onClear,
                      child: Text('projection-clear'.tr())),
              ]),
          const SizedBox(height: 7),
          Row(children: [
            IconButton(
                tooltip: 'future-projection-previous-month'.tr(),
                onPressed: _index > 0 ? () => _select(_index - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded)),
            Expanded(
                child: Center(
                    child: TextButton(
              key: const ValueKey('projection-month'),
              onPressed: _pickMonth,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                    child: Text(
                        toBeginningOfSentenceCase(monthLabel) ?? monthLabel,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                        textAlign: TextAlign.center)),
                const SizedBox(width: 5),
                Icon(Icons.keyboard_arrow_down_rounded,
                    color: scheme.onSurfaceVariant, size: 19),
              ]),
            ))),
            IconButton(
                tooltip: 'future-projection-next-month'.tr(),
                onPressed:
                    _index < _offset(_last) ? () => _select(_index + 1) : null,
                icon: const Icon(Icons.chevron_right_rounded)),
          ]),
          const SizedBox(height: 9),
          if (!widget.hasHistory &&
              widget.filters.source != ProjectionSource.scheduled)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('future-projection-empty-history'.tr(),
                          style: theme.textTheme.bodySmall)),
                ])),
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth >= 720) {
              return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        flex: 6,
                        child: Column(children: [
                          trend,
                          const SizedBox(height: 12),
                          flow
                        ])),
                    const SizedBox(width: 12),
                    Expanded(
                        flex: 5,
                        child: Column(children: [
                          schedule,
                          const SizedBox(height: 12),
                          balances
                        ])),
                  ]);
            }
            return Column(children: [
              trend,
              const SizedBox(height: 12),
              schedule,
              const SizedBox(height: 12),
              flow,
              const SizedBox(height: 12),
              balances
            ]);
          }),
        ]));
  }
}

class _Panel extends StatelessWidget {
  const _Panel(
      {required this.icon,
      required this.title,
      required this.children,
      this.aside});
  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? aside;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant.withOpacity(.58)),
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: scheme.primary, size: 21),
            const SizedBox(width: 8),
            Expanded(
                child: Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800))),
            if (aside != null) aside!,
          ]),
          const SizedBox(height: 12),
          ...children,
        ]));
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.name, this.value, {this.emphasis = false});
  final String name, value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = emphasis
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)
        : theme.textTheme.bodyMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(flex: 3, child: Text(name, style: label)),
          const SizedBox(width: 8),
          Flexible(
              flex: 2,
              child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(value,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: emphasis
                                  ? FontWeight.w800
                                  : FontWeight.w600))))),
        ]));
  }
}

class _FlowTotal extends StatelessWidget {
  const _FlowTotal(this.label, this.amount, this.color, this.icon);
  final String label, amount;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
        padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
        decoration: BoxDecoration(
            color: color.withOpacity(.09),
            borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Flexible(child: Text(label, style: theme.textTheme.labelMedium))
          ]),
          const SizedBox(height: 3),
          FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(amount,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800))),
        ]));
  }
}
