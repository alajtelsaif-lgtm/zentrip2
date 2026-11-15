import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/price_comparison.dart';
import '../../../../global_widgets/flight_currency_selector.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../models/flight_model.dart';
import 'flight_checkout_shared_components.dart';

@immutable
class FlightCheckoutPassenger {
  final String name;
  final String dateOfBirth;
  final String nationality;
  final String passportNumber;
  final String passportExpiry;
  final String email;
  final String phone;

  const FlightCheckoutPassenger({
    this.name = '',
    this.dateOfBirth = '',
    this.nationality = '',
    this.passportNumber = '',
    this.passportExpiry = '',
    this.email = '',
    this.phone = '',
  });

  FlightCheckoutPassenger copyWith({
    String? name,
    String? dateOfBirth,
    String? nationality,
    String? passportNumber,
    String? passportExpiry,
    String? email,
    String? phone,
  }) =>
      FlightCheckoutPassenger(
        name: name ?? this.name,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        nationality: nationality ?? this.nationality,
        passportNumber: passportNumber ?? this.passportNumber,
        passportExpiry: passportExpiry ?? this.passportExpiry,
        email: email ?? this.email,
        phone: phone ?? this.phone,
      );
}

@immutable
class FlightPassengerUpdate {
  final int index;
  final FlightCheckoutPassenger passenger;

  const FlightPassengerUpdate({required this.index, required this.passenger});
}

class FlightPassengersScreen extends StatelessWidget {
  final FlightModel flight;
  final List<FlightCheckoutPassenger> passengers;
  final String fareLabel;
  final String currencyCode;
  final PriceComparison comparison;
  final ValueChanged<String> onCurrencyChanged;
  final double totalPrice;
  final ValueChanged<FlightPassengerUpdate> onPassengerChanged;
  final VoidCallback? onContinue;
  final VoidCallback? onBack;

  const FlightPassengersScreen({
    super.key,
    required this.flight,
    required this.passengers,
    required this.fareLabel,
    required this.currencyCode,
    required this.comparison,
    required this.onCurrencyChanged,
    required this.totalPrice,
    required this.onPassengerChanged,
    required this.onContinue,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = CheckoutLabels(l10n);
    return CheckoutScaffold(
      header: FlightBookingFlowHeader(
        title: l10n.passengers,
        activeStep: 1,
        onBack: onBack,
      ),
      footer: CheckoutFooter(
        total: checkoutMoney(
          currencyCode,
          totalPrice,
          locale: Localizations.localeOf(context).languageCode,
        ),
        caption: '$fareLabel · ${labels.travellerPrice(passengers.length)}',
        buttonLabel: labels.continueLabel,
        onPressed: onContinue,
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 18),
        children: [
          CheckoutRouteCaption(flight: flight),
          FlightCurrencySelector(
            comparison: comparison,
            onChanged: onCurrencyChanged,
          ),
          const SizedBox(height: 10),
          const SizedBox(height: 14),
          Text(labels.whosFlying,
              style: const TextStyle(
                  fontSize: 22,
                  height: 1.15,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(labels.passportPrompt,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 14),
          if (passengers.isEmpty)
            CheckoutEmptyPanel(message: labels.noPassengerData)
          else
            ...List.generate(
              passengers.length,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PassengerEditor(
                  key: ValueKey('passenger-$index'),
                  index: index,
                  passenger: passengers[index],
                  onChanged: (passenger) => onPassengerChanged(
                    FlightPassengerUpdate(index: index, passenger: passenger),
                  ),
                ),
              ),
            ),
          CheckoutPanel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 15, color: AppColors.textHint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labels.passportPrivacy,
                    style: const TextStyle(
                        color: AppColors.textHint, fontSize: 10, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PassengerEditor extends StatefulWidget {
  final int index;
  final FlightCheckoutPassenger passenger;
  final ValueChanged<FlightCheckoutPassenger> onChanged;
  const _PassengerEditor({
    super.key,
    required this.index,
    required this.passenger,
    required this.onChanged,
  });

  @override
  State<_PassengerEditor> createState() => _PassengerEditorState();
}

class _PassengerEditorState extends State<_PassengerEditor> {
  bool _editing = false;

  void _update(String field, String value) {
    final current = widget.passenger;
    final next = switch (field) {
      'name' => current.copyWith(name: value),
      'dob' => current.copyWith(dateOfBirth: value),
      'nationality' => current.copyWith(nationality: value),
      'passport' => current.copyWith(passportNumber: value),
      'expiry' => current.copyWith(passportExpiry: value),
      'email' => current.copyWith(email: value),
      _ => current.copyWith(phone: value),
    };
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = CheckoutLabels(l10n);
    final passenger = widget.passenger;
    return CheckoutPanel(
      padding: const EdgeInsets.all(13),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 37,
                height: 37,
                decoration: const BoxDecoration(
                    color: AppColors.primarySurface, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('${widget.index + 1}',
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(labels.travellerType(widget.index),
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 10)),
                    Text(
                      passenger.name.isEmpty
                          ? labels.nameLabel
                          : passenger.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _editing = !_editing),
                child: Text(_editing ? l10n.done : l10n.edit,
                    style: const TextStyle(
                        color: AppColors.primary, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (_editing) ...[
            const Divider(height: 20),
            _PassengerTextField(
              label: labels.nameLabel,
              value: passenger.name,
              icon: Icons.person_outline_rounded,
              onChanged: (value) => _update('name', value),
            ),
            _PassengerDateField(
              label: labels.dateOfBirth,
              value: passenger.dateOfBirth,
              onChanged: (value) => _update('dob', value),
            ),
            _PassengerTextField(
              label: labels.nationality,
              value: passenger.nationality,
              icon: Icons.public_rounded,
              onChanged: (value) => _update('nationality', value),
            ),
            _PassengerTextField(
              label: labels.passportNumber,
              value: passenger.passportNumber,
              icon: Icons.badge_outlined,
              onChanged: (value) => _update('passport', value),
            ),
            _PassengerDateField(
              label: labels.passportExpiry,
              value: passenger.passportExpiry,
              onChanged: (value) => _update('expiry', value),
            ),
            _PassengerTextField(
              label: l10n.emailLabel,
              value: passenger.email,
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              onChanged: (value) => _update('email', value),
            ),
            _PassengerTextField(
              label: l10n.phoneLabel,
              value: passenger.phone,
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              onChanged: (value) => _update('phone', value),
            ),
          ] else ...[
            const Divider(height: 18),
            CheckoutTwoColumnValues(
              firstLabel: labels.dateOfBirth,
              firstValue: passenger.dateOfBirth,
              secondLabel: labels.nationality,
              secondValue: passenger.nationality,
            ),
            const SizedBox(height: 12),
            CheckoutTwoColumnValues(
              firstLabel: labels.passportNumber,
              firstValue: checkoutMaskPassport(passenger.passportNumber),
              secondLabel: labels.passportExpiry,
              secondValue: passenger.passportExpiry,
            ),
            if (passenger.email.isNotEmpty || passenger.phone.isNotEmpty) ...[
              const Divider(height: 20),
              CheckoutValueLine(label: l10n.emailLabel, value: passenger.email),
              CheckoutValueLine(label: l10n.phoneLabel, value: passenger.phone),
            ],
          ],
        ],
      ),
    );
  }
}

class _PassengerTextField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;
  const _PassengerTextField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onChanged,
    this.keyboardType,
  });
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: TextFormField(
          initialValue: value,
          onChanged: onChanged,
          keyboardType: keyboardType,
          textDirection: Directionality.of(context),
          decoration: checkoutInputDecoration(label, icon),
        ),
      );
}

class _PassengerDateField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  const _PassengerDateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: TextFormField(
          initialValue: value,
          readOnly: true,
          onTap: () async {
            final initial = DateTime.tryParse(value) ?? DateTime(2000);
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              onChanged(
                '${picked.year.toString().padLeft(4, '0')}-'
                '${picked.month.toString().padLeft(2, '0')}-'
                '${picked.day.toString().padLeft(2, '0')}',
              );
            }
          },
          decoration: checkoutInputDecoration(
            label,
            Icons.calendar_today_outlined,
          ).copyWith(suffixIcon: const Icon(Icons.expand_more_rounded)),
        ),
      );
}
