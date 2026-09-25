import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/closey_colors.dart';
import '../../core/theme/closey_spacing.dart';
import '../../core/theme/closey_typography.dart';
import '../../core/widgets/async_section.dart';
import '../../core/widgets/closey_button.dart';
import '../../core/widgets/closey_chip.dart';
import '../../core/widgets/closey_scaffold.dart';
import '../../core/widgets/closey_surface.dart';
import '../../core/widgets/closey_text_field.dart';
import '../../data/constants.dart';
import '../../data/models/app_user.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/user_repository.dart';
import '../../state/services.dart';

/// Onboarding wizard.
///
/// Rebuilt from the Expo version, which stacked all four sections into one
/// scrolling page behind step pills and then gated the whole thing on a single
/// "Finish onboarding" button â€” so a validation failure on step 1 showed up
/// only at the very end.
///
/// What changed:
/// * **One question group per screen** with an animated progress bar, so the
///   commitment is visible and each step can validate itself before advancing.
/// * **Back navigation that preserves answers**, plus a "save and finish later"
///   exit that writes whatever exists. The old build lost everything if you
///   left.
/// * **The AI-context fields are explained.** "3 things you love talking about"
///   looks like busywork unless you say why it matters; the step now tells you
///   the coach uses it.
/// * **Photo step supports up to 6** with reordering-free add/remove, matching
///   the `photos[]` the schema always had but the UI never collected.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.editing = false});

  /// When true the wizard is reused to edit an existing profile and the final
  /// action saves instead of onboarding.
  final bool editing;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 4;

  final _page = PageController();
  int _step = 0;

  // Step 1 â€” basics.
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _bio = TextEditingController();
  DateTime? _birthDate;
  Gender? _gender;

  // Step 2 â€” interests + conversation topics.
  final Set<String> _interests = {};
  final List<String> _topics = [];
  final _topicInput = TextEditingController();
  final _topicChips = <String>{};

  // Step 3 â€” prompt.
  String? _promptQuestion;
  final _promptAnswer = TextEditingController();

  // Step 4 â€” photos + preferences.
  final List<XFile> _newPhotos = [];
  final List<String> _existingPhotos = [];
  final Set<String> _lookingFor = {};
  int _minAge = DiscoveryDefaults.defaultMinAge;
  int _maxAge = DiscoveryDefaults.defaultMaxAge;

  String? _error;
  bool _busy = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    for (final preset in CloseyContent.agePresets) {
      if (preset.label == '25 â€“ 34') {
        _minAge = preset.min;
        _maxAge = preset.max;
      }
    }
  }

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    _city.dispose();
    _bio.dispose();
    _topicInput.dispose();
    _promptAnswer.dispose();
    super.dispose();
  }

  void _prefillFrom(AppUser user) {
    if (_prefilled) return;
    _prefilled = true;

    _name.text = user.fullName;
    _city.text = user.city ?? '';
    _bio.text = user.bio ?? '';
    _birthDate = user.birthDate;
    _gender = user.gender;
    _interests.addAll(user.interests);
    _topics.addAll(user.conversationTopics);
    _promptQuestion = user.promptQuestion;
    _promptAnswer.text = user.promptAnswer ?? '';
    _existingPhotos.addAll(user.photos);
    _lookingFor.addAll(user.lookingFor);
    _minAge = user.minAge;
    _maxAge = user.maxAge;
  }

  // ------------------------------------------------------------ validation --

  /// Returns an error message, or null when the step is satisfied.
  String? _validateStep(int step) {
    switch (step) {
      case 0:
        if (_name.text.trim().length < 2) return 'Add your first name.';
        if (_birthDate == null) {
          return 'Add your date of birth â€” we need it to confirm you are 18+.';
        }
        if (!isAtLeast18(_birthDate!)) {
          return 'You must be 18 or over to use Closey.';
        }
      case 1:
        if (_interests.length < 3) {
          return 'Pick at least 3 interests. They are what the coach uses to find things you both like.';
        }
        if (_topics.length + _topicChips.length < 1) {
          return 'Add at least one thing you love talking about.';
        }
      case 2:
        if (_promptQuestion == null) return 'Choose a prompt to answer.';
        if (_promptAnswer.text.trim().length < 4) {
          return 'Give the prompt a short answer.';
        }
      case 3:
        if (_existingPhotos.isEmpty && _newPhotos.isEmpty) {
          return 'Add at least one photo so people know who they are talking to.';
        }
        if (_lookingFor.isEmpty) return 'Choose who you would like to see.';
    }
    return null;
  }

  void _next() {
    final error = _validateStep(_step);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _error = null);

    if (_step < _stepCount - 1) {
      setState(() => _step++);
      _page.animateToPage(
        _step,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step == 0) return;
    setState(() {
      _step--;
      _error = null;
    });
    _page.animateToPage(
      _step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  // ----------------------------------------------------------------- save --

  /// Writes whatever exists. Used both by the final step and by "finish later",
  /// so a partial profile is never lost.
  Future<void> _finish({bool partial = false}) async {
    final uid = ref.read(uidProvider);
    final user = ref.read(currentUserValueProvider);
    if (uid == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final users = ref.read(userRepositoryProvider);

      // Upload any newly picked photos first so the profile never references a
      // local file path.
      final uploaded = <String>[..._existingPhotos];
      for (final file in _newPhotos) {
        // `uploadPhoto` takes the XFile directly — no `dart:io` File, so this
        // compiles and runs on web as well as on mobile.
        final url = await users.uploadPhoto(uid: uid, file: file);
        uploaded.add(url);
      }

      final topics = <String>[
        ..._topicChips,
        if (_topicInput.text.trim().isNotEmpty) _topicInput.text.trim(),
      ];

      await users.updateProfile(
        uid,
        fullName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        birthDate: _birthDate,
        age: _birthDate != null ? ageFromBirthDate(_birthDate!) : null,
        gender: _gender,
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
        bio: _bio.text.trim().isEmpty ? null : _bio.text.trim(),
        photos: uploaded.isEmpty ? null : uploaded,
        interests: _interests.isEmpty ? null : _interests.toList(),
        conversationTopics: topics.isEmpty ? null : topics,
        promptQuestion: _promptQuestion,
        promptAnswer: _promptAnswer.text.trim().isEmpty
            ? null
            : _promptAnswer.text.trim(),
        lookingFor: _lookingFor.isEmpty ? null : _lookingFor.toList(),
        minAge: _minAge,
        maxAge: _maxAge,
        onboarded: _validateStep(0) == null && !partial
            ? true
            : user?.onboarded,
      );
    } on CloseyFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save your profile. $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 82, limit: 6);
    if (picked.isEmpty) return;
    setState(() {
      _newPhotos.addAll(picked);
      while (_newPhotos.length + _existingPhotos.length > 6) {
        _newPhotos.removeLast();
      }
    });
  }

  // ------------------------------------------------------------------ view --

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final user = ref.watch(currentUserValueProvider);
    if (user != null) _prefillFrom(user);

    final photoCount = _existingPhotos.length + _newPhotos.length;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _ProgressHeader(
              step: _step,
              total: _stepCount,
              onBack: _step == 0 ? null : _back,
              onLater: () => _finish(partial: true),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: CloseyErrorBanner(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
              ),

            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _BasicsStep(
                    name: _name,
                    city: _city,
                    bio: _bio,
                    gender: _gender,
                    birthDate: _birthDate,
                    onGender: (g) => setState(() => _gender = g),
                    onBirthDate: (d) => setState(() => _birthDate = d),
                  ),
                  _InterestsStep(
                    selected: _interests,
                    topics: _topics,
                    topicChips: _topicChips,
                    topicInput: _topicInput,
                    onToggleInterest: (label) => setState(() {
                      if (!_interests.remove(label)) _interests.add(label);
                    }),
                    onToggleTopicChip: (label) => setState(() {
                      if (!_topicChips.remove(label)) _topicChips.add(label);
                    }),
                    onAddTopic: () {
                      final text = _topicInput.text.trim();
                      if (text.isEmpty) return;
                      setState(() {
                        _topics.add(text);
                        _topicInput.clear();
                      });
                    },
                    onRemoveTopic: (t) => setState(() => _topics.remove(t)),
                  ),
                  _PromptStep(
                    question: _promptQuestion,
                    answer: _promptAnswer,
                    onQuestion: (q) => setState(() => _promptQuestion = q),
                  ),
                  _PhotosStep(
                    existing: _existingPhotos,
                    fresh: _newPhotos,
                    lookingFor: _lookingFor,
                    minAge: _minAge,
                    maxAge: _maxAge,
                    onAdd: _pickPhoto,
                    onRemoveExisting: (url) =>
                        setState(() => _existingPhotos.remove(url)),
                    onRemoveNew: (f) => setState(() => _newPhotos.remove(f)),
                    onToggleLookingFor: (v) => setState(() {
                      if (!_lookingFor.remove(v)) _lookingFor.add(v);
                    }),
                    onAgeRange: (min, max) => setState(() {
                      _minAge = min;
                      _maxAge = max;
                    }),
                  ),
                ],
              ),
            ),

            CloseyBottomBar(
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: CloseyButton(
                        label: 'Back',
                        variant: CloseyButtonVariant.secondary,
                        size: CloseyButtonSize.lg,
                        onPressed: _back,
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: Gap.md),
                  Expanded(
                    flex: 2,
                    child: CloseyButton(
                      label: _step == _stepCount - 1
                          ? (widget.editing
                                ? 'Save changes'
                                : 'Start meeting people')
                          : 'Continue',
                      size: CloseyButtonSize.lg,
                      loading: _busy,
                      fullWidth: true,
                      trailingIcon: _step == _stepCount - 1
                          ? null
                          : Icons.arrow_forward_rounded,
                      onPressed: _next,
                    ),
                  ),
                ],
              ),
            ),

            if (_step == 3 && photoCount == 0)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Text(
                  'A clear face photo gets 4x more replies.',
                  style: context.text.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Segmented progress bar plus a "finish later" escape hatch.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.step,
    required this.total,
    this.onBack,
    this.onLater,
  });

  final int step;
  final int total;
  final VoidCallback? onBack;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.md, Gap.page, Gap.md),
      child: Column(
        children: [
          Row(
            children: [
              if (onBack != null)
                Icon(
                  Icons.arrow_back_rounded,
                  size: 20,
                  color: colors.textSecondary,
                )
              else
                const SizedBox(width: 20),
              const Spacer(),
              Text(
                'Step ${step + 1} of $total',
                style: context.text.labelMedium?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onLater,
                child: Text(
                  'Later',
                  style: context.text.labelMedium?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Row(
            children: List.generate(total, (i) {
              final active = i <= step;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  height: 4,
                  margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: active ? colors.brand : colors.surfaceSunken,
                    borderRadius: Radii.pill,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- step one --

class _BasicsStep extends StatelessWidget {
  const _BasicsStep({
    required this.name,
    required this.city,
    required this.bio,
    required this.gender,
    required this.birthDate,
    required this.onGender,
    required this.onBirthDate,
  });

  final TextEditingController name;
  final TextEditingController city;
  final TextEditingController bio;
  final Gender? gender;
  final DateTime? birthDate;
  final ValueChanged<Gender> onGender;
  final ValueChanged<DateTime> onBirthDate;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final age = birthDate != null ? ageFromBirthDate(birthDate!) : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      children: [
        Text('Let us start simple', style: context.text.displaySmall),
        const SizedBox(height: Gap.sm),
        Text(
          'This is what people see first, so keep it you.',
          style: context.text.bodyLarge?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Gap.xxl),

        CloseyTextField(
          label: 'First name',
          controller: name,
          hint: 'Your first name',
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: Gap.lg),

        Text('DATE OF BIRTH', style: context.eyebrow()),
        const SizedBox(height: Gap.sm),
        Row(
          children: [
            Expanded(
              child: CloseyButton(
                label: birthDate == null
                    ? 'Choose a date'
                    : '${birthDate!.day}/${birthDate!.month}/${birthDate!.year}',
                icon: Icons.cake_outlined,
                variant: CloseyButtonVariant.secondary,
                fullWidth: true,
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        birthDate ??
                        DateTime(now.year - 25, now.month, now.day),
                    firstDate: DateTime(now.year - 100),
                    lastDate: DateTime(now.year - 18, now.month, now.day),
                    helpText: 'Your date of birth',
                  );
                  if (picked != null) onBirthDate(picked);
                },
              ),
            ),
            if (age != null) ...[
              const SizedBox(width: Gap.md),
              CloseyTag(label: '$age', tone: CloseyTagTone.brand),
            ],
          ],
        ),
        const SizedBox(height: Gap.lg),

        Text('I AM Aâ€¦', style: context.eyebrow()),
        const SizedBox(height: Gap.sm),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: Gender.values
              .map(
                (g) => CloseyChip(
                  label: g.label,
                  selected: gender == g,
                  onTap: () => onGender(g),
                  dense: true,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: Gap.lg),

        CloseyTextField(
          label: 'City',
          controller: city,
          hint: 'Lagos, London, Nairobiâ€¦',
          prefixIcon: Icons.location_on_outlined,
        ),
        const SizedBox(height: Gap.lg),

        CloseyTextField(
          label: 'About you',
          controller: bio,
          hint: 'A couple of sentences. What would a friend say about you?',
          maxLines: 4,
          maxLength: 280,
          helper: '280 characters',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- step two --

class _InterestsStep extends StatelessWidget {
  const _InterestsStep({
    required this.selected,
    required this.topics,
    required this.topicChips,
    required this.topicInput,
    required this.onToggleInterest,
    required this.onToggleTopicChip,
    required this.onAddTopic,
    required this.onRemoveTopic,
  });

  final Set<String> selected;
  final List<String> topics;
  final Set<String> topicChips;
  final TextEditingController topicInput;
  final ValueChanged<String> onToggleInterest;
  final ValueChanged<String> onToggleTopicChip;
  final VoidCallback onAddTopic;
  final ValueChanged<String> onRemoveTopic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      children: [
        Text('What are you into?', style: context.text.displaySmall),
        const SizedBox(height: Gap.sm),
        Text(
          'These feed the coach, so it can suggest things you both actually '
          'care about instead of random small talk.',
          style: context.text.bodyLarge?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Gap.lg),

        Row(
          children: [
            CloseyTag(
              label: '${selected.length} selected',
              tone: selected.length >= 3
                  ? CloseyTagTone.success
                  : CloseyTagTone.neutral,
              icon: selected.length >= 3
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
            ),
            if (selected.length < 3) ...[
              const SizedBox(width: Gap.sm),
              Text(
                'pick at least 3',
                style: context.text.bodySmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: Gap.lg),

        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: CloseyContent.interests
              .map(
                (label) => CloseyChip(
                  label: label,
                  selected: selected.contains(label),
                  onTap: () => onToggleInterest(label),
                  dense: true,
                ),
              )
              .toList(),
        ),

        const SizedBox(height: Gap.xxxl),
        Text(
          'Three things you love talking about',
          style: context.text.titleLarge,
        ),
        const SizedBox(height: Gap.xs),
        Text(
          'Not hobbies â€” actual subjects you could talk about for an hour. '
          'This is the single most useful thing you can give the coach.',
          style: context.text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Gap.lg),

        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: CloseyContent.conversationTopicSuggestions
              .map(
                (label) => CloseyChip(
                  label: label,
                  selected: topicChips.contains(label),
                  onTap: () => onToggleTopicChip(label),
                  dense: true,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: Gap.lg),

        Row(
          children: [
            Expanded(
              child: CloseyTextField(
                label: 'Or type your own',
                controller: topicInput,
                hint: 'e.g. why cities feel different at night',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAddTopic(),
              ),
            ),
            const SizedBox(width: Gap.sm),
            Padding(
              padding: const EdgeInsets.only(top: 26),
              child: CloseyIconButton(
                icon: Icons.add_rounded,
                filled: true,
                onPressed: onAddTopic,
                semanticLabel: 'Add topic',
              ),
            ),
          ],
        ),

        if (topics.isNotEmpty) ...[
          const SizedBox(height: Gap.md),
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: topics
                .map(
                  (t) => CloseyChip(
                    label: t,
                    selected: true,
                    onTap: () => onRemoveTopic(t),
                    icon: Icons.close_rounded,
                    dense: true,
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }
}

// -------------------------------------------------------------- step three --

class _PromptStep extends StatelessWidget {
  const _PromptStep({
    required this.question,
    required this.answer,
    required this.onQuestion,
  });

  final String? question;
  final TextEditingController answer;
  final ValueChanged<String> onQuestion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      children: [
        Text('Give them an opener', style: context.text.displaySmall),
        const SizedBox(height: Gap.sm),
        Text(
          'A prompt answer is the easiest thing for someone to reply to â€” and '
          'the coach reads it too.',
          style: context.text.bodyLarge?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Gap.xxl),

        ...CloseyContent.promptQuestions.map(
          (q) => Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: CloseyCard(
              onTap: () => onQuestion(q),
              tinted: question == q ? colors.brandSoft : null,
              borderColor: question == q ? colors.brand : null,
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      q,
                      style: context.text.titleSmall?.copyWith(
                        color: question == q ? colors.brandText : null,
                      ),
                    ),
                  ),
                  if (question == q)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: colors.brand,
                    ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: Gap.xl),
        if (question != null)
          CloseyTextField(
            label: question!,
            controller: answer,
            hint: 'Keep it short and specific',
            maxLines: 3,
            maxLength: 160,
            autofocus: true,
          )
        else
          Container(
            padding: const EdgeInsets.all(Gap.xl),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: Radii.allMd,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_upward_rounded,
                  size: 18,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    'Pick a prompt above to answer it.',
                    style: context.text.bodyMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// --------------------------------------------------------------- step four --

class _PhotosStep extends StatelessWidget {
  const _PhotosStep({
    required this.existing,
    required this.fresh,
    required this.lookingFor,
    required this.minAge,
    required this.maxAge,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
    required this.onToggleLookingFor,
    required this.onAgeRange,
  });

  final List<String> existing;
  final List<XFile> fresh;
  final Set<String> lookingFor;
  final int minAge;
  final int maxAge;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemoveExisting;
  final ValueChanged<XFile> onRemoveNew;
  final ValueChanged<String> onToggleLookingFor;
  final void Function(int min, int max) onAgeRange;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = existing.length + fresh.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.xxl),
      children: [
        Text('Photos, then preferences', style: context.text.displaySmall),
        const SizedBox(height: Gap.sm),
        Text(
          'Up to 6 photos. Your first one is your profile picture everywhere.',
          style: context.text.bodyLarge?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Gap.xl),

        Row(
          children: [
            CloseyTag(
              label: '$total of 6',
              tone: total > 0 ? CloseyTagTone.success : CloseyTagTone.neutral,
            ),
            const Spacer(),
            if (total > 0)
              Text(
                'Tap a photo to remove it',
                style: context.text.bodySmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.md),

        Wrap(
          spacing: Gap.md,
          runSpacing: Gap.md,
          children: [
            for (final url in existing)
              _PhotoTile(
                imageUrl: url,
                isPrimary: existing.first == url,
                onRemove: () => onRemoveExisting(url),
              ),
            for (final file in fresh)
              _PhotoTile(
                file: file,
                isPrimary: existing.isEmpty && fresh.first == file,
                onRemove: () => onRemoveNew(file),
              ),
            if (total < 6) _AddPhotoTile(onTap: onAdd),
          ],
        ),

        const SizedBox(height: Gap.xxxl),
        Text('Who would you like to see?', style: context.text.titleLarge),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: LookingFor.values
              .map(
                (o) => CloseyChip(
                  label: o.label,
                  selected: lookingFor.contains(o.wire),
                  onTap: () => onToggleLookingFor(o.wire),
                  dense: true,
                ),
              )
              .toList(),
        ),

        const SizedBox(height: Gap.xl),
        Text('Age range', style: context.text.titleLarge),
        const SizedBox(height: Gap.xs),
        Text(
          'Between $minAge and $maxAge',
          style: context.text.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Gap.md),
        RangeSlider(
          values: RangeValues(minAge.toDouble(), maxAge.toDouble()),
          min: DiscoveryDefaults.minAge.toDouble(),
          max: DiscoveryDefaults.maxAge.toDouble(),
          divisions: DiscoveryDefaults.maxAge - DiscoveryDefaults.minAge,
          labels: RangeLabels('$minAge', '$maxAge'),
          activeColor: colors.brand,
          inactiveColor: colors.surfaceSunken,
          onChanged: (v) => onAgeRange(v.start.round(), v.end.round()),
        ),
        const SizedBox(height: Gap.lg),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: CloseyContent.agePresets
              .map(
                (p) => CloseyChip(
                  label: p.label,
                  selected: p.matches(minAge, maxAge),
                  onTap: () => onAgeRange(p.min, p.max),
                  dense: true,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    this.imageUrl,
    this.file,
    required this.isPrimary,
    required this.onRemove,
  });

  final String? imageUrl;
  final XFile? file;
  final bool isPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onRemove,
      child: SizedBox(
        width: 104,
        height: 132,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: Radii.allMd,
                child: file != null
                    ? FutureBuilder(
                        future: file!.readAsBytes(),
                        builder: (context, snap) => snap.hasData
                            ? Image.memory(snap.data!, fit: BoxFit.cover)
                            : ColoredBox(color: colors.surfaceSunken),
                      )
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            ColoredBox(color: colors.surfaceSunken),
                      ),
              ),
            ),
            if (isPrimary)
              Positioned(
                left: 6,
                bottom: 6,
                child: CloseyTag(label: 'Main', tone: CloseyTagTone.brand),
              ),
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.scrim,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        height: 132,
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: Radii.allMd,
          border: Border.all(color: colors.borderStrong, width: Strokes.thin),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_a_photo_outlined,
              size: 22,
              color: colors.textSecondary,
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'Add photo',
              style: context.text.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
