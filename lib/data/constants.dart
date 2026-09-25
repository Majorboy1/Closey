import '../core/config/app_config.dart';

/// Content constants shared by onboarding, discovery and reporting.
///
/// These were split across `lib/constants.ts` and inline literals in the Expo
/// app; here they live in one place so they can be reused by the Cloud
/// Functions prompt builder too.
abstract final class CloseyContent {
  /// Interest tags. Ordered roughly by how often they appear in the wild.
  static const List<String> interests = [
    'Gospel Music',
    'Travel',
    'Bible Study',
    'Worship',
    'Movies',
    'Fitness',
    'Cooking',
    'Photography',
    'Gaming',
    'Reading',
    'Tech / AI',
    'Fashion',
    'Football',
    'Hiking',
    'Art',
    'Coffee',
    'Live Music',
    'Podcasts',
    'Volunteering',
    'Dancing',
    'Cycling',
    'Board Games',
    'Writing',
    'Foodie',
  ];

  /// Hinge-style profile prompts. Gives both a conversation hook and — per the
  /// spec — useful raw material for the coach.
  static const List<String> promptQuestions = [
    'A cause I care about',
    'My ideal Sunday',
    "I'm known for",
    'Next on my list',
    'A movie that changed how I think',
    'Currently learning',
    'The way to my heart is',
    'I go crazy for',
    'Two truths and a lie',
  ];

  /// Guided starters for "3 things you love talking about".
  ///
  /// The spec calls this out as the fix for the coach's cold-start problem, but
  /// asked for "a short free-text or guided-tag prompt". Pure free text
  /// produced empty fields in the prototype, so this pairs a small tag set
  /// with the ability to type your own.
  static const List<String> conversationTopicSuggestions = [
    'Growing up',
    'Faith & meaning',
    'Big ideas I keep returning to',
    'Films & series',
    'Music that shaped me',
    'Food & cooking',
    'Work & ambition',
    'Travel stories',
    'Books',
    'Sport',
    'Technology & AI',
    'Family',
  ];

  static const List<String> reportReasons = [
    'Fake profile',
    'Inappropriate messages',
    'Asks for money or a scam',
    'Underage',
    'Harassment or threats',
    'Wants to leave the app',
    'Something else',
  ];

  static const List<String> communityGuidelines = [
    'Be a real person. One account, your own photos.',
    'Be kind. No harassment, hate speech or threats.',
    'Keep it on the app. Never send money to someone you met here.',
    'Respect boundaries. A no is a no, the first time.',
    'Report anything that feels wrong. We read every report.',
  ];

  /// Age-range presets offered in discovery preferences.
  static const List<AgeRangePreset> agePresets = [
    AgeRangePreset('18 – 24', 18, 24),
    AgeRangePreset('25 – 34', 25, 34),
    AgeRangePreset('35 – 44', 35, 44),
    AgeRangePreset('45+', 45, DiscoveryDefaults.maxAge),
    AgeRangePreset(
      'Any age',
      DiscoveryDefaults.minAge,
      DiscoveryDefaults.maxAge,
    ),
  ];

  /// Ready-made openers used by the offline coach fallback and the demo chat.
  static const List<String> fallbackOpeners = [
    'Okay, important question: what is your ideal Sunday, hour by hour?',
    'What is something you could talk about for an hour with no preparation?',
    'Settle this for me — best meal you have had this year, and where?',
    'What is a small thing that made you weirdly happy this week?',
  ];
}

class AgeRangePreset {
  const AgeRangePreset(this.label, this.min, this.max);
  final String label;
  final int min;
  final int max;

  bool matches(int lo, int hi) => lo == min && hi == max;
}
