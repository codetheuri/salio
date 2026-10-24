import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/layout/breakpoints.dart';
import '../../../core/phone/phone.dart';
import '../../../core/time/shop_time.dart';
import '../../../core/widgets/money_text.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/data/providers.dart';

/// Opens the customer chooser over the current screen and returns the id
/// of the one tapped, or null. Searches by name or phone, as the customer
/// list does.
Future<String?> pickCustomer(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const CustomerPicker(),
      ),
    );

class CustomerPicker extends ConsumerStatefulWidget {
  const CustomerPicker({super.key});

  @override
  ConsumerState<CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<CustomerPicker> {
  var _search = '';

  // Made once per search, not per build: a new stream would start empty.
  late Stream<List<CustomerBalance>> _customers = _query();

  Stream<List<CustomerBalance>> _query() => ref
      .read(customerRepositoryProvider)
      .watchList(today: ref.read(shopTodayProvider), search: _search);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.customerChoose)),
      body: ReadableWidth(
        maxWidth: Breakpoints.listWidth,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() {
                  _search = v;
                  _customers = _query();
                }),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.customersSearch,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<List<CustomerBalance>>(
                stream: _customers,
                builder: (context, snapshot) {
                  final list = snapshot.data;
                  if (list == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        _search.trim().isEmpty
                            ? l10n.customersEmpty
                            : l10n.customersNoMatch,
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = list[i].customer;
                      final phone = c.phone;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: AppColors.primaryDark,
                          child: Text(
                            c.name.isEmpty
                                ? '?'
                                : c.name.characters.first.toUpperCase(),
                          ),
                        ),
                        title: Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: phone == null
                            ? null
                            : Text(Phone.display(phone)),
                        trailing: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: BalanceText(list[i].balanceCents),
                        ),
                        onTap: () => Navigator.of(context).pop(c.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
