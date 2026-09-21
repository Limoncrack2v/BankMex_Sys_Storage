import 'package:flutter/material.dart';

import '../../../data/models/family.dart';
import '../../../data/models/member.dart';
import '../../../data/repositories/family_repository.dart';
import '../../../data/repositories/member_repository.dart';
import '../../formatting.dart';
import '../../session_navigation.dart';
import '../../theme/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_header.dart';
import '../../widgets/pill.dart';
import 'member_form_sheet.dart';

/// Perfil del hogar: resumen de la familia e integrantes.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.family});

  final Family family;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final Stream<Family?> _family;
  late Stream<List<Member>> _members;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _family = FamilyRepository().watchFamily(widget.family.familyId);
    _members = _watchMembers();
  }

  Stream<List<Member>> _watchMembers() => MemberRepository()
      .watchAllMembers(widget.family.familyId)
      .map(
        (members) =>
            [...members]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );

  void _retry() => setState(() => _members = _watchMembers());

  void _openMemberForm([Member? member]) {
    showMemberFormSheet(
      context,
      familyId: widget.family.familyId,
      initial: member,
    );
  }

  /// signOutAndReturnToSignIn navega primero y cierra la sesión después, así
  /// que no falla aquí. La bandera evita un segundo toque durante la
  /// transición.
  Future<void> _signOut() async {
    if (_signingOut) return;
    _signingOut = true;
    await signOutAndReturnToSignIn(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AppHeader(title: 'Perfil'),
        Expanded(
          child: StreamBuilder<Family?>(
            stream: _family,
            initialData: widget.family,
            builder: (context, familySnapshot) {
              final family = familySnapshot.data ?? widget.family;
              return StreamBuilder<List<Member>>(
                stream: _members,
                builder: (context, snapshot) =>
                    _buildContent(family.displayName, snapshot),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContent(
    String familyName,
    AsyncSnapshot<List<Member>> snapshot,
  ) {
    final members = snapshot.hasError ? null : snapshot.data;
    final adults = members
        ?.where((m) => m.memberType == MemberType.adult)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HouseholdSummary(
          familyName: familyName,
          adults: adults,
          children: members == null ? null : members.length - adults!,
        ),
        const SizedBox(height: 16),
        Text(
          'Integrantes',
          style: AppText.nunito(15, 22.5, weight: FontWeight.w700),
        ),
        if (snapshot.hasError) ...[
          const SizedBox(height: 8),
          const InfoBanner(
            message: 'No se pudieron cargar los integrantes. Intenta de nuevo.',
            background: AppColors.dangerSoft,
            foreground: AppColors.dangerText,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextLinkButton(label: 'Reintentar', onPressed: _retry),
          ),
        ] else if (members == null)
          const Padding(
            padding: EdgeInsets.only(top: 24, bottom: 8),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (members.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Aún no hay integrantes registrados.',
              style: AppText.nunito(15, 22.5, color: AppColors.textMuted),
            ),
          )
        else
          for (final member in members) ...[
            const SizedBox(height: 8),
            _MemberCard(member: member, onTap: () => _openMemberForm(member)),
          ],
        const SizedBox(height: 16),
        SecondaryButton(
          label: 'Agregar integrante',
          icon: AppIcons.plus,
          onPressed: _openMemberForm,
        ),
        const SizedBox(height: 24),
        Center(
          child: TextLinkButton(label: 'Cerrar sesión', onPressed: _signOut),
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

  /// null mientras cargan los integrantes.
  final int? adults;
  final int? children;

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
              _Stat(
                value: children,
                label: children == 1 ? 'Niña o niño' : 'Niñas y niños',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int? value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value == null ? '–' : '$value',
          style: AppText.baloo(24, 36, color: AppColors.primaryDark),
        ),
        Text(label, style: AppText.nunito(14, 21, color: AppColors.textMuted)),
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.onTap});

  final Member member;
  final VoidCallback onTap;

  static const _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
    side: BorderSide(color: AppColors.border),
  );

  String get _initial {
    final trimmed = member.name.trim();
    return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppText.nunito(14, 21, color: AppColors.textMuted);
    final age = member.age;
    final weight = member.weightKg;
    final allergies = member.allergies ?? const <Allergy>[];

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
                  _initial,
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
                    Text(memberKindLabel(member), style: muted),
                    if (allergies.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Alergias: ${allergies.map(allergyLabel).join(', ')}',
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
              if (age != null || weight != null) ...[
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (age != null) Text(formatAge(age), style: muted),
                    if (weight != null)
                      Text(formatWeight(weight), style: muted),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
