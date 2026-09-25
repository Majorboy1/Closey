---
description: "Design token and styling rules for Closey UI files. Covers colour, typography, spacing, radii, motion, tap targets and component reuse."
name: "Design Tokens"
applyTo: "lib/features/**, lib/core/widgets/**"
---

# Design tokens

Every visual value resolves to a token. If you need a value that has no token, add
one to `lib/core/theme/` with a name describing its **purpose** (`coachSurface`),
not its appearance (`lightAmber`).

## Colours — `context.colors`

| Token | Use |
|---|---|
| `background`, `backgroundSunken` | page and banded backgrounds |
| `surface`, `surfaceRaised`, `surfaceSunken` | cards, sheets, inset wells |
| `border`, `borderStrong` | hairlines, emphasised outlines |
| `textPrimary`, `textSecondary`, `textTertiary` | the three text weights |
| `brand` / `brandText` / `textOnBrand` | fill / text-on-light / text-on-fill |
| `brandSoft`, `brandBorder` | tinted containers |
| `accent`, `accentText`, `accentSoft` | amber; verification highlights |
| `success`, `successText`, `successSoft` | sage; friendship, unlimited, positive |
| `danger`, `dangerSoft` | destructive |
| `coachSurface`, `coachBorder` | the AI coach card — never a normal card |
| `privateSurface` | private nudges |
| `chatMine`, `chatMineText`, `chatTheirs`, `chatTheirsText`, `chatTheirsBorder` | bubbles |
| `scrim`, `skeleton`, `shadow` | overlays, loading, elevation |

**`brand` is a fill, `brandText` is text.** They are separate because the brand
rose is legible as a background but not as text on light. Never use `brand` for
text on a light surface.

Literal colours are only acceptable **on top of user photographs** (scrims,
gradients), because those do not respond to the theme.

## Typography — `context.text`

Fraunces for brand moments: `displayLarge`, `displayMedium`, `displaySmall`,
`headlineLarge/Medium/Small`, and the coach's suggestion copy. Plus Jakarta Sans
for everything functional: `titleLarge/Medium/Small`, `bodyLarge/Medium/Small`,
`labelLarge/Medium/Small`.

`CloseyTypography.eyebrow` is the uppercase section label. `context.eyebrow()` in
`closey_typography.dart` is the convenience accessor.

## Spacing — `Gap`

Strict 4pt scale: `xxs 2, xs 4, sm 8, md 12, lg 16, xl 20, xxl 24, xxxl 32,
huge 40, giant 56`. `Gap.page` is the standard horizontal page padding.

Never write `EdgeInsets.all(13)`. Twenty-two files in the previous codebase mixed
tokens and literals in the same file, which is why nothing ever quite lined up.

## Shape — `Radii`, `Strokes`

Cards 20 (`Radii.lg`), sheets 32 (`Radii.allSheet`), pills fully round
(`Radii.pill`). Strokes: `hairline 1`, `thin 1.5`, `thick 2`, `ring 3`.

## Motion — `context.motion(...)`

`Motion.instant` (120ms) for micro-feedback, `Motion.quick` (220ms) for the
default, `Motion.moderate` (380ms) for entrances, `Motion.slow` (620ms) for
celebrations only. Curves: `standard`, `emphasized`, `overshoot`, `exit`.

Always wrap: `duration: context.motion(Motion.quick)`. This returns
`Duration.zero` when the user has reduce-motion enabled.

## Components

Reuse `lib/core/widgets/`: `CloseyButton`, `CloseyIconButton`, `CloseyChip`,
`CloseyTag`, `CloseyFilterBar`, `CloseyTextField`, `CloseyCodeField`,
`CloseyCard`, `CloseySectionHeader`, `CloseyBadge`, `CloseyListRow`,
`CloseyScaffold`, `CloseyAppBar`, `CloseyBottomBar`, `CloseyAvatar`,
`CloseyAvatarPair`, `CloseyLogo`, `CloseyWordmark`, `CloseySheet*`,
`AsyncSection`, `CloseySkeleton`, `CloseySkeletonList`, `CloseyEmptyState`,
`CloseyErrorState`, `CloseyErrorBanner`, `PhotoCarousel`, `Pressable`.

Build a new core widget only if it will be used by two or more screens. An earlier
version of this app grew five different card recipes, three icon-circle sizes and
two palettes by not following this.
