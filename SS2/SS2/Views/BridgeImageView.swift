import SwiftUI
import Inject

struct BridgeImageView: View {
    @ObserveInjection var inject
    @State private var imageData: Data?
    @State private var isLoading = true
    @State private var isExpanded = false
    
    var body: some View {
        ZStack {
            if let imageData = imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: isExpanded ? .fit : .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: isExpanded ? nil : 220)
                    .offset(y: 25)
                    .clipped()
                    .opacity(isLoading ? 0.5 : 1.0)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.top, 4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .cornerRadius(12)
                    .padding(.horizontal)
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