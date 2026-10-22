import Foundation
import CoreGraphics

@main struct DotMapChecks {
    static var count = 0
    static func check(_ condition: Bool, _ description: String) {
        precondition(condition, description)
        count += 1
    }
    static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.000001 }
    static func main() {
        for scale: CGFloat in [0.12, 0.25, 0.62, 1, 2.2] {
            var camera = DotMapViewport(scale: scale, limits: 0.12...2.2)
            camera.pan(to: CGSize(width: 30, height: -20))
            camera.pan(to: CGSize(width: 120, height: -80))
            check(camera.offset == CGSize(width: 120, height: -80), "Drag must follow full finger distance at every zoom")
            camera.endPan()
            check(camera.offset == CGSize(width: 120, height: -80), "Release must not pull back or coast")
            camera.pan(to: CGSize(width: -15, height: 9))
            check(camera.offset == CGSize(width: 105, height: -71), "A new drag must start at the released position")
            camera.cancelGestures()
            camera.pan(to: CGSize(width: 5, height: 5))
            check(camera.offset == CGSize(width: 110, height: -66), "Cancelled gestures must not retain cumulative translation")
            let anchor = CGPoint(x: 87, y: -126)
            let world = CGPoint(x: (anchor.x-camera.offset.width)/camera.scale, y: (anchor.y-camera.offset.height)/camera.scale)
            for magnification: CGFloat in [0.001, 0.8, 1.7, 100] {
                camera.pinch(to: magnification, anchor: anchor)
                check(near(world.x*camera.scale+camera.offset.width, anchor.x) && near(world.y*camera.scale+camera.offset.height, anchor.y), "Pinch must preserve its focal point even at zoom limits")
            }
            camera.endPinch()
            let released = camera.offset
            camera.pan(to: CGSize(width: 200, height: 100))
            check(camera.offset == released, "An interrupted drag must not replay after pinch")
            camera.pan(to: CGSize(width: 207, height: 109))
            check(camera.offset == CGSize(width: released.width+7, height: released.height+9), "Remaining finger must resume without jumping after pinch")
            camera.endPan()
            camera.pan(to: CGSize(width: 10, height: 15))
            check(camera.offset == CGSize(width: released.width+17, height: released.height+24), "Fresh drag must work after pinch")
            check(camera.gridSpacing >= 18, "Zoomed-out grid must stay bounded in density")
        }
        var camera = DotMapViewport(offset: CGSize(width: 180, height: -70), scale: 0.62, limits: 0.12...2.2)
        let before = camera.offset
        camera.zoom(to: camera.scale*1.35)
        camera.zoom(to: camera.scale/1.35)
        check(near(camera.offset.width, before.width) && near(camera.offset.height, before.height), "Zoom controls must preserve the world point at viewport center")
        camera.pinch(to: 2, anchor: .zero)
        camera.reset(offset: CGSize(width: 0, height: 40), scale: 0.62)
        camera.pan(to: CGSize(width: 12, height: 8))
        check(camera.offset == CGSize(width: 12, height: 48), "Recenter must clear gesture history")
        camera.zoom(to: .infinity)
        check(camera.scale == 0.62, "Invalid input must not corrupt the camera")
        camera.cancelGestures()
        camera.pinch(to: 1.5, anchor: CGPoint(x: -40, y: 50))
        camera.endPinch()
        let pinchOnly = camera.offset
        camera.pan(to: CGSize(width: 10, height: 12))
        check(camera.offset == CGSize(width: pinchOnly.width+10, height: pinchOnly.height+12), "Pinch without a drag must not block the next drag")
        camera.suspendPan()
        let held = camera.offset
        camera.pan(to: CGSize(width: 90, height: 80))
        check(camera.offset == held, "Moving an individual dot must not move the map")
        camera.endPan()
        camera.pan(to: CGSize(width: -5, height: -8))
        check(camera.offset == CGSize(width: held.width-5, height: held.height-8), "Map must resume after dropping an individual dot")
        print("Passed \(count) map movement checks")
    }
}
