import SwiftUI

/// D47 (v1.4): the introduction. Four pages you swipe, one primary action, one quiet way out.
/// Everything it says is `Introduction.pages`; this view draws and never decides.
struct IntroductionView: View {
    enum Purpose {
        /// A first launch: ends on **Choose a plan**, with **Not now** beneath.
        case firstRun
        /// Settings → About → How the app works: the same pages, ending on **Done**.
        case reference
    }

    let purpose: Purpose
    /// First run only: the intro is dismissed and Add plan opens on the built-in picker.
    var choosePlan: () -> Void = {}
    let dismiss: () -> Void

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(Introduction.pages.enumerated()), id: \.offset) { index, item in
                    IntroPageView(page: item).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 14) {
                switch purpose {
                case .firstRun:
                    PrimaryButton(title: Introduction.choosePlan) { choosePlan() }
                    Button(Introduction.notNow) { dismiss() }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .reference:
                    PrimaryButton(title: Introduction.done) { dismiss() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
    }
}

private struct IntroPageView: View {
    let page: IntroPage

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image(systemName: page.symbol)
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(page.title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(page.body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
        .accessibilityElement(children: .combine)
    }
}
