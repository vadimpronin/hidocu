import SwiftUI
import LLMService

struct ContentView: View {
    @Bindable var viewModel: TestStudioViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VSplitView {
                ChatView(viewModel: viewModel)
                    .frame(minHeight: 300)

                VStack(spacing: 0) {
                    DebugControlsView(viewModel: viewModel)
                    Divider()
                    LogView(viewModel: viewModel)
                }
                .frame(minHeight: 150, idealHeight: 200)
            }
        }
        .navigationTitle("LLM Test Studio")
        .task {
            await viewModel.loadModels()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            ProviderListView(viewModel: viewModel)
            Divider()
            ModelListView(viewModel: viewModel)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }
}
