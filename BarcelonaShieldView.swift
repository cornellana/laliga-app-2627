import SwiftUI

/// Escudo oficial del FC Barcelona.
struct BarcelonaShieldView: View {
    var size: CGFloat = 28

    var body: some View {
        Image("BarcelonaShield")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        BarcelonaShieldView(size: 24)
        BarcelonaShieldView(size: 40)
        BarcelonaShieldView(size: 64)
        BarcelonaShieldView(size: 120)
    }
    .padding()
    .background(Color(hex: 0x0A0A14))
}
