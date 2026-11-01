import Testing
@testable import GRFCore

struct ActionPreviewSelectionTests {
    @Test func startsOnDrawableActionInsteadOfBlankEquipmentPose() {
        let empty = SpriteAction(frames: [ActionFrame(layers: [], anchors: [], soundIndex: -1)], frameDuration: 0.1)
        let layer = ActionLayer(offsetX: 0, offsetY: 0, spriteIndex: 0, isTruecolor: false, mirror: false,
                                scaleX: 1, scaleY: 1, rotation: 0, color: [255, 255, 255, 255], width: 1, height: 1)
        let visible = SpriteAction(frames: [ActionFrame(layers: [layer], anchors: [], soundIndex: -1)], frameDuration: 0.1)
        let document = ActionDocument(version: 0x205, actions: [empty, empty, visible], sounds: [])
        #expect(document.firstDrawableActionIndex == 2)
        #expect(ActionDocument(version: 0x205, actions: [empty], sounds: []).firstDrawableActionIndex == nil)
    }
}
