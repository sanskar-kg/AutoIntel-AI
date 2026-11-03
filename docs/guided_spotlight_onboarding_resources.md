# Guided Spotlight Onboarding: Resources and Implementation Brief

## Objective

Implement a first-launch, step-by-step guided onboarding tour using **spotlight coach marks**. Do not use generic tooltips fixed at the bottom of the screen.

The intended experience:
- Highlight one real UI element at a time, such as a bottom-navigation tab.
- Dim the rest of the screen with a translucent overlay.
- Leave a transparent spotlight around the active element.
- Anchor a tooltip near the highlighted element.
- Advance only through the intended user interaction or an explicit Next action.
- Persist completion so onboarding does not replay on every app launch.

## Important design constraint

**Use the app's existing colors only. Do not introduce new brand colors, accent colors, gradients, or an unrelated onboarding palette.**

Before implementing:
1. Inspect the existing theme, design tokens, color constants, typography, spacing, and component styles.
2. Reuse the app's existing colors for tooltip surfaces, text, borders, buttons, progress indicators, and spotlight accents.
3. For the dimmed overlay, use a black or neutral overlay with transparency if compatible with the existing design system. Do not change the app's theme colors to create the dimming effect.
4. Match the existing app's typography, corner radii, button styles, and icon style.
5. If a required visual treatment cannot be created using existing tokens, explain the limitation and ask before adding a new token.

## Recommended resources

### 1. ShowcaseView for Flutter
Recommended first option. Review the package documentation, source code, and example app before implementation.

- Package: https://pub.dev/packages/showcaseview
- GitHub repository: https://github.com/SimformSolutionsPvtLtd/showcaseview

Investigate sequential widget highlighting, custom tooltip content, target positioning, animation, scrolling, and lifecycle/navigation behavior. Check the current API and compatibility with the app's Flutter version.

### 2. Tutorial Coach Mark for Flutter
Alternative if ShowcaseView does not support the required behavior or desired visual control.

- Package: https://pub.dev/packages/tutorial_coach_mark
- GitHub repository: https://github.com/RafaelBarbosatec/tutorial_coach_mark

Investigate `GlobalKey`-based targets, circular and rounded highlights, tooltip placement, Skip, and programmatic progression. Verify the current API before coding.

### 3. Spotlight Tutorial
Another package to evaluate if the first two options do not fit the app.

- Package: https://pub.dev/packages/spotlight_tutorial

Review maintenance, compatibility, examples, and interaction behavior before choosing it.

### 4. Custom implementation references
Consider these only if existing packages cannot satisfy the requirements. Verify that each repository is accessible, maintained, and compatible before using its code.

- https://github.com/Thanasis-Traitsis/flutter_spotlight
- https://github.com/youseflabs-k/coachmark

### 5. Video and written learning resources
Use these to understand the implementation pattern. Videos may use older APIs, so follow current package documentation for code.

- YouTube, Flutter ShowCaseView tutorial: https://www.youtube.com/watch?v=o4Hcwkr8t18
- Written TutorialCoachMark guide: https://davidserrano.io/use-this-to-explain-how-to-use-your-app-flutter-pro-tip-2

## Implementation prompt for the AI coding agent

### Task: Replace bottom tooltips with interactive guided spotlight onboarding

Inspect the existing code first. Identify the current onboarding implementation, navigation structure, state management, persistence mechanism, theme, and Flutter/dependency versions. Then choose the smallest reliable implementation.

#### Visual behavior
1. Display a full-screen, semi-transparent dimming overlay.
2. Keep the current target visible through a transparent spotlight cutout.
3. Use a circle for icon-only targets and a rounded rectangle for larger controls when appropriate.
4. Position the tooltip near the target, preferably above a bottom-navigation item when there is enough room. Prevent clipping and respect safe areas.
5. Animate transitions smoothly without flicker or stale target positions.
6. **Use only colors already present in the app's theme or design tokens.** Do not invent a new color palette. The dimming layer may use a neutral translucent overlay, while tooltip surfaces, text, borders, buttons, and indicators must follow existing app styles.
7. Reuse existing typography, spacing, radius, shadows, and button components where practical.

#### Example flow
1. On the first eligible launch, wait until the home screen and its target widgets are mounted.
2. Highlight only the first bottom-navigation tab. Dim all other areas.
3. Show a short tooltip describing the first tab.
4. When the user taps the highlighted tab, allow the intended navigation action and advance the tour at the correct point in the navigation lifecycle.
5. Highlight the second tab and update the tooltip.
6. Continue to the third tab and any additional targets in the intended order.
7. Provide Skip and Finish actions. Back is optional.
8. If a step targets a widget on another screen, navigate first, wait for the destination widget to mount, then show the next spotlight.

Do not assume that every step can be handled by merely incrementing an integer. Account for actual navigation state and widget lifecycle.

#### Interaction and accessibility
- Unrelated taps must not accidentally trigger controls behind the overlay.
- The active target should respond as intended. If the package cannot pass taps through to it safely, implement an explicit, clear Next action instead of simulating unreliable tap-through behavior.
- Ensure Skip and Finish remain accessible.
- Add suitable semantics and support text scaling.
- Handle smaller screens, safe areas, scrolling, and Android/iOS differences.
- Avoid hardcoded screen coordinates. Use stable widget references such as `GlobalKey`s or the package's supported target mechanism.

#### Persistence
- Use the app's existing persistence solution.
- Mark onboarding complete after Finish, and decide deliberately whether Skip should also mark it complete.
- Do not replay the tour on every launch.
- If appropriate, provide a way to replay the tour from Settings or Help.

#### Package selection
1. Evaluate ShowcaseView first.
2. Evaluate TutorialCoachMark if needed.
3. Choose one solution unless the existing architecture genuinely requires otherwise.
4. Check package maintenance, current API, and Flutter-version compatibility.
5. Avoid unnecessary dependencies and unrelated refactoring.

#### Acceptance criteria
- The first eligible launch shows a spotlight around the first navigation tab, not a tooltip fixed at the bottom.
- The rest of the screen is dimmed.
- The tooltip is correctly anchored and does not obscure the target.
- The next step appears only after the intended action or explicit Next action.
- Navigation between screens does not leave the overlay attached to stale coordinates.
- Skip and Finish dismiss the tour and persist the completion state.
- All UI styling uses the app's existing colors and design system.
- Existing app behavior remains intact.
- Run relevant checks and report what was actually verified on a simulator or device.

#### Required workflow
1. Briefly report the existing onboarding implementation and relevant theme/color sources found.
2. Recommend the package and explain why it fits.
3. Implement the smallest reliable change.
4. Run formatting, analysis, and relevant tests/build checks available in the project.
5. Report changed files, the implemented flow, checks performed, and any behavior not verified.

Do not claim that device behavior is verified unless it was actually tested.

## Suggested step copy

Keep each tooltip concise and specific to the actual feature. For example:

- **Home:** “Your overview starts here.”
- **Second tab:** “Explore your [feature name] here.”
- **Third tab:** “Manage your [feature name] here.”

Replace these examples with accurate descriptions based on the actual app. Do not invent features.

## Final reminder

The task is not simply to move the existing tooltip higher on the screen. It is to implement a **target-aware, interactive, sequential spotlight tour**, styled entirely with the app's existing colors and design system.
