import Combine
import ComposableArchitecture
import SwiftUI

class PullToRefreshViewModel: ObservableObject {
  @Published var count = 0
  @Published var fact: String? = nil

  func incrementButtonTapped() {
    self.count += 1
  }

  func decrementButtonTapped() {
    self.count -= 1
  }

  @MainActor func getFact() async {
    withAnimation {
      self.fact = nil
    }

    await Task.sleep(2_000_000_000)

    do {
      let (data, _) = try await URLSession.shared.data(
        from: .init(string: "http://numbersapi.com/\(self.count)/trivia")!
      )
      withAnimation {
        self.fact = String(decoding: data, as: UTF8.self)
      }
    } catch {
      // TODO: do some error handling
    }
  }
}

// TODO: cancellation

struct VanillaPullToRefreshView: View {
  @ObservedObject var viewModel: PullToRefreshViewModel

  var body: some View {
    List {
      HStack {
        Button("-") { self.viewModel.decrementButtonTapped() }
        Text("\(self.viewModel.count)")
        Button("+") { self.viewModel.incrementButtonTapped() }
      }
      .buttonStyle(.plain)

      if let fact = self.viewModel.fact {
        Text(fact)
      }
    }
    .refreshable {
      await self.viewModel.getFact()
    }
  }
}

struct VanillaPullToRefresh_Previews: PreviewProvider {
  static var previews: some View {
    VanillaPullToRefreshView(viewModel: .init())
  }
}


// ---------------------


extension ViewStore {
  @available(iOS 15.0, macOS 12.0, macCatalyst 15, tvOS 15, watchOS 15, *)
  func send(_ action: Action, `while`: @escaping (State) -> Bool) async {
    self.send(action)

    var cancellable: Cancellable?

    await withTaskCancellationHandler(handler: { [cancellable] in cancellable?.cancel() }) {
      await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
        cancellable = self.publisher
          .filter { !`while`($0) }
          .prefix(1)
          .sink(
            receiveCompletion: { _ in
            continuation.resume(returning: ())
            _ = cancellable
            cancellable = nil
          },
            receiveValue: { _ in }
          )
      }
    }
  }
}

struct PullToRefreshState: Equatable {
  var count = 0
  var fact: String?
  var isLoading = false
}

enum PullToRefreshAction {
  case decrementButtonTapped
  case incrementButtonTapped
  case numberFactResponse(Result<String, NumbersApiError>)
  case refresh
}

struct PullToRefreshEnvironment {
  var mainQueue: AnySchedulerOf<DispatchQueue>
  var numberFact: (Int) -> Effect<String, NumbersApiError>
}

let pullToRefreshReducer = Reducer<
  PullToRefreshState,
  PullToRefreshAction,
  PullToRefreshEnvironment
> { state, action, environment in
  switch action {
  case .decrementButtonTapped:
    state.count -= 1
    state.fact = nil
    return .none

  case .incrementButtonTapped:
    state.count += 1
    state.fact = nil
    return .none

  case let .numberFactResponse(.success(fact)):
    state.fact = fact
    state.isLoading = false
    return .none

  case .numberFactResponse(.failure):
    state.isLoading = false
    return .none

  case .refresh:
    state.fact = nil
    state.isLoading = true
    return environment.numberFact(state.count)
      .delay(for: 2, scheduler: environment.mainQueue.animation())
      .catchToEffect()
      .map(PullToRefreshAction.numberFactResponse)
  }
}
  .debug()

struct PullToRefreshView: View {
  let store: Store<PullToRefreshState, PullToRefreshAction>

  var body: some View {
    WithViewStore(self.store) { viewStore in
      List {
        HStack {
          Button("-") { viewStore.send(.decrementButtonTapped, animation: .default) }
          Text("\(viewStore.count)")
          Button("+") { viewStore.send(.incrementButtonTapped, animation: .default) }
        }
        .buttonStyle(.plain)

        if let fact = viewStore.fact {
          Text(fact)
        }
      }
      .refreshable {
        await viewStore.send(.refresh, while: \.isLoading)
      }
    }
  }
}

struct PullToRefresh_Previews: PreviewProvider {
  static var previews: some View {
    PullToRefreshView(
      store: .init(
        initialState: .init(),
        reducer: pullToRefreshReducer,
        environment: PullToRefreshEnvironment(
          mainQueue: .main,
          numberFact: liveNumberFact(for:)
        )
      )
    )
  }
}