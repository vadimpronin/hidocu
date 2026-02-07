//
//  BatteryIndicatorView.swift
//  HiDocu
//
//  Battery level indicator with icon and percentage.
//

import SwiftUI

struct BatteryIndicatorView: View {
    let battery: DeviceBatteryInfo

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIconName)
                .foregroundStyle(batteryColor)
            Text("\(battery.percentage)%")
                .font(.caption)
                .foregroundStyle(.secondary)
            if battery.state == .charging {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Battery \(battery.percentage) percent\(battery.state == .charging ? ", charging" : "")")
    }

    private var batteryIconName: String {
        switch battery.percentage {
        case 0..<15:   return "battery.0percent"
        case 15..<40:  return "battery.25percent"
        case 40..<60:  return "battery.50percent"
        case 60..<85:  return "battery.75percent"
        default:       return "battery.100percent"
        }
    }

    private var batteryColor: Color {
        if battery.percentage < 15 { return .red }
        if battery.percentage < 30 { return .orange }
        return .green
    }
}
