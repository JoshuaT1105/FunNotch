//
//  WeatherPane.swift
//  FunNotch
//
//  What the home tab shows when nothing is playing.
//
//  The player is the reason most people open the notch, but it is blank
//  whenever the music is off, and a large empty rectangle is a bad first
//  impression. Weather fills it with something worth glancing at.
//

import SwiftUI

struct WeatherPane: View {
    @ObservedObject private var weather = WeatherManager.shared

    private var scene: WeatherScene {
        guard let conditions = weather.conditions else { return .cloudy }
        return WeatherScene.from(code: conditions.weatherCode, isDay: conditions.isDay)
    }

    private var isNight: Bool { !(weather.conditions?.isDay ?? true) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.04))

            // A new forecast crossfades into the next scene rather than cutting.
            PixelWeatherView(scene: scene, isNight: isNight)
                .id("\(scene)-\(isNight)")
                .transition(.opacity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            content
                .padding(.horizontal, 14)
        }
        .animation(.easeInOut(duration: 0.9), value: "\(scene)-\(isNight)")
        .onAppear { weather.addSubscriber() }
        .onDisappear { weather.removeSubscriber() }
    }

    @ViewBuilder
    private var content: some View {
        if weather.conditions != nil {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(weather.temperatureText ?? "—")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.97))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: weather.temperatureText)

                    Text(scene.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(scene.accent)

                    if let place = weather.conditions?.placeName {
                        Text(place)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                // The sky behind is a colour now, not black; a soft shadow
                // keeps the text clear of whatever is drifting past.
                .shadow(color: .black.opacity(0.45), radius: 3, y: 1)

                Spacer(minLength: 0)
            }
        } else {
            // No reading yet: either location was refused, or the first fetch
            // has not landed. Say which, rather than showing a blank box.
            VStack(spacing: 6) {
                Image(systemName: "location.slash")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                Text(weather.isLocationAuthorized ? "Getting the weather…" : "Weather needs location access")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                if !weather.isLocationAuthorized {
                    Button("Allow…") { weather.requestAccess() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
        }
    }
}
