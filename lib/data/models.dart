enum LookupType { rc, phone }

class Account {
  const Account({
    required this.id,
    required this.name,
    this.email = '',
    this.phone = '',
    this.provider = 'unknown',
    this.isTemporary = false,
    this.isPhoneVerified = false,
  });
  final String id;
  final String name;
  final String email;
  final String phone;
  final String provider;
  final bool isTemporary;
  final bool isPhoneVerified;

  String get firstName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '' : trimmed.split(RegExp(r'\s+')).first;
  }
}

/// Server-driven configuration. Prices and limits can change without an app update.
class AppConfig {
  const AppConfig({
    required this.rcPricePaise,
    required this.phonePricePaise,
    required this.minRechargePaise,
    required this.maxRechargePaise,
    required this.presetsPaise,
  });

  final int rcPricePaise;
  final int phonePricePaise;
  final int minRechargePaise;
  final int maxRechargePaise;
  final List<int> presetsPaise;

  int priceFor(LookupType type) =>
      type == LookupType.rc ? rcPricePaise : phonePricePaise;
}

class WalletSnapshot {
  const WalletSnapshot({
    required this.balancePaise,
    required this.minRechargeDone,
    this.showRechargeGate = true,
  });
  final int balancePaise;
  final bool minRechargeDone;
  final bool showRechargeGate;
}

enum LedgerType { credit, debit, refund }

enum LedgerCategory { topup, rcLookup, phoneLookup, refund }

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.category,
    required this.amountPaise,
    required this.balanceAfterPaise,
    required this.createdAt,
    this.regNoMasked = '',
  });

  final String id;
  final LedgerType type;
  final LedgerCategory category;
  final int amountPaise;
  final int balanceAfterPaise;
  final DateTime createdAt;
  final String regNoMasked;

  bool get isCredit => type != LedgerType.debit;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'category': category.name,
    'amountPaise': amountPaise,
    'balanceAfterPaise': balanceAfterPaise,
    'createdAt': createdAt.toIso8601String(),
    'regNoMasked': regNoMasked,
  };

  factory LedgerEntry.fromJson(Map<String, Object?> j) => LedgerEntry(
    id: j['id']! as String,
    type: LedgerType.values.byName(j['type']! as String),
    category: LedgerCategory.values.byName(j['category']! as String),
    amountPaise: j['amountPaise']! as int,
    balanceAfterPaise: j['balanceAfterPaise']! as int,
    createdAt: DateTime.parse(j['createdAt']! as String),
    regNoMasked: (j['regNoMasked'] as String?) ?? '',
  );
}

/// Normalized RC result. [extra] holds additional provider fields keyed by a
/// canonical name (e.g. `fuelType`); unknown keys are shown as-is.
class RcResult {
  const RcResult({
    required this.ownerName,
    required this.maker,
    required this.model,
    this.extra = const {},
  });
  final String ownerName;
  final String maker;
  final String model;
  final Map<String, String> extra;

  Map<String, Object?> toJson() => {
    'ownerName': ownerName,
    'maker': maker,
    'model': model,
    'extra': extra,
  };

  factory RcResult.fromJson(Map<String, Object?> j) => RcResult(
    ownerName: j['ownerName']! as String,
    maker: j['maker']! as String,
    model: j['model']! as String,
    extra: Map<String, String>.from((j['extra'] as Map?) ?? const {}),
  );
}

class Lookup {
  const Lookup({
    required this.id,
    required this.type,
    required this.regNo,
    required this.regNoMasked,
    required this.chargedPaise,
    required this.createdAt,
    this.rc,
    this.phone,
    this.isDemo = false,
  });

  final String id;
  final LookupType type;
  final String regNo; // normalized, e.g. MH12AB1234
  final String regNoMasked;
  final int chargedPaise;
  final DateTime createdAt;
  final RcResult? rc;
  final String? phone;
  final bool isDemo;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'regNo': regNo,
    'regNoMasked': regNoMasked,
    'chargedPaise': chargedPaise,
    'createdAt': createdAt.toIso8601String(),
    'rc': rc?.toJson(),
    'phone': phone,
    'isDemo': isDemo,
  };

  factory Lookup.fromJson(Map<String, Object?> j) => Lookup(
    id: j['id']! as String,
    type: LookupType.values.byName(j['type']! as String),
    regNo: j['regNo']! as String,
    regNoMasked: j['regNoMasked']! as String,
    chargedPaise: j['chargedPaise']! as int,
    createdAt: DateTime.parse(j['createdAt']! as String),
    rc: j['rc'] == null
        ? null
        : RcResult.fromJson(Map<String, Object?>.from(j['rc']! as Map)),
    phone: j['phone'] as String?,
    isDemo: (j['isDemo'] as bool?) ?? false,
  );
}

enum OrderStatus { created, pending, success, failed }

class PaymentOrder {
  const PaymentOrder({
    required this.id,
    required this.amountPaise,
    required this.status,
    this.gateway = 'MOCK',
  });
  final String id;
  final int amountPaise;
  final OrderStatus status;
  final String gateway;

  bool get isTerminal =>
      status == OrderStatus.success || status == OrderStatus.failed;

  PaymentOrder copyWith({OrderStatus? status}) => PaymentOrder(
    id: id,
    amountPaise: amountPaise,
    status: status ?? this.status,
    gateway: gateway,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'amountPaise': amountPaise,
    'status': status.name,
    'gateway': gateway,
  };

  factory PaymentOrder.fromJson(Map<String, Object?> j) => PaymentOrder(
    id: j['id']! as String,
    amountPaise: j['amountPaise']! as int,
    status: OrderStatus.values.byName(j['status']! as String),
    gateway: (j['gateway'] as String?) ?? 'MOCK',
  );
}
