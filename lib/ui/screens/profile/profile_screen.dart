import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/household_member.dart';
import '../../sample_data.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../sign_in/sign_in_screen.dart';
import 'member_form_sheet.dart';

/// Perfil del hogar: resumen de la familia e integrantes.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _members = [...SampleData.members];

  void _openMemberForm({int? index}) {
    showMemberFormSheet(
      context,
      initial: index == null ? null : _members[index],
      onSave: (member) => setState(() {
        if (index == null) {
          _members.add(member);
        } else {
          _members[index] = member;
        }
      }),
    );
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final adults = _members.where((m) => m.type == MemberType.adulto).length;

    return Column(
      children: [
        const AppHeader(title: 'Perfil'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HouseholdSummary(
                familyName: SampleData.familyName,
                adults: adults,
                children: _members.length - adults,
              ),
              const SizedBox(height: 16),
              Text(
                'Integrantes',
                style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
              ),
              if (_members.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Aún no hay integrantes registrados.',
                    style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
                  ),
                ),
              for (var i = 0; i < _members.length; i++) ...[
                const SizedBox(height: 8),
                _MemberCard(
                  member: _members[i],
                  onTap: () => _openMemberForm(index: i),
                ),
              ],
              const SizedBox(height: 16),
              SecondaryButton(
                label: 'Agregar integrante',
                icon: AppIcons.plus,
                onPressed: _openMemberForm,
              ),
              const SizedBox(height: 24),
              Center(
                child: TextLinkButton(
                  label: 'Cerrar sesión',
                  onPressed: _signOut,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HouseholdSummary extends StatelessWidget {
  const _HouseholdSummary({
    required this.familyName,
    required this.adults,
    required this.children,
  });

  final String familyName;
  final int adults;
  final int children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hogar',
            style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
          ),
          Text(familyName, style: AppText.baloo(20, 30)),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(value: adults, label: adults == 1 ? 'Adulto' : 'Adultos'),
              const SizedBox(width: 16),
              _Stat(value: children, label: 'Niñas y niños'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: AppText.baloo(24, 36, color: AppColors.primaryDark),
        ),
        Text(
          label,
          style: AppText.nunito(14, 21, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.onTap});

  final HouseholdMember member;
  final VoidCallback onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: AppColors.border),
  );

  @override
  Widget build(BuildContext context) {
    final muted = AppText.nunito(14, 21, color: AppColors.textMuted);
    final weight = member.weightKg;

    return Material(
      color: AppColors.surface,
      shape: _shape,
      child: InkWell(
        onTap: onTap,
        customBorder: _shape,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  member.initial,
                  style: AppText.baloo(18, 27, color: AppColors.primaryDark),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      style: AppText.baloo(17, 25.5, weight: FontWeight.w600),
                    ),
                    Text(member.type.label, style: muted),
                    if (member.allergies.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Alergias: ${member.allergies.join(', ')}',
                          style: AppText.nunito(
                            13,
                            19.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    member.age == 1 ? '1 año' : '${member.age} años',
                    style: muted,
                  ),
                  if (weight != null) Text('${formatKg(weight)} kg', style: muted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
