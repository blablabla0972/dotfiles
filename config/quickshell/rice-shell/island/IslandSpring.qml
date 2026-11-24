pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: spring

    required property vector3d target
    property bool contracting: false
    property bool mediaBounce: false
    property real openingFrequency: 24
    property real epsilon: 0.15
    readonly property bool running: driver.running
    property vector3d position
    property vector3d velocity
    property bool initialized: false
    property real travelWeight: 0
    readonly property real frequency: Math.max(1, (contracting ? 29 : openingFrequency) - 6 * travelWeight)
    readonly property real decay: frequency * (mediaBounce ? (contracting ? 0.72 : 0.62)
        : (contracting ? 0.96 : 0.74 + 0.13 * travelWeight))
    readonly property real oscillation: Math.sqrt(frequency * frequency - decay * decay)

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

    function advance(seconds: real): void {
        if (seconds <= 0) return;
        // Exact damped spring step. A new target keeps the rendered position and velocity.
        const attenuation = Math.exp(-decay * seconds);
        const cosine = attenuation * Math.cos(oscillation * seconds);
        const sine = attenuation * Math.sin(oscillation * seconds) / oscillation;
        const offset = position.minus(target);
        const nextOffset = offset.times(cosine + decay * sine).plus(velocity.times(sine));
        const nextVelocity = velocity.times(cosine - decay * sine)
            .minus(offset.times(frequency * frequency * sine));
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
