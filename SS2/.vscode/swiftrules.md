## General Guidelines
1. Use the latest SwiftUI APIs and features whenever possible.
2. Implement `async/await` for asynchronous operations.
3. Write clean, readable, and well-structured code.
4. Follow the VIPER architecture to ensure modularity and scalability.

## VIPER Architecture Overview
Each module in your SwiftUI app should follow the VIPER structure:

### 1. **View**
   - The SwiftUI `View` handles user interface (UI) rendering and user interactions.
   - Import the `Inject` framework to enable hot reloading.
   - Use `@ObserveInjection` to monitor changes for hot reloading.
   - Use the `.enableInjection()` modifier in the view body.

   ```swift
   import SwiftUI
   import Inject

   struct YourViewName: View {
       @ObserveInjection var inject
       let presenter: YourPresenterProtocol

       var body: some View {
           VStack {
               // UI elements here
           }
           .enableInjection()
       }
   }
   ```

### 2. **Interactor**
   - The `Interactor` handles business logic and communicates with external data sources (e.g., APIs, databases).
   - Use protocols to define the interaction between the `Presenter` and `Interactor`.

   ```swift
   protocol YourInteractorProtocol {
       func fetchData() async throws -> [YourEntity]
   }

   final class YourInteractor: YourInteractorProtocol {
       func fetchData() async throws -> [YourEntity] {
           // Fetch or compute data
       }
   }
   ```

### 3. **Presenter**
   - The `Presenter` prepares data for the `View` and handles communication between the `View` and `Interactor`.
   - Use protocols to abstract the `Presenter` logic.

   ```swift
   protocol YourPresenterProtocol: ObservableObject {
       var data: [YourEntity] { get }
       func loadData() async
   }

   final class YourPresenter: YourPresenterProtocol {
       @Published private(set) var data: [YourEntity] = []
       private let interactor: YourInteractorProtocol

       init(interactor: YourInteractorProtocol) {
           self.interactor = interactor
       }

       func loadData() async {
           do {
               data = try await interactor.fetchData()
           } catch {
               // Handle error
           }
       }
   }
   ```

### 4. **Entity**
   - Define simple data models used by the `Interactor` and `Presenter`.

   ```swift
   struct YourEntity: Identifiable {
       let id: UUID
       let name: String
   }
   ```

### 5. **Router**
   - The `Router` handles navigation logic and module creation.

   ```swift
   protocol YourRouterProtocol {
       func createModule() -> YourViewName
   }

   final class YourRouter: YourRouterProtocol {
       func createModule() -> YourViewName {
           let interactor = YourInteractor()
           let presenter = YourPresenter(interactor: interactor)
           return YourViewName(presenter: presenter)
       }
   }
   ```

## Hot Reloading Setup
To enable hot reloading in all SwiftUI views:
1. **Import the Inject framework** in the `View`.
2. **Add the `@ObserveInjection` property wrapper**.
3. **Use the `.enableInjection()` modifier** in the main body of the view.

Example:
```swift
import SwiftUI
import Inject

struct ExampleView: View {
    @ObserveInjection var inject
    var body: some View {
        Text("Hello, VIPER!")
            .enableInjection()
    }
}
```

## State Management
1. Use `@Published` properties in the `Presenter` to manage and update state.
2. Avoid using `@State` or `@StateObject` directly in the `View`. Instead, rely on the `Presenter` for state.
3. Pass dependencies via initializers to ensure clear and testable code.

## Performance Optimization
1. Use `LazyVStack`, `LazyHStack`, or `LazyVGrid` for large lists or grids to improve performance.
2. Optimize `ForEach` loops by providing stable and unique identifiers.

## Reusable Components
1. Implement custom view modifiers for shared styling and behavior.
2. Use extensions to add reusable functionality to existing types.

## Accessibility
1. Add accessibility modifiers to all UI elements.
2. Support Dynamic Type for text scaling.
3. Provide clear accessibility labels and hints.

## SwiftUI Lifecycle
1. Use the `App` protocol and `@main` for the app entry point.
2. Implement `Scene` for managing app structure.
3. Use appropriate lifecycle methods like `onAppear` and `onDisappear`.

## Data Flow
1. Use protocols to define communication between VIPER components.
2. Implement proper error handling and data propagation in the `Interactor`.

## Testing
1. Write unit tests for `Interactor` and `Presenter` logic.
2. Implement UI tests for critical user flows.
3. Use `PreviewProvider` for rapid UI iteration and visual validation.

## SwiftUI-specific Patterns
1. Use `@Binding` for two-way data flow when needed.
2. Implement custom `PreferenceKey` for child-to-parent communication.
3. Utilize `@Environment` for dependencies shared across multiple views.

## Code Style and Formatting
1. Follow Swift naming conventions and style guidelines.
2. Use tools like SwiftLint to enforce consistent code style.