import 'package:budget/struct/futureProjection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final history = ProjectionHistory(
    start: DateTime(2026, 1, 1),
    endInclusive: DateTime(2026, 12, 31),
    amounts: [24000, -12000],
  );

  test('annual insurance is due in July 2029', () {
    final insurance = ProjectionSchedule(
      payment: (
        name: 'Assicurazione auto',
        amount: -800.0,
        date: DateTime(2027, 7, 20),
      ),
      frequency: ProjectionFrequency.yearly,
      interval: 1,
    );

    ProjectedMonth project(int month) => projectMonth(
          startMonth: DateTime(2027, 1),
          targetMonth: DateTime(2029, month),
          history: history,
          schedules: [insurance],
          investments: [],
          annualReserve: 1200,
        );

    final june = project(6);
    final july = project(7);
    expect(june.payments, isEmpty);
    expect(june.expenses, 1000);
    expect(june.cashFlow, 900);
    expect(july.payments.single.name, 'Assicurazione auto');
    expect(july.payments.single.date, DateTime(2029, 7, 20));
    expect(july.payments.single.amount, -800);
    expect(july.expenses, 1800);
    expect(july.cashFlow, 100);
    expect(july.cumulativeCashFlow - june.cumulativeCashFlow, 100);
  });

  test('month-end recurrence observes leap days and the end date', () {
    final schedule = ProjectionSchedule(
      payment: (name: 'Rent', amount: -400.0, date: DateTime(2028, 1, 31)),
      frequency: ProjectionFrequency.monthly,
      interval: 1,
      endDate: DateTime(2028, 3, 31),
    );
    expect(
      schedule
          .paymentsBetween(DateTime(2028, 2), DateTime(2028, 5))
          .map((payment) => payment.date),
      [DateTime(2028, 2, 29), DateTime(2028, 3, 31)],
    );
  });

  test('a planned one-time payment is included only once', () {
    final schedule = ProjectionSchedule(
      payment: (name: 'Repair', amount: -200.0, date: DateTime(2028, 2, 2)),
      frequency: ProjectionFrequency.once,
      interval: 0,
    );
    expect(
      schedule.paymentsBetween(DateTime(2028, 1), DateTime(2028, 8)).length,
      1,
    );
    expect(
      schedule.paymentsBetween(DateTime(2028, 3), DateTime(2028, 8)),
      isEmpty,
    );
  });

  test('investment return compounds on prior contributions', () {
    final projection = projectMonth(
      startMonth: DateTime(2027, 1),
      targetMonth: DateTime(2027, 2),
      history: history,
      schedules: [],
      investments: [
        (name: 'Growth', monthlyContribution: 100.0, annualReturn: 12.0),
        (name: 'Cash', monthlyContribution: 200.0, annualReturn: 0.0),
      ],
      annualReserve: 1200,
    );
    expect(projection.monthlyReserve, 100);
    expect(projection.monthlyContribution, 300);
    expect(projection.investmentValue, closeTo(600.94888, 0.00001));
    expect(projection.investmentGain, closeTo(0.94888, 0.00001));
    expect(projection.cashFlow, 600);
  });

  test(
      'moving the chart window preserves earlier cash flows and investment growth',
      () {
    final start = DateTime(2027);
    final schedule = ProjectionSchedule(
      payment: (name: 'Insurance', amount: -800, date: DateTime(2027, 7, 20)),
      frequency: ProjectionFrequency.yearly,
      interval: 1,
    );
    List<ProjectedMonth> window(DateTime first, int length) => projectMonths(
          startMonth: start,
          firstVisibleMonth: first,
          monthCount: length,
          history: history,
          schedules: [schedule],
          investments: [
            (name: 'Plan', monthlyContribution: 100, annualReturn: 6)
          ],
          annualReserve: 1200,
        );
    final full = window(start, 60);
    final short = window(DateTime(2029, 6), 6);
    for (var i = 0; i < short.length; i++) {
      final expected = full[29 + i];
      expect(short[i].date, expected.date);
      expect(short[i].payments, expected.payments);
      expect(short[i].investmentValue, closeTo(expected.investmentValue, 1e-8));
      expect(short[i].cumulativeCashFlow,
          closeTo(expected.cumulativeCashFlow, 1e-8));
    }
    expect(short[0].cashFlow, 800);
    expect(short[1].cashFlow, 0);
    expect(short[1].payments.single.date, DateTime(2029, 7, 20));
  });

  test('the historical period counts the covered part of each month', () {
    final partial = ProjectionHistory(
      start: DateTime(2028, 2, 15),
      endInclusive: DateTime(2028, 3, 31),
      amounts: [440, -110],
    );
    expect(partial.months, closeTo(1 + 15 / 29, 0.00001));
    expect(partial.monthlyIncome, closeTo(290, 0.00001));
    expect(partial.monthlyExpenses, closeTo(72.5, 0.00001));
  });
}
