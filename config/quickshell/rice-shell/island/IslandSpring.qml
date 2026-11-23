pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: spring

    required property vector3d target
    property bool contracting: false
    property real openingFrequency: 20
    property real epsilon: 0.15
    readonly property bool running: driver.running
    property vector3d position
    property vector3d velocity
    property bool initialized: false

    Component.onCompleted: {
        position = target;
        initialized = true;
    }
    onTargetChanged: if (initialized) driver.start()

    readonly property FrameAnimation driver: FrameAnimation {
        onTriggered: spring.advance(Math.min(0.05, frameTime))
    }

    function advance(seconds: real): void {
        if (seconds <= 0) return;
        // Exact damped spring step. A new target keeps the rendered position and velocity.
        const frequency = contracting ? 20 : openingFrequency;
        const decay = frequency * (contracting ? 0.89 : 0.80);
        const oscillation = Math.sqrt(frequency * frequency - decay * decay);
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
