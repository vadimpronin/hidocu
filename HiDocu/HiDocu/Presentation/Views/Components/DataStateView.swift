//
//  DataStateView.swift
//  HiDocu
//
//  Generic container that switches between loading, empty, and content states.
//  Replaces .overlay-based empty state patterns to prevent rendering empty tables.
//

import SwiftUI

struct DataStateView<Content: View, EmptyContent: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let emptyContent: () -> EmptyContent

    var body: some View {
        if isLoading && isEmpty {
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty {
            emptyContent()
        } else {
            content()
        }
    }
}
