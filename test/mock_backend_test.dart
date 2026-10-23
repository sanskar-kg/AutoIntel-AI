import 'package:autointel_ai/core/errors.dart';
import 'package:autointel_ai/data/mock_backend.dart';
import 'package:autointel_ai/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<MockBackend> newBackend() async {
  SharedPreferences.setMockInitialValues({});
  return MockBackend(
    await SharedPreferences.getInstance(),
    latency: Duration.zero,
  );
}

Future<void> recharge(MockBackend b, int paise) async {
  final order = await b.createOrder(paise);
  await b.settleOrder(order.id, OrderStatus.success);
}

void main() {
  test('lookups are blocked until the first recharge', () async {
    final b = await newBackend();
    expect(
      () => b.lookup(LookupType.rc, 'MH12AB1234', 'k1'),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          ErrorCode.rechargeRequired,
        ),
      ),
    );
  });

  test('recharge below the minimum is rejected', () async {
    final b = await newBackend();
    expect(() => b.createOrder(100), throwsA(isA<AppException>()));
  });

  test('successful order credits once, even if settled twice', () async {
    final b = await newBackend();
    final order = await b.createOrder(10000);
    await b.settleOrder(order.id, OrderStatus.success);
    await b.settleOrder(order.id, OrderStatus.success);
    final w = await b.getWallet();
    expect(w.balancePaise, 10000);
    expect(w.minRechargeDone, isTrue);
    expect((await b.getLedger()).length, 1);
  });

  test('failed order credits nothing', () async {
    final b = await newBackend();
    final order = await b.createOrder(10000);
    await b.settleOrder(order.id, OrderStatus.failed);
    final w = await b.getWallet();
    expect(w.balancePaise, 0);
    expect(w.minRechargeDone, isFalse);
  });

  test('RC lookup charges the RC price and is saved to history', () async {
    final b = await newBackend();
    await recharge(b, 5000);
    final l = await b.lookup(LookupType.rc, 'mh12 ab 1234', 'k1');
    expect(l.chargedPaise, 200);
    expect(l.rc, isNotNull);
    expect(l.regNo, 'MH12AB1234');
    expect((await b.getWallet()).balancePaise, 4800);
    expect((await b.getHistory()).length, 1);
  });

  test('phone lookup charges the higher price', () async {
    final b = await newBackend();
    await recharge(b, 5000);
    final l = await b.lookup(LookupType.phone, 'MH12AB1234', 'k1');
    expect(l.chargedPaise, 500);
    expect(l.phone, matches(RegExp(r'^\d{10}$')));
    expect((await b.getWallet()).balancePaise, 4500);
  });

  test('same idempotency key never charges twice', () async {
    final b = await newBackend();
    await recharge(b, 5000);
    final a = await b.lookup(LookupType.rc, 'MH12AB1234', 'same');
    final c = await b.lookup(LookupType.rc, 'MH12AB1234', 'same');
    expect(c.id, a.id);
    expect((await b.getWallet()).balancePaise, 4800);
  });

  test('failed provider calls are never charged', () async {
    final b = await newBackend();
    await recharge(b, 5000);
    await expectLater(
      b.lookup(LookupType.rc, 'MH12AB0000', 'k1'),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          ErrorCode.recordNotFound,
        ),
      ),
    );
    await expectLater(
      b.lookup(LookupType.phone, 'MH12AB9999', 'k2'),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          ErrorCode.providerUnavailable,
        ),
      ),
    );
    expect((await b.getWallet()).balancePaise, 5000);
    expect(await b.getHistory(), isEmpty);
  });

  test('insufficient balance does not call the provider', () async {
    final b = await newBackend();
    await recharge(b, 2000);
    for (var i = 0; i < 10; i++) {
      await b.lookup(LookupType.rc, 'MH12AB123$i', 'rc$i'); // 10 × ₹2 = ₹20
    }
    expect((await b.getWallet()).balancePaise, 0);
    await expectLater(
      b.lookup(LookupType.rc, 'MH12AB1234', 'one-more'),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          ErrorCode.insufficientBalance,
        ),
      ),
    );
  });

  test('invalid registration number is rejected before charging', () async {
    final b = await newBackend();
    await recharge(b, 5000);
    await expectLater(
      b.lookup(LookupType.rc, 'nope', 'k1'),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          ErrorCode.invalidRegNo,
        ),
      ),
    );
    expect((await b.getWallet()).balancePaise, 5000);
  });

  test('state survives an app restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = MockBackend(prefs, latency: Duration.zero);
    await recharge(first, 5000);
    await first.lookup(LookupType.rc, 'MH12AB1234', 'k1');
    final second = MockBackend(prefs, latency: Duration.zero);
    expect((await second.getWallet()).balancePaise, 4800);
    expect((await second.getHistory()).length, 1);
  });
}
