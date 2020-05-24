import ComposableArchitecture
import ComposableCoreMotion
import CoreMotion
import SwiftUI

private let readMe = """
  This demonstrates how to work with the MotionManager API from Apple's Motion framework.

  Unfortunately the Motion APIs are not available in SwiftUI previews or simulators. However, \
  thanks to how the Composable Architecture models its dependencies and effects, it is trivial \
  to substitute a mock MotionClient into the SwiftUI preview so that we can still play around with \
  its basic functionality.

  Here we are creating a mock MotionClient that simulates motion data by running a timer that \
  emits sinusoidal values.
  """

struct AppState: Equatable {
  var alertTitle: String?
  var facingDirection: Direction?
  var initialAttitude: Attitude?
  var isRecording = false
  var z: [Double] = []

  enum Direction {
    case backward
    case forward
  }
}

enum AppAction: Equatable {
  case alertDismissed
  case motionUpdate(Result<DeviceMotion, MotionManager.Error>)
  case recordingButtonTapped
}

struct AppEnvironment {
  var motionManager: MotionManager
}

let appReducer = Reducer<AppState, AppAction, AppEnvironment> { state, action, environment in
  struct MotionClientId: Hashable {}

  switch action {
  case .alertDismissed:
    state.alertTitle = nil
    return .none

  case .motionUpdate(.failure):
    state.alertTitle = """
      We encountered a problem with the motion manager. Make sure you run this demo on a real \
      device, not the simulator.
      """
    state.isRecording = false
    return .none

  case let .motionUpdate(.success(motion)):
    state.initialAttitude = state.initialAttitude
      ?? environment.motionManager.deviceMotion()?.attitude

    if let initialAttitude = state.initialAttitude {
      let newAttitude = motion.attitude.multiply(byInverseOf: initialAttitude)
      if abs(newAttitude.yaw) < Double.pi / 2 {
        state.facingDirection = .forward
      } else {
        state.facingDirection = .backward
      }
    }

    state.z.append(
      motion.gravity.x * motion.userAcceleration.x
        + motion.gravity.y * motion.userAcceleration.y
        + motion.gravity.z * motion.userAcceleration.z
    )
    state.z.removeFirst(max(0, state.z.count - 350))

    return .none

  case .recordingButtonTapped:
    state.isRecording.toggle()
    if state.isRecording {
      return environment.motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main)
        .catchToEffect()
        .map(AppAction.motionUpdate)
    } else {
      state.initialAttitude = nil
      state.facingDirection = nil
      return environment.motionManager.stopDeviceMotionUpdates()
        .fireAndForget()
    }
  }
}
.debug()

struct AppView: View {
  let store: Store<AppState, AppAction>

  var body: some View {
    WithViewStore(self.store) { viewStore in
      VStack {
        Text(readMe)
          .multilineTextAlignment(.leading)
          .layoutPriority(1)

        Spacer(minLength: 100)

        plot(buffer: viewStore.z, scale: 40)

        Button(action: { viewStore.send(.recordingButtonTapped) }) {
          HStack {
            Image(
              systemName: viewStore.isRecording
                ? "stop.circle.fill" : "arrowtriangle.right.circle.fill"
            )
            .font(.title)
            Text(viewStore.isRecording ? "Stop Recording" : "Start Recording")
          }
          .foregroundColor(.white)
          .padding()
          .background(viewStore.isRecording ? Color.red : .blue)
          .cornerRadius(16)
        }
      }
      .padding()
      .background(viewStore.facingDirection == .backward ? Color.green : Color.clear)
      .alert(
        item: viewStore.binding(
          get: { $0.alertTitle.map(AppAlert.init(title:)) },
          send: .alertDismissed
        )
      ) { alert in
        Alert(title: Text(alert.title))
      }
    }
  }
}

struct AppAlert: Identifiable {
  var title: String
  var id: String { self.title }
}

func plot(buffer: [Double], scale: Double) -> Path {
  Path { path in
    let baseline: Double = 50
    let size: Double = 3
    for (offset, value) in buffer.enumerated() {
      let point = CGPoint(x: Double(offset) - size / 2, y: baseline - value * scale - size / 2)
      let rect = CGRect(origin: point, size: CGSize(width: size, height: size))
      path.addEllipse(in: rect)
    }
  }
}

struct AppView_Previews: PreviewProvider {
  static var previews: some View {
    // Since MotionManager isn't usable in SwiftUI previews or simulators we create one that just
    // sends a bunch of data on some sine curves.
    var isStarted = false
    let mockMotionManager = MotionManager.mock(
      startDeviceMotionUpdates: { _, _ in
        isStarted = true
        return Timer.publish(every: 0.01, on: .main, in: .default)
          .autoconnect()
          .filter { _ in isStarted }
          .map { $0.timeIntervalSince1970 * 2 }
          .map { t in
            DeviceMotion(
              attitude: .init(quaternion: .init(x: 1, y: 0, z: 0, w: 0)),
              gravity: .init(x: sin(2 * t), y: -cos(-t), z: sin(3 * t)),
              heading: 0,
              magneticField: .init(field: .init(x: 0, y: 0, z: 0), accuracy: .high),
              rotationRate: CMRotationRate.init(x: 0, y: 0, z: 0),
              timestamp: Date().timeIntervalSince1970,
              userAcceleration: .init(x: -cos(-3 * t), y: sin(2 * t), z: -cos(t))
            )
        }
        .setFailureType(to: MotionManager.Error.self)
        .eraseToEffect()
    },
      stopDeviceMotionUpdates: {
        .fireAndForget { isStarted = false }
    })

    return AppView(
      store: Store(
        initialState: AppState(
          z: (1...350).map {
            2 * sin(Double($0) / 20) + cos(Double($0) / 8)
          }
        ),
        reducer: appReducer,
        environment: .init(motionManager: mockMotionManager)
      )
    )
  }
}
