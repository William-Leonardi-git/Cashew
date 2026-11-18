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

  Iterable<ProjectedPayment> paymentsBetween(DateTime start, DateTime end)
      sync* {
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

    for (var index = math.max(0, earliestIndex); ; index++) {
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

  final double income;
  final double expenses;
  final List<ProjectedPayment> payments;
  final double monthlyReserve;
  final double monthlyContribution;
  final List<ProjectedInvestment> investments;
  final double investmentValue;
  final double investmentGain;
  final double cumulativeCashFlow;

  double get cashFlow => income - expenses - monthlyReserve - monthlyContribution;
}

ProjectedMonth projectMonth({
  required DateTime startMonth,
  required DateTime targetMonth,
  required ProjectionHistory history,
  required Iterable<ProjectionSchedule> schedules,
  required Iterable<ProjectionInvestment> investments,
  required double annualReserve,
}) {
  final start = DateTime(startMonth.year, startMonth.month);
  final target = DateTime(targetMonth.year, targetMonth.month);
  if (target.isBefore(start)) {
    throw ArgumentError.value(targetMonth, 'targetMonth');
  }
  final end = DateTime(target.year, target.month + 1);
  final monthCount = _monthsBetween(start, target) + 1;
  final monthlyReserve = annualReserve / 12;

  final payments = <ProjectedPayment>[];
  var scheduledCashFlow = 0.0;
  var income = history.monthlyIncome;
  var expenses = history.monthlyExpenses;
  for (final schedule in schedules) {
    for (final payment in schedule.paymentsBetween(start, end)) {
      scheduledCashFlow += payment.amount;
      if (payment.date.isBefore(target)) continue;

      payments.add(payment);
      if (payment.amount > 0) {
        income += payment.amount;
      } else {
        expenses -= payment.amount;
      }
    }
  }
  payments.sort((left, right) => left.date.compareTo(right.date));

  final positions = <ProjectedInvestment>[];
  var monthlyContribution = 0.0;
  var investmentValue = 0.0;
  for (final plan in investments) {
    final monthlyGrowth = math.pow(1 + plan.annualReturn / 100, 1 / 12);
    var value = 0.0;
    for (var month = 0; month < monthCount; month++) {
      value = value * monthlyGrowth + plan.monthlyContribution;
    }
    monthlyContribution += plan.monthlyContribution;
    investmentValue += value;
    positions.add((plan: plan, value: value));
  }

  final monthlyBaseline = history.monthlyIncome -
      history.monthlyExpenses -
      monthlyReserve -
      monthlyContribution;
  return ProjectedMonth(
    income: income,
    expenses: expenses,
    payments: List.unmodifiable(payments),
    monthlyReserve: monthlyReserve,
    monthlyContribution: monthlyContribution,
    investments: List.unmodifiable(positions),
    investmentValue: investmentValue,
    investmentGain: investmentValue - monthlyContribution * monthCount,
    cumulativeCashFlow: monthlyBaseline * monthCount + scheduledCashFlow,
  );
}

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
