import SwiftUI

/// ВРЕМЕННАЯ ЗАГЛУШКА. Полноценный экран (камера/галерея, OCR, подстановка
/// перевода поверх фото на место исходного текста, голосовой ввод и озвучка)
/// будет реализован по присланному макету экрана камеры.
struct PhotoTranslateView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Перевод по фото")
                    .font(.title2.bold())
                Text("Этот экран в разработке.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Фото")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
