import LivingPortraitCore
import LivingPortraitSwiftUI
import SwiftUI

struct BasicLivingPortrait: View {
    let scene: LivingPortraitScene

    var body: some View {
        LivingPortraitStage(scene: scene) { layer, _ in
            Image(layer.asset)
                .resizable()
                .scaledToFit()
        }
        .aspectRatio(scene.canvas.aspectWidth / scene.canvas.aspectHeight, contentMode: .fit)
        .accessibilityLabel("A subtly animated layered portrait")
    }
}
