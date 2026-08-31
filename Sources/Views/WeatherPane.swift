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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.04))

            PixelWeatherView(scene: scene)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 0) {
                content
                    .padding(.horizontal, 14)

                if weather.conditions != nil {
                    daylight
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
            }
        }
        .onAppear { weather.addSubscriber() }
        .onDisappear { weather.removeSubscriber() }
    }

    /// The day's arc, with the times it turns.
    @ViewBuilder
    private var daylight: some View {
        VStack(spacing: 2) {
            PixelDaylightGraph(
                sunrise: weather.conditions?.sunrise,
                sunset: weather.conditions?.sunset,
                accent: scene.accent
            )
            .frame(height: 40)

            HStack {
                label(icon: "sunrise", date: weather.conditions?.sunrise)
                Spacer()
                label(icon: "sunset", date: weather.conditions?.sunset)
            }
        }
    }

    private func label(icon: String, date: Date?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
            Text(date.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(.white.opacity(0.42))
    }

    @ViewBuilder
    private var content: some View {
        if weather.conditions != nil {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(weather.temperatureText ?? "—")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                        .monospacedDigit()

                    Text(scene.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(scene.accent.opacity(0.95))

                    if let place = weather.conditions?.placeName {
                        Text(place)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: weather.symbolName)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(scene.accent.opacity(0.9))
                    .shadow(color: scene.accent.opacity(0.35), radius: 8)
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
