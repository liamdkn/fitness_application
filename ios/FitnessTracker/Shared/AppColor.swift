import SwiftUI
import UIKit

/// Every colour the app uses, by what it means rather than what it looks
/// like. Views and widgets refer to these names and never to `.blue` or
/// `.green` directly, so changing how protein (or the whole app) looks is a
/// one-line edit here. Shared with the widget extension so the Live Activity
/// and widgets match the app.
nonisolated enum AppColor {
    // MARK: Brand

    /// The app's accent: tab bar, links, primary buttons, selected days,
    /// "Today" badges. Applied app-wide from `RootView` (`.tint`) and UIKit's
    /// appearance, so anything that just says `.tint`/default button follows it.
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.82, blue: 0.62, alpha: 1)
            : UIColor(red: 0.12, green: 0.42, blue: 0.28, alpha: 1)
    })

    /// The default button fill (see `AppButtonStyle`): a cool slate grey,
    /// kept separate from `accent` so buttons and highlights can differ.
    static let button = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.37, green: 0.40, blue: 0.46, alpha: 1)
            : UIColor(red: 0.45, green: 0.48, blue: 0.54, alpha: 1)
    })

    /// The screen background: a faint forest-to-black gradient in dark mode,
    /// soft warm green-grey in light mode, rather than
    /// a flat fill, so the glass buttons and cards have something to refract.
    static let backgroundTop = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.075, green: 0.13, blue: 0.10, alpha: 1)
            : UIColor(red: 0.96, green: 0.97, blue: 0.93, alpha: 1)
    })
    static let backgroundBottom = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.025, green: 0.045, blue: 0.032, alpha: 1)
            : UIColor(red: 0.89, green: 0.92, blue: 0.87, alpha: 1)
    })

    /// The glow that swells and fades behind the background gradient (see
    /// `AppBackground`).
    static let backgroundGlow = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.14, green: 0.48, blue: 0.30, alpha: 1)
            : UIColor(red: 0.40, green: 0.67, blue: 0.43, alpha: 1)
    })

    /// The light that runs round card edges when the app opens (see
    /// `AppIntro`): brighter than the background glow so it shows on glass.
    static let cardGlow = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.48, green: 0.82, blue: 0.60, alpha: 1)
            : UIColor(red: 0.17, green: 0.48, blue: 0.31, alpha: 1)
    })

    // MARK: Feedback

    /// Done, on target, a good score.
    static let success = Color.green
    /// Close to a limit, off target, worth a second look.
    static let warning = Color.orange
    /// Over a limit, a very low score, destructive actions.
    static let danger = Color.red
    /// Inline error messages.
    static let error = Color.red

    // MARK: Streaks and stars

    /// A star on the star chart, a perfect-week medal.
    static let star = Color.yellow
    /// The streak flame.
    static let flame = Color.orange
    /// A streak freeze.
    static let freeze = Color.cyan

    // MARK: Nutrition

    static let protein = Color(UIColor(red: 0.82, green: 0.38, blue: 0.26, alpha: 1))
    static let carbs = Color(UIColor(red: 0.28, green: 0.63, blue: 0.40, alpha: 1))
    static let fat = Color(UIColor(red: 0.88, green: 0.64, blue: 0.20, alpha: 1))
    static let calories = accent
    static let sodium = Color.orange
    static let fibre = Color.mint
    static let caffeine = Color.brown
    static let water = Color(UIColor(red: 0.18, green: 0.59, blue: 0.56, alpha: 1))
    /// Calories banked toward a planned treat.
    static let treat = Color.orange

    // MARK: Body and activity

    static let steps = accent
    static let weight = Color(UIColor(red: 0.47, green: 0.63, blue: 0.48, alpha: 1))
    static let heartRate = Color.red
    static let bedtime = Color.indigo
    /// A meal prep batch in the freezer.
    static let frozen = Color.cyan

    // MARK: Run stats and route

    static let runDistance = water
    static let runTime = fat
    static let runPace = accent
    static let runCalories = protein
    static let runElevation = carbs
    static let runPower = Color.mint
    static let runCadence = water
    static let routeStart = Color.green
    static let routeEnd = Color.red
}
