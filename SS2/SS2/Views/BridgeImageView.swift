import SwiftUI
import Inject

struct BridgeImageView: View {
    @ObserveInjection var inject
    @State private var imageData: Data?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if let imageData = imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 250)
                    .clipped()
                    .opacity(isLoading ? 0.5 : 1.0)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 250)
            }
            
            if isLoading {
                ProgressView()
            }
        }
        .onAppear(perform: loadImage)
        .task {
            // Update image every 30 seconds
            while true {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                loadImage()
            }
        }
        .enableInjection()
    }
    
    private func loadImage() {
        Task {
            isLoading = true
            do {
                let url = URL(string: "https://raw.githubusercontent.com/danielraffel/ggb/main/ggb.screenshot.png")!
                let (data, _) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    imageData = data
                    isLoading = false
                }
            } catch {
                print("Error loading image: \(error)")
                isLoading = false
            }
        }
    }
} 