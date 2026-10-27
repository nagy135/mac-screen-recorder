/// Hover and permission prompts both pause the countdown and reset it to three.
public struct CountdownState: Sendable {
    public private(set) var remainingSeconds = 3
    public private(set) var isHovering = false
    public private(set) var isWaitingForPermission = false

    public init() {}

    public var isPaused: Bool { isHovering || isWaitingForPermission }
    public var isComplete: Bool { remainingSeconds == 0 }

    public mutating func setHovering(_ hovering: Bool) {
        guard !isComplete, hovering != isHovering else { return }
        isHovering = hovering
        remainingSeconds = 3
    }

    public mutating func setWaitingForPermission(_ waiting: Bool) {
        guard !isComplete, waiting != isWaitingForPermission else { return }
        isWaitingForPermission = waiting
        remainingSeconds = 3
    }

    public mutating func tick() {
        guard !isPaused, !isComplete else { return }
        remainingSeconds -= 1
    }
}
