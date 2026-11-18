import 'dart:math' as math;

enum ProjectionFrequency { once, daily, weekly, monthly, yearly }

typedef ProjectedPayment = ({String name, double amount, DateTime date});
typedef ProjectionInvestment = ({
  String name,
  double monthlyContribution,
  double annualReturn,
});
typedef ProjectedInvestment = ({
  ProjectionInvestment plan,
  double value,
});

class ProjectionSchedule {
  const ProjectionSchedule({
    required this.payment,
    required this.frequency,
    required this.interval,
    this.endDate,
  });

  final ProjectedPayment payment;
  final ProjectionFrequency frequency;
  final int interval;
  final DateTime? endDate;

  Iterable<ProjectedPayment> paymentsBetween(
      DateTime start, DateTime end) sync* {
    final anchor = payment.date;
    final lastDay = endDate;
    final afterLastDay = lastDay == null
        ? end
        : DateTime(lastDay.year, lastDay.month, lastDay.day + 1);
    final limit = afterLastDay.isBefore(end) ? afterLastDay : end;
    if (frequency == ProjectionFrequency.once || interval <= 0) {
      if (!anchor.isBefore(start) && anchor.isBefore(limit)) yield payment;
      return;
    }
    if (!anchor.isBefore(limit) || !start.isBefore(limit)) return;

    final daysApart = _calendarDaysBetween(anchor, start);
    final monthsApart = _monthsBetween(anchor, start);
    final earliestIndex = switch (frequency) {
      ProjectionFrequency.daily => daysApart ~/ interval,
      ProjectionFrequency.weekly => daysApart ~/ (7 * interval),
      ProjectionFrequency.monthly => monthsApart ~/ interval,
      ProjectionFrequency.yearly => monthsApart ~/ (12 * interval),
      ProjectionFrequency.once => 0,
    };

    for (var index = math.max(0, earliestIndex);; index++) {
      final step = interval * index;
      final date = switch (frequency) {
        ProjectionFrequency.daily =>
          DateTime(anchor.year, anchor.month, anchor.day + step),
        ProjectionFrequency.weekly =>
          DateTime(anchor.year, anchor.month, anchor.day + step * 7),
        ProjectionFrequency.monthly => _addCalendarMonths(anchor, step),
        ProjectionFrequency.yearly => _addCalendarMonths(anchor, step * 12),
        ProjectionFrequency.once => anchor,
      };
      if (!date.isBefore(limit)) return;
      if (!date.isBefore(start)) {
        yield (name: payment.name, amount: payment.amount, date: date);
      }
    }
  }
}

class ProjectionHistory {
  ProjectionHistory({
    required DateTime start,
    required DateTime endInclusive,
    required List<double> amounts,
  }) : months = _observedMonths(start, endInclusive) {
    for (final amount in amounts) {
      if (amount > 0) {
        _income += amount;
      } else {
        _expenses -= amount;
      }
    }
  }

  final double months;
  double _income = 0;
  double _expenses = 0;

  double get monthlyIncome => _income / months;
  double get monthlyExpenses => _expenses / months;
}

class ProjectedMonth {
  const ProjectedMonth({
    required this.date,
    required this.income,
    required this.expenses,
    required this.payments,
    required this.monthlyReserve,
    required this.monthlyContribution,
    required this.investments,
    required this.investmentValue,
    required this.investmentGain,
    required this.cumulativeCashFlow,
  });

  final DateTime date;
  final double income;
  final double expenses;
  final List<ProjectedPayment> payments;
  final double monthlyReserve;
  final double monthlyContribution;
  final List<ProjectedInvestment> investments;
  final double investmentValue;
  final double investmentGain;
  final double cumulativeCashFlow;

  double get cashFlow =>
      income - expenses - monthlyReserve - monthlyContribution;
}

List<ProjectedMonth> projectMonths({
  required DateTime startMonth,
  required DateTime firstVisibleMonth,
  required int monthCount,
  required ProjectionHistory history,
  required Iterable<ProjectionSchedule> schedules,
  required List<ProjectionInvestment> investments,
  required double annualReserve,
}) {
  final start = DateTime(startMonth.year, startMonth.month);
  final first = DateTime(firstVisibleMonth.year, firstVisibleMonth.month);
  final elapsed = _monthsBetween(start, first);
  if (elapsed < 0) throw ArgumentError.value(firstVisibleMonth);
  if (monthCount < 1) throw ArgumentError.value(monthCount);

  final end = DateTime(first.year, first.month + monthCount);
  final buckets = List.generate(monthCount, (_) => <ProjectedPayment>[]);
  var priorScheduledNet = 0.0;
  for (final schedule in schedules) {
    for (final payment in schedule.paymentsBetween(start, end)) {
      final index = _monthsBetween(first, payment.date);
      if (index < 0) {
        priorScheduledNet += payment.amount;
      } else {
        buckets[index].add(payment);
      }
    }
  }

  final growth = [
    for (final plan in investments)
      math.pow(1 + plan.annualReturn / 100, 1 / 12).toDouble(),
  ];
  final balances = List.filled(investments.length, 0.0);
  void investForMonth() {
    for (var i = 0; i < investments.length; i++) {
      balances[i] =
          balances[i] * growth[i] + investments[i].monthlyContribution;
    }
  }

  final contribution = investments.fold<double>(
      0, (sum, plan) => sum + plan.monthlyContribution);
  final reserve = annualReserve / 12;
  final ordinaryNet = history.monthlyIncome - history.monthlyExpenses;
  var cumulative =
      elapsed * (ordinaryNet - reserve - contribution) + priorScheduledNet;
  for (var i = 0; i < elapsed; i++) {
    investForMonth();
  }

  final result = <ProjectedMonth>[];
  for (var i = 0; i < monthCount; i++) {
    final payments = buckets[i]
      ..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate == 0 ? a.name.compareTo(b.name) : byDate;
      });
    var income = history.monthlyIncome;
    var expenses = history.monthlyExpenses;
    for (final payment in payments) {
      if (payment.amount >= 0) {
        income += payment.amount;
      } else {
        expenses -= payment.amount;
      }
    }
    cumulative += income - expenses - reserve - contribution;
    investForMonth();
    final portfolio = balances.fold<double>(0, (sum, value) => sum + value);
    result.add(ProjectedMonth(
      date: DateTime(first.year, first.month + i),
      income: income,
      expenses: expenses,
      payments: List.unmodifiable(payments),
      monthlyReserve: reserve,
      monthlyContribution: contribution,
      investments: [
        for (var j = 0; j < investments.length; j++)
          (plan: investments[j], value: balances[j]),
      ],
      investmentValue: portfolio,
      investmentGain: portfolio - contribution * (elapsed + i + 1),
      cumulativeCashFlow: cumulative,
    ));
  }
  return result;
}

ProjectedMonth projectMonth({
  required DateTime startMonth,
  required DateTime targetMonth,
  required ProjectionHistory history,
  required Iterable<ProjectionSchedule> schedules,
  required Iterable<ProjectionInvestment> investments,
  required double annualReserve,
}) =>
    projectMonths(
      startMonth: startMonth,
      firstVisibleMonth: targetMonth,
      monthCount: 1,
      history: history,
      schedules: schedules,
      investments: investments.toList(),
      annualReserve: annualReserve,
    ).single;

DateTime _addCalendarMonths(DateTime anchor, int months) {
  final month = DateTime(anchor.year, anchor.month + months);
  final lastDay = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, math.min(anchor.day, lastDay));
}

int _calendarDaysBetween(DateTime from, DateTime to) {
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  return end.difference(start).inDays;
}

int _monthsBetween(DateTime from, DateTime to) =>
    (to.year - from.year) * 12 + to.month - from.month;

double _observedMonths(DateTime start, DateTime endInclusive) {
  if (endInclusive.isBefore(start)) {
    throw ArgumentError.value(endInclusive, 'endInclusive');
  }
  final end =
      DateTime(endInclusive.year, endInclusive.month, endInclusive.day + 1);

  var cursor = DateTime(start.year, start.month, start.day);
  var months = 0.0;
  while (cursor.isBefore(end)) {
    final nextMonth = DateTime(cursor.year, cursor.month + 1);
    final daysInMonth = DateTime(cursor.year, cursor.month + 1, 0).day;
    final coveredUntil = nextMonth.isBefore(end) ? nextMonth : end;
    months += _calendarDaysBetween(cursor, coveredUntil) / daysInMonth;
    cursor = coveredUntil;
  }
  return months;
}
