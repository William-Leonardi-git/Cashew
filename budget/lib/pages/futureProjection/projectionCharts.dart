import 'dart:math' as math;

import 'package:budget/struct/futureProjection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

enum ProjectionMetric {
  total,
  cash,
  portfolio;

  String get label => ('projection-metric-' + name).tr();
  double value(ProjectedMonth month, double opening) => switch (this) {
        ProjectionMetric.total =>
          opening + month.cumulativeCashFlow + month.investmentValue,
        ProjectionMetric.cash => opening + month.cumulativeCashFlow,
        ProjectionMetric.portfolio => month.investmentValue,
      };
}

class _Scale {
  const _Scale(this.low, this.high);
  final double low;
  final double high;
  double get step => (high - low) / 2;

  factory _Scale.forValues(Iterable<double> values, {bool fromZero = false}) {
    final min = fromZero ? 0.0 : values.reduce(math.min);
    final max = values.reduce(math.max);
    final width = max == min ? math.max(2.0, max.abs() * .12) : max - min;
    final low = fromZero ? 0.0 : min - width * .12;
    final high = max + width * .12;
    final rough = (high - low) / 3;
    final factor =
        math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final unit = [1, 2, 5, 10].firstWhere((n) => n * factor >= rough) * factor;
    return _Scale((low / unit).floor() * unit, (high / unit).ceil() * unit);
  }
}

class _Plot extends StatelessWidget {
  const _Plot(
      {required this.scale,
      required this.height,
      required this.child,
      required this.labels});
  final _Scale scale;
  final double height;
  final Widget child;
  final Widget labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final compact = NumberFormat.compact(locale: locale);
    final decimal = NumberFormat.decimalPattern(locale);
    String tick(double value) {
      final label = compact.format(value);
      return value.abs() >= 1000 && RegExp(r'^-?[0-9]{4,}$').hasMatch(label)
          ? decimal.format(value)
          : label;
    }

    final style = theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: 10,
        letterSpacing: .15);
    return DefaultTextStyle(
        style: style ?? const TextStyle(fontSize: 10),
        child: Column(children: [
          SizedBox(
              height: height,
              child: Row(children: [
                SizedBox(
                    width: 42,
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final value in [
                            scale.high,
                            scale.low + scale.step,
                            scale.low
                          ])
                            Flexible(
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(tick(value)))),
                        ])),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: child)),
              ])),
          Padding(
              padding: const EdgeInsetsDirectional.only(start: 42, top: 4),
              child: labels),
        ]));
  }
}

FlGridData _grid(BuildContext context, _Scale scale) => FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: scale.step,
      getDrawingHorizontalLine: (_) => FlLine(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(.14),
          strokeWidth: 1,
          dashArray: [3, 5]),
    );

class ProjectionTrendChart extends StatelessWidget {
  const ProjectionTrendChart(
      {super.key,
      required this.months,
      required this.selected,
      required this.metric,
      required this.opening,
      required this.onSelect,
      required this.money});
  final List<ProjectedMonth> months;
  final int selected;
  final ProjectionMetric metric;
  final double opening;
  final ValueChanged<int> onSelect;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fmt =
        DateFormat('MMM yy', Localizations.localeOf(context).toString());
    final values = [for (final month in months) metric.value(month, opening)];
    final scale = _Scale.forValues(values);
    final color = scheme.primary;
    final last = values.length - 1;
    String description(int i) =>
        fmt.format(months[i].date) + ', ' + money(values[i]);
    return Semantics(
      slider: true,
      excludeSemantics: true,
      label: metric.label,
      value: description(selected),
      increasedValue: selected < last ? description(selected + 1) : null,
      decreasedValue: selected > 0 ? description(selected - 1) : null,
      onIncrease: selected < last ? () => onSelect(selected + 1) : null,
      onDecrease: selected > 0 ? () => onSelect(selected - 1) : null,
      child: _Plot(
          scale: scale,
          height: 129,
          labels: Stack(children: [
            for (final i in [0, last ~/ 2, last].toSet())
              Align(
                  alignment: Alignment(last == 0 ? -1 : (2 * i / last) - 1, 0),
                  child: Text(fmt.format(months[i].date))),
          ]),
          child: LayoutBuilder(builder: (context, box) {
            void pick(double x) =>
                onSelect((x / box.maxWidth * last).round().clamp(0, last));
            return GestureDetector(
              key: const ValueKey('projection-trend-plot'),
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTapUp: (details) => pick(details.localPosition.dx),
              onHorizontalDragStart: (details) =>
                  pick(details.localPosition.dx),
              onHorizontalDragUpdate: (details) =>
                  pick(details.localPosition.dx),
              child: IgnorePointer(
                  child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: math.max(1, last).toDouble(),
                        minY: scale.low,
                        baselineY: scale.low,
                        maxY: scale.high,
                        titlesData: const FlTitlesData(show: false),
                        gridData: _grid(context, scale),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        extraLinesData: ExtraLinesData(
                            extraLinesOnTop: false,
                            verticalLines: [
                              VerticalLine(
                                  x: selected.toDouble(),
                                  color: color.withOpacity(.5),
                                  strokeWidth: 1,
                                  dashArray: [3, 4])
                            ]),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (var i = 0; i <= last; i++)
                                FlSpot(i.toDouble(), values[i])
                            ],
                            color: color,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            isStrokeJoinRound: true,
                            belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      color.withOpacity(.22),
                                      color.withOpacity(.015)
                                    ])),
                            dotData: FlDotData(
                                checkToShowDot: (spot, _) =>
                                    spot.x.round() == selected,
                                getDotPainter: (_, __, ___, ____) =>
                                    FlDotCirclePainter(
                                        radius: 4.2,
                                        color: color,
                                        strokeWidth: 2,
                                        strokeColor: scheme.surface)),
                          )
                        ],
                      ),
                      duration: Duration.zero)),
            );
          })),
    );
  }
}

class ProjectionFlowChart extends StatelessWidget {
  const ProjectionFlowChart(
      {super.key,
      required this.months,
      required this.selected,
      required this.onSelect,
      required this.incomeColor,
      required this.expenseColor,
      required this.money});
  final List<ProjectedMonth> months;
  final int selected;
  final ValueChanged<int> onSelect;
  final Color incomeColor;
  final Color expenseColor;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final count = math.min(6, months.length);
    final start = (selected - count ~/ 2).clamp(0, months.length - count);
    final visible = months.sublist(start, start + count);
    final max = visible.map((m) => math.max(m.income, m.expenses));
    final scale = _Scale.forValues(max, fromZero: true);
    final locale = Localizations.localeOf(context).toString();
    final fmt = DateFormat.MMM(locale);
    final theme = Theme.of(context);
    return _Plot(
        scale: scale,
        height: 102,
        labels: Row(children: [
          for (var i = 0; i < count; i++)
            Expanded(
                child: Center(
                    child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(fmt.format(visible[i].date),
                            style: i + start == selected
                                ? TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface)
                                : null)))),
        ]),
        child: Stack(fit: StackFit.expand, children: [
          IgnorePointer(
              child: BarChart(
                  BarChartData(
                    minY: 0,
                    maxY: scale.high,
                    alignment: BarChartAlignment.spaceAround,
                    gridData: _grid(context, scale),
                    titlesData: const FlTitlesData(show: false),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(enabled: false),
                    barGroups: [
                      for (var i = 0; i < count; i++)
                        BarChartGroupData(x: i, barsSpace: 3, barRods: [
                          for (final bar in [
                            (visible[i].income, incomeColor),
                            (visible[i].expenses, expenseColor)
                          ])
                            BarChartRodData(
                                toY: bar.$1,
                                width: 7,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(3)),
                                color: bar.$2.withOpacity(
                                    start + i == selected ? 1 : .52)),
                        ]),
                    ],
                  ),
                  swapAnimationDuration: Duration.zero)),
          Row(children: [
            for (var i = 0; i < count; i++)
              Expanded(
                  child: Semantics(
                button: true,
                selected: start + i == selected,
                label: DateFormat.yMMMM(locale).format(visible[i].date) +
                    ', ' +
                    'future-projection-income'.tr() +
                    ' ' +
                    money(visible[i].income) +
                    ', ' +
                    'future-projection-expenses'.tr() +
                    ' ' +
                    money(visible[i].expenses),
                child: GestureDetector(
                    key: ValueKey(
                        'projection-bars-' + visible[i].date.toIso8601String()),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(start + i)),
              ))
          ]),
        ]));
  }
}
