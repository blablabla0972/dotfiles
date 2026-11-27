pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: spring

    required property vector3d target
    property bool contracting: false
    property bool mediaBounce: false
    property real openingFrequency: 27
    property real epsilon: 0.15
    readonly property bool running: driver.running
    property vector3d position
    property vector3d velocity
    property bool initialized: false
    property real travelWeight: 0
    readonly property real frequency: Math.max(1, contracting ? 31 - 13 * travelWeight : openingFrequency - 5 * travelWeight)
    readonly property real heightFrequency: frequency * (contracting ? 1.18 : 0.80)
    readonly property real dampingRatio: mediaBounce ? (contracting ? 0.71 : 0.64)
        : (contracting ? 0.96 : 0.77 + 0.11 * travelWeight)

    Component.onCompleted: {
        position = target;
        initialized = true;
    }
    onTargetChanged: {
        if (!initialized) return;
        // Measure once per destination so the spring keeps its rhythm through reversals.
        travelWeight = Math.min(1, target.minus(position).length() / 640);
        driver.start();
    }

    readonly property FrameAnimation driver: FrameAnimation {
        onTriggered: spring.advance(frameTime)
    }

    // Exact spring step for one axis. Return displacement from target and velocity.
    function stepAxis(offset: real, speed: real, rate: real, seconds: real): point {
        const decay = rate * dampingRatio;
        const oscillation = rate * Math.sqrt(1 - dampingRatio * dampingRatio);
        const attenuation = Math.exp(-decay * seconds);
        const cosine = attenuation * Math.cos(oscillation * seconds);
        const sine = attenuation * Math.sin(oscillation * seconds) / oscillation;
        return Qt.point(offset * (cosine + decay * sine) + speed * sine,
                        speed * (cosine - decay * sine) - offset * rate * rate * sine);
    }

    function advance(seconds: real): void {
        if (seconds <= 0) return;
        const offset = position.minus(target);
        const x = stepAxis(offset.x, velocity.x, frequency, seconds);
        const y = stepAxis(offset.y, velocity.y, heightFrequency, seconds);
        const radius = stepAxis(offset.z, velocity.z, heightFrequency, seconds);
        const nextOffset = Qt.vector3d(x.x, y.x, radius.x);
        const nextVelocity = Qt.vector3d(x.y, y.y, radius.y);
        if (nextOffset.length() <= epsilon && nextVelocity.length() <= frequency * epsilon) {
            position = target;
            velocity = Qt.vector3d(0, 0, 0);
            driver.stop();
        } else {
            position = target.plus(nextOffset);
            velocity = nextVelocity;
        }
    }
}
