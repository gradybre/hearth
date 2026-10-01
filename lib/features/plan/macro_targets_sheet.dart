import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/hearth_colors.dart';
import '../../app/theme/hearth_spacing.dart';
import '../../app/theme/hearth_theme.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/planning/day_format.dart';
import '../../domain/planning/day_progress.dart';
import '../../domain/planning/target_schedule.dart';
import '../../domain/planning/week.dart';

/// Reviews this person's seven daily targets and where they apply (spec §5.6).
/// The opening week and account stay fixed until the sheet is dismissed.
Future<void> showMacroTargetsSheet(
  BuildContext context, {
  DateTime Function()? clock,
}) {
  final ProviderContainer container = ProviderScope.containerOf(
    context,
    listen: false,
  );
  final DateTime week = startOfWeek(container.read(selectedDateProvider));
  final String userId = container.read(currentUserIdProvider);
  final PlanRepository repository = container.read(planRepositoryProvider);
  final bool isCurrentWeek =
      week == startOfWeek(clock?.call() ?? DateTime.now());
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxWidth: 640,
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => _MacroTargetsSheet(
      week: week,
      userId: userId,
      repository: repository,
      openedOnCurrentWeek: isCurrentWeek,
      clock: clock,
    ),
  );
}

/// The source of a week's targets, with a visible way to review them.
class TargetSourceAction extends StatelessWidget {
  const TargetSourceAction({
    super.key,
    required this.resolution,
    required this.hasTargets,
  });

  final ResolvedTargets? resolution;
  final bool hasTargets;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => showMacroTargetsSheet(context),
    child: Text(
      resolution?.source == TargetSource.ongoing
          ? 'Using ongoing targets · Change'
          : hasTargets
          ? 'This week’s targets · Change'
          : 'Set targets',
    ),
  );
}

class _MacroTargetsSheet extends ConsumerStatefulWidget {
  const _MacroTargetsSheet({
    required this.week,
    required this.userId,
    required this.repository,
    required this.openedOnCurrentWeek,
    this.clock,
  });

  final DateTime week;
  final String userId;
  final PlanRepository repository;
  final bool openedOnCurrentWeek;
  final DateTime Function()? clock;

  @override
  ConsumerState<_MacroTargetsSheet> createState() => _MacroTargetsSheetState();
}

class _MacroTargetsSheetState extends ConsumerState<_MacroTargetsSheet> {
  final TextEditingController _kcal = TextEditingController();
  final TextEditingController _protein = TextEditingController();
  final TextEditingController _carbs = TextEditingController();
  final TextEditingController _fat = TextEditingController();

  // Blank means the Daily Value, not zero and not a prefilled daily value.
  final TextEditingController _fibre = TextEditingController();
  final TextEditingController _sodium = TextEditingController();
  final TextEditingController _cholesterol = TextEditingController();

  late final DateTime _week;
  late final String _userId;
  late final PlanRepository _repository;
  late final bool _openedOnCurrentWeek;
  ResolvedTargets? _initial;
  List<String> _savedText = <String>[];
  bool _useOngoing = true;
  bool _saving = false;
  String? _error;

  List<TextEditingController> get _controllers => <TextEditingController>[
    _kcal,
    _protein,
    _carbs,
    _fat,
    _fibre,
    _sodium,
    _cholesterol,
  ];

  DateTime get _now => widget.clock?.call() ?? DateTime.now();
  bool get _hasOngoing => _initial?.ongoingBoundary?.isStopped == false;
  bool get _accountMatches => ref.read(currentUserIdProvider) == _userId;
  bool get _dirty =>
      _savedText.length != _controllers.length ||
      <int>[for (int i = 0; i < _controllers.length; i++) i]
          .any((int i) => _controllers[i].text != _savedText[i]);

  String get _weekRange {
    final DateTime end = addDays(_week, 6);
    final String startYear = _week.year == end.year ? '' : ', ${_week.year}';
    return '${monthName(_week)} ${_week.day}$startYear – '
        '${monthName(end)} ${end.day}, ${end.year}';
  }

  @override
  void initState() {
    super.initState();
    _week = widget.week;
    _userId = widget.userId;
    _repository = widget.repository;
    _openedOnCurrentWeek = widget.openedOnCurrentWeek;
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _seed(ResolvedTargets resolution) {
    // A no-target answer is a completed load too. Refreshes, navigation and
    // account changes must never replace numbers the person has since typed.
    if (_initial != null ||
        resolution.userId != _userId ||
        resolution.weekStart != _week) {
      return;
    }
    _initial = resolution;
    final MacroTargets? existing = resolution.targets;
    if (existing != null) {
      final List<double?> values = <double?>[
        existing.kcal,
        existing.proteinG,
        existing.carbG,
        existing.fatG,
        existing.fiberG,
        existing.sodiumMg,
        existing.cholesterolMg,
      ];
      for (int i = 0; i < values.length; i++) {
        _controllers[i].text = values[i] == null ? '' : _trim(values[i]!);
      }
    }
    _savedText = _controllers.map((TextEditingController c) => c.text).toList();
    _useOngoing =
        _openedOnCurrentWeek &&
        (!_hasOngoing || resolution.source != TargetSource.exactWeek);
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  MacroTargets _enteredTargets() => MacroTargets(
    kcal: double.tryParse(_kcal.text.trim()) ?? 0,
    proteinG: double.tryParse(_protein.text.trim()) ?? 0,
    carbG: double.tryParse(_carbs.text.trim()) ?? 0,
    fatG: double.tryParse(_fat.text.trim()) ?? 0,
    fiberG: double.tryParse(_fibre.text.trim()),
    sodiumMg: double.tryParse(_sodium.text.trim()),
    cholesterolMg: double.tryParse(_cholesterol.text.trim()),
  );

  bool _canWrite({required bool ongoing}) {
    if (_saving) return false;
    if (!_accountMatches) {
      setState(
        () => _error =
            'The account changed. Close this sheet and '
            'reopen targets for the current account.',
      );
      return false;
    }
    if (ongoing && _week != startOfWeek(_now)) {
      setState(
        () => _error = _hasOngoing
            ? 'A new week has started. Choose This week only to save for '
                  'these dates, or reopen the current week to change ongoing targets.'
            : 'A new week has started. Turn off “Use these targets each new '
                  'week” to save for these dates, or reopen the current week.',
      );
      return false;
    }
    return _initial != null;
  }

  Future<void> _save() async {
    if (!_canWrite(ongoing: _useOngoing)) return;
    for (final TextEditingController controller in _controllers) {
      final String text = controller.text.trim();
      if (text.isEmpty) continue;
      final double? value = double.tryParse(text);
      if (value == null || !value.isFinite || value < 0) {
        setState(
          () => _error =
              'Enter a number of zero or more for each '
              'target. Optional nutrients can be left blank.',
        );
        return;
      }
    }
    final MacroTargets targets = _enteredTargets();
    await _write(
      () => _useOngoing
          ? _repository.setOngoingTargets(_week, targets)
          : _repository.setTargets(_week, targets),
      error:
          'Targets could not be saved. Your changes are still here. '
          'Try again.',
    );
  }

  Future<void> _stop() async {
    if (!_canWrite(ongoing: true) || _dirty) return;
    await _write(
      () => _repository.stopOngoingTargets(_week),
      error:
          'Carry-forward could not be stopped. Your targets are still '
          'here. Try again.',
    );
  }

  Future<void> _write(
    Future<void> Function() action, {
    required String error,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(targetResolutionProvider);
      ref.invalidate(dayTargetResolutionProvider);
      ref.invalidate(dayTargetsProvider);
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final HearthColors colors = context.colors;
    final bool sameAccount = ref.watch(currentUserIdProvider) == _userId;
    final AsyncValue<ResolvedTargets> loading = ref.watch(
      targetResolutionProvider(_week),
    );
    if (sameAccount) {
      if (loading.value case final ResolvedTargets resolution) {
        _seed(resolution);
      }
    }
    final bool editable = sameAccount && !_saving;
    final String? error = sameAccount
        ? _error
        : 'The account changed. Close this sheet and reopen targets for '
              'the current account.';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(HearthRadius.xl),
        ),
        child: SafeArea(
          child: ListView(
            key: const ValueKey<String>('macro-targets-editor'),
            shrinkWrap: true,
            padding: const EdgeInsets.all(HearthSpacing.lg),
            children: <Widget>[
              Text('Weekly targets', style: context.text.sectionHeader),
              const SizedBox(height: HearthSpacing.xs),
              Text(_weekRange, style: context.text.body),
              const SizedBox(height: HearthSpacing.xxs),
              Text(
                'Your daily targets, private to you.',
                style: context.text.metadata.copyWith(color: colors.textMuted),
              ),
              if (_initial == null && sameAccount) ...<Widget>[
                const SizedBox(height: HearthSpacing.lg),
                if (loading.hasError) ...<Widget>[
                  const Text('Targets could not be loaded. Try again.'),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(targetResolutionProvider(_week)),
                    child: const Text('Retry'),
                  ),
                ] else
                  const Center(child: CircularProgressIndicator()),
              ],
              if (_initial != null && sameAccount) ...<Widget>[
                const SizedBox(height: HearthSpacing.lg),
                if (_openedOnCurrentWeek && !_hasOngoing)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Use these targets each new week'),
                    subtitle: const Text(
                      'Starts with these dates when you save.',
                    ),
                    value: _useOngoing,
                    onChanged: editable
                        ? (bool? value) =>
                              setState(() => _useOngoing = value ?? false)
                        : null,
                  )
                else if (_openedOnCurrentWeek) ...<Widget>[
                  Text(
                    _initial!.source == TargetSource.exactWeek
                        ? 'This week has its own targets. Ongoing targets are enabled.'
                        : 'Using ongoing targets.',
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  RadioGroup<bool>(
                    groupValue: _useOngoing,
                    onChanged: (bool? value) {
                      if (editable && value != null) {
                        setState(() => _useOngoing = value);
                      }
                    },
                    child: Column(
                      children: <Widget>[
                        RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('This week only'),
                          value: false,
                          enabled: editable,
                        ),
                        RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('From this week onward'),
                          value: true,
                          enabled: editable,
                        ),
                      ],
                    ),
                  ),
                ] else
                  Text(
                    'Changes apply to these dates only. To change ongoing '
                    'targets, open the current week.',
                    style: context.text.metadata.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                const SizedBox(height: HearthSpacing.lg),
                _fields(<(TextEditingController, String)>[
                  (_kcal, 'kcal'),
                  (_protein, 'Protein'),
                  (_carbs, 'Carbs'),
                  (_fat, 'Fat'),
                ], editable: editable),
                const SizedBox(height: HearthSpacing.lg),
                Text('Fibre, sodium, cholesterol', style: context.text.body),
                const SizedBox(height: HearthSpacing.xxs),
                Text(
                  'Leave blank for the Daily Values — 28 g, 2,300 mg and '
                  '300 mg. Fibre is one to reach; the other two are budgets.',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: HearthSpacing.sm),
                _fields(<(TextEditingController, String)>[
                  (_fibre, 'Fibre g'),
                  (_sodium, 'Sodium mg'),
                  (_cholesterol, 'Chol. mg'),
                ], editable: editable),
              ],
              if (error != null) ...<Widget>[
                const SizedBox(height: HearthSpacing.md),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: context.text.body.copyWith(color: colors.error),
                  ),
                ),
              ],
              const SizedBox(height: HearthSpacing.lg),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: HearthSpacing.sm,
                overflowSpacing: HearthSpacing.sm,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: editable && _initial != null ? _save : null,
                    child: Text(_saving ? 'Saving…' : 'Save targets'),
                  ),
                ],
              ),
              if (sameAccount &&
                  _openedOnCurrentWeek &&
                  _hasOngoing) ...<Widget>[
                const SizedBox(height: HearthSpacing.xl),
                Text(
                  _dirty
                      ? 'Save your target changes before stopping carry-forward.'
                      : 'Keeps this week’s saved targets and any later '
                            'week-specific targets. Other later weeks will have no targets.',
                  style: context.text.metadata.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                TextButton(
                  onPressed: editable && !_dirty ? _stop : null,
                  child: const Text('Stop carrying forward after this week'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fields(
    List<(TextEditingController, String)> fields, {
    required bool editable,
  }) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final double scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final int columns = (constraints.maxWidth / (64 * scale)).floor().clamp(
        1,
        fields.length,
      );
      final double width =
          (constraints.maxWidth - HearthSpacing.sm * (columns - 1)) / columns;
      return Wrap(
        spacing: HearthSpacing.sm,
        runSpacing: HearthSpacing.md,
        children: <Widget>[
          for (final (TextEditingController controller, String label) in fields)
            SizedBox(
              width: width,
              child: _TargetField(
                controller: controller,
                label: label,
                enabled: editable,
                onChanged: (_) => setState(() => _error = null),
              ),
            ),
        ],
      );
    },
  );
}

class _TargetField extends StatelessWidget {
  const _TargetField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      ExcludeSemantics(
        child: Text(
          label,
          style: context.text.metadata.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
      const SizedBox(height: HearthSpacing.xs),
      Semantics(
        label: label,
        child: TextField(
          key: ValueKey<String>('target-$label'),
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: context.text.body,
        ),
      ),
    ],
  );
}
