import 'package:autointel_ai/app/app.dart';
import 'package:autointel_ai/app/providers.dart';
import 'package:autointel_ai/core/theme.dart';
import 'package:autointel_ai/data/mock_backend.dart';
import 'package:autointel_ai/data/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mock calls resolve through zero-length timers, so a bare pumpAndSettle can return early.
/// Pumps a fixed span instead (a busy spinner under a pushed route never "settles").
Future<void> settle(WidgetTester tester, {int ms = 800}) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration(milliseconds: ms ~/ 8));
  }
}

Future<void> pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.binding.setSurfaceSize(const Size(412, 915));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        mockBackendProvider.overrideWithValue(
          MockBackend(prefs, latency: Duration.zero),
        ),
        paymentGatewayProvider.overrideWith(
          (ref) => MockPaymentGateway(ref.watch(mockBackendProvider)),
        ),
      ],
      child: const AutoIntelApp(),
    ),
  );
  await settle(tester, ms: 2000);
}

/// Gate → pay ₹100 via the mock gateway → land on the main shell.
Future<void> completeFirstRecharge(WidgetTester tester) async {
  await tester.tap(find.text('Pay ₹100'));
  await settle(tester);
  await tester.tap(find.text('Simulate success'));
  await settle(tester);
  await tester.tap(find.text('Continue'));
  await settle(tester);
}

void main() {
  testWidgets('first launch shows the recharge gate, then unlocks the app', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Add money to get started'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);

    await tester.tap(find.text('Pay ₹100'));
    await settle(tester);
    await tester.tap(find.text('Simulate success'));
    await settle(tester);
    expect(find.text('Payment successful'), findsOneWidget);
    expect(find.text('Your wallet balance is now ₹100.'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('₹100'), findsWidgets); // wallet chip
  });

  testWidgets('failed payment keeps the gate closed', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Pay ₹100'));
    await settle(tester);
    await tester.tap(find.text('Simulate failure'));
    await settle(tester);
    expect(find.text('Payment failed'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('Add money to get started'), findsOneWidget);
  });

  testWidgets('user can defer the first recharge', (tester) async {
    await pumpApp(tester);

    expect(find.text("I'll do it later"), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsNothing);

    await tester.tap(find.text("I'll do it later"));
    await settle(tester);

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Add money to get started'), findsNothing);

    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(find.text('Language'), findsOneWidget);
  });

  testWidgets('RC lookup end to end: validate, confirm, charge, result', (
    tester,
  ) async {
    await pumpApp(tester);
    await completeFirstRecharge(tester);

    await tester.tap(find.textContaining('Owner, maker'));
    await settle(tester);
    expect(find.text('Vehicle Details'), findsOneWidget);
    expect(find.textContaining('third-party data providers'), findsNothing);
    expect(
      find.text('You are charged only if the search succeeds.'),
      findsNothing,
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintStyle?.color, AppColors.placeholder);

    final searchFinder = find.widgetWithText(FilledButton, 'Search for ₹2');
    expect(tester.widget<FilledButton>(searchFinder).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'mh12ab1234');
    await tester.pump();
    expect(tester.widget<FilledButton>(searchFinder).onPressed, isNotNull);

    await tester.tap(searchFinder);
    await settle(tester);
    expect(find.text('Confirm search'), findsOneWidget);
    expect(find.text('₹98'), findsOneWidget); // balance after

    await tester.tap(find.widgetWithText(FilledButton, 'Search for ₹2').last);
    await settle(tester);

    expect(find.text('MH12AB1234'), findsOneWidget);
    expect(find.text('Owner name'), findsOneWidget);
    expect(find.textContaining('Get the owner'), findsOneWidget);
    expect(find.textContaining('Demo data'), findsOneWidget);
    expect(find.textContaining('third-party data providers'), findsNothing);

    await tester.tap(find.byTooltip('Go back'));
    await settle(tester);
    expect(find.text('₹98'), findsWidgets); // deducted
    await tester.tap(find.text('History'));
    await settle(tester);
    expect(find.text('MH12****34'), findsOneWidget); // saved in history
  });

  testWidgets('phone lookup button stays disabled for an invalid number', (
    tester,
  ) async {
    await pumpApp(tester);
    await completeFirstRecharge(tester);

    await tester.tap(find.textContaining('Get the owner'));
    await settle(tester);
    expect(find.textContaining('third-party data providers'), findsNothing);
    expect(
      find.text('You are charged only if the search succeeds.'),
      findsNothing,
    );
    await tester.enterText(find.byType(TextField), 'ABC');
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'Search for ₹5');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
  });

  testWidgets(
    'record not found shows a no-charge message and keeps the balance',
    (tester) async {
      await pumpApp(tester);
      await completeFirstRecharge(tester);

      await tester.tap(find.textContaining('Owner, maker'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'MH12AB0000');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Search for ₹2').last);
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Search for ₹2').last);
      await settle(tester);

      expect(find.textContaining('You were not charged'), findsOneWidget);
      await tester.tap(find.byTooltip('Go back'));
      await settle(tester);
      expect(find.text('₹100'), findsWidgets);
    },
  );
}
