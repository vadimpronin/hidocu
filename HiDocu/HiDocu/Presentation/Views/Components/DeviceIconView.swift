//
//  DeviceIconView.swift
//  HiDocu
//
//  Shared device icon component showing device model image or SF symbol fallback.
//  Used in device headers (64pt), recording source headers, and recording table rows (16pt).
//

import SwiftUI

struct DeviceIconView: View {
    let model: DeviceModel?
    var size: CGFloat = 64

    var body: some View {
        Group {
            if let model, let imageName = model.imageName {
                // Asset images always use resizable
                Image(imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .foregroundStyle(.secondary)
            } else if let model {
                // SF symbols: use font-based sizing for small icons, resizable for large
                if size <= 24 {
                    Image(systemName: model.sfSymbolName)
                        .font(.system(size: size * 0.8))
                        .frame(width: size, height: size)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: model.sfSymbolName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .foregroundStyle(.secondary)
                }
            } else {
                // Nil model fallback (unknown source)
                if size <= 24 {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: size * 0.8))
                        .frame(width: size, height: size)
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
