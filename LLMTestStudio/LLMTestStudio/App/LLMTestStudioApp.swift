import SwiftUI

@main
struct LLMTestStudioApp: App {
    @State private var viewModel = TestStudioViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .defaultSize(width: 1100, height: 750)
    }
}
