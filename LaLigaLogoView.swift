import SwiftUI

/// Logo oficial de La Liga.
struct LaLigaLogoView: View {
    var size: CGFloat = 40

    var body: some View {
        Image("LaLigaLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 24) {
        LaLigaLogoView(size: 40)
        LaLigaLogoView(size: 72)
        LaLigaLogoView(size: 100)
    }
    .padding(24)
    .background(Color(hex: 0x0A0A14))
}
