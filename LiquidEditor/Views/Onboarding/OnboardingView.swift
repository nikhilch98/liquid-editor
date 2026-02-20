// OnboardingView.swift
// LiquidEditor
//
// First-launch tutorial that introduces the app's key features.
// Displays a swipeable page view with styled icons inside gradient circles,
// custom page indicators, and haptic feedback.
//
// Matches Flutter OnboardingFlow + OnboardingPage layout:
// - 64pt icon INSIDE 160pt circle with gradient border (accent at 0.2-0.05 opacity),
//   1pt accent border, and 30pt blur glow shadow
// - Custom page indicators: active = 24x8pt elongated capsule, inactive = 8x8pt circle
//   with 200ms animation
// - Next/Get Started button uses .borderedProminent with .tint(.blue)
// - Skip button visible on ALL pages (including last)
// - Haptics: selectionClick on page change, lightImpact on next, mediumImpact on complete
//
// Pure SwiftUI with iOS 26 native styling. Uses TabView with
// .page style but with custom dots overlay.

import SwiftUI

// MARK: - OnboardingPage

/// A single page of onboarding content.
private struct OnboardingPage: Sendable, Identifiable {
    let id: Int
    let iconName: String
    let title: String
    let description: String
    let accentColor: Color
}

// MARK: - OnboardingView

/// First-launch onboarding flow.
///
/// Presents a series of swipeable pages introducing the app's
/// key features. Dismisses when the user taps "Get Started"
/// on the final page, or "Skip" at any point.
///
/// Sets the `hasSeenOnboarding` preference on completion.
struct OnboardingView: View {

    // MARK: - State

    /// Current page index.
    @State private var currentPage: Int = 0

    /// Dismiss action for full-screen cover presentation.
    @Environment(\.dismiss) private var dismiss

    // MARK: - Callbacks

    /// Called when onboarding is completed or skipped.
    let onComplete: @MainActor () -> Void

    // MARK: - Haptic Generators

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Pages

    /// The onboarding pages to display.
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            iconName: "play.rectangle.fill",
            title: "Welcome to Liquid Editor",
            description: "Your videos deserve a premium editing experience. Craft stunning content with professional tools.",
            accentColor: .blue
        ),
        OnboardingPage(
            id: 1,
            iconName: "square.and.arrow.down.fill",
            title: "Import a Video",
            description: "Tap the + button to import a video from your photo library. Supported formats include MP4, MOV, and HEVC.",
            accentColor: .green
        ),
        OnboardingPage(
            id: 2,
            iconName: "timeline.selection",
            title: "Timeline Basics",
            description: "Scroll to navigate your timeline. Pinch to zoom in for precise frame-level editing. Tap a clip to select it.",
            accentColor: .orange
        ),
        OnboardingPage(
            id: 3,
            iconName: "scissors",
            title: "Trim and Split",
            description: "Drag clip edges to trim. Use the Split tool to cut at the playhead position, creating two separate clips.",
            accentColor: .red
        ),
        OnboardingPage(
            id: 4,
            iconName: "person.crop.rectangle.fill",
            title: "Smart Tracking",
            description: "Automatically detect and track people in your video. Use Auto Reframe to keep subjects perfectly framed.",
            accentColor: .purple
        ),
        OnboardingPage(
            id: 5,
            iconName: "sparkles",
            title: "Effects and Adjustments",
            description: "Apply speed changes, volume adjustments, and keyframe animations to bring your edits to life.",
            accentColor: .pink
        ),
        OnboardingPage(
            id: 6,
            iconName: "square.and.arrow.up.fill",
            title: "Export and Share",
            description: "Choose a resolution preset and export your masterpiece directly to your photo library.",
            accentColor: .cyan
        ),
    ]

    /// Whether the current page is the last page.
    private var isLastPage: Bool {
        currentPage == pages.count - 1
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(white: 0.12),
                    Color.black,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button (top right) - visible on ALL pages
                skipButton

                // Page content (using TabView for swiping)
                TabView(selection: $currentPage) {
                    ForEach(pages) { page in
                        pageView(for: page)
                            .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: currentPage) { _, _ in
                    selectionFeedback.selectionChanged()
                }

                // Custom page indicators
                customPageIndicators
                    .padding(.bottom, LiquidSpacing.xxl)

                // Bottom button
                bottomButton
                    .padding(.horizontal, 40)
                    .padding(.bottom, 50)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Skip Button (always visible)

    private var skipButton: some View {
        HStack {
            Spacer()
            Button("Skip") {
                completeOnboarding()
            }
            .font(LiquidTypography.body)
            .foregroundStyle(LiquidColors.textSecondary)
            .padding(.trailing, LiquidSpacing.xxl)
            .padding(.top, LiquidSpacing.lg)
        }
        .frame(height: LiquidSpacing.minTouchTarget)
        .accessibilityLabel("Skip onboarding")
        .accessibilityHint("Skips the tutorial and goes to the main screen")
    }

    // MARK: - Page View

    /// Content for a single onboarding page.
    private func pageView(for page: OnboardingPage) -> some View {
        VStack(spacing: 40) {
            Spacer(minLength: LiquidSpacing.xl)

            // Icon inside gradient circle
            iconCircle(for: page)

            VStack(spacing: LiquidSpacing.md) {
                // Title
                Text(page.title)
                    .font(LiquidTypography.title2)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LiquidSpacing.xxxl)

                // Description
                Text(page.description)
                    .font(LiquidTypography.body)
                    .foregroundStyle(LiquidColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title). \(page.description)")
    }

    // MARK: - Icon Circle

    /// 64pt icon inside a 160pt `.ultraThinMaterial` circle with gradient tint, accent border, and glow shadow.
    private func iconCircle(for page: OnboardingPage) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    page.accentColor.opacity(0.2),
                                    page.accentColor.opacity(0.05),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .frame(width: 160, height: 160)
                .overlay(
                    Circle()
                        .stroke(page.accentColor.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: page.accentColor.opacity(0.2), radius: 30)

            Image(systemName: page.iconName)
                .font(.system(size: 64))
                .foregroundStyle(page.accentColor)
                .symbolRenderingMode(.hierarchical)
        }
    }

    // MARK: - Custom Page Indicators

    private var customPageIndicators: some View {
        HStack(spacing: LiquidSpacing.sm) {
            ForEach(0..<pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? LiquidColors.primary : Color.white.opacity(0.3))
                    .frame(
                        width: index == currentPage ? 24 : LiquidSpacing.sm,
                        height: LiquidSpacing.sm
                    )
                    .animation(.easeInOut(duration: 0.2), value: currentPage)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(currentPage + 1) of \(pages.count)")
    }

    // MARK: - Bottom Button

    private var bottomButton: some View {
        Button {
            if isLastPage {
                mediumImpact.impactOccurred()
                completeOnboarding()
            } else {
                lightImpact.impactOccurred()
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage += 1
                }
            }
        } label: {
            Text(isLastPage ? "Get Started" : "Next")
                .font(LiquidTypography.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
        }
        .buttonStyle(.borderedProminent)
        .tint(LiquidColors.primary)
        .accessibilityLabel(isLastPage ? "Get Started" : "Next page")
        .accessibilityHint(isLastPage ? "Completes onboarding and opens the app" : "Goes to the next onboarding page")
    }

    // MARK: - Completion

    /// Finish onboarding and dismiss.
    private func completeOnboarding() {
        mediumImpact.impactOccurred()
        onComplete()
        dismiss()
    }
}
