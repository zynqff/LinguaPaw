import SwiftUI
import AVFoundation

/// Показывает сделанное/выбранное фото с переводом, наложенным поверх
/// исходного текста — на том же месте, где он был на снимке.
struct PhotoResultView: View {
    let image: UIImage
    @EnvironmentObject var vm: TranslatorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isProcessing = true
    @State private var errorMessage: String?
    @State private var blocks: [TranslatedBlock] = []

    private struct TranslatedBlock: Identifiable {
        let id = UUID()
        /// Нормализованный прямоугольник Vision (0...1, начало — левый нижний угол).
        let visionRect: CGRect
        let text: String
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let displayRect = AVMakeRect(
                    aspectRatio: image.size,
                    insideRect: CGRect(origin: .zero, size: geo.size)
                )

                ZStack {
                    Color.black.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)

                    ForEach(blocks) { block in
                        let rect = displayFrame(for: block.visionRect, in: displayRect)
                        Text(block.text)
                            .font(.system(size: max(11, rect.height * 0.62), weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 4)
                            .frame(width: rect.width, height: rect.height)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(4)
                            .position(x: rect.midX, y: rect.midY)
                    }

                    if isProcessing {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Распознаём и переводим…").font(.footnote)
                        }
                        .padding(20)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .navigationTitle("Фото")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = blocks.map(\.text).joined(separator: "\n")
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(blocks.isEmpty)
                }
            }
        }
        .task { await process() }
        .alert("Не удалось перевести фото", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Готово") { dismiss() }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Переводит Vision-прямоугольник (нормализованный, левый нижний угол)
    /// в прямоугольник на экране (верхний левый угол), с учётом того, что
    /// изображение показано в режиме .scaledToFit и может иметь чёрные поля.
    private func displayFrame(for visionRect: CGRect, in displayRect: CGRect) -> CGRect {
        let x = displayRect.minX + visionRect.minX * displayRect.width
        let width = visionRect.width * displayRect.width
        let height = visionRect.height * displayRect.height
        let y = displayRect.minY + (1 - visionRect.minY - visionRect.height) * displayRect.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func process() async {
        do {
            let recognized = try await TextRecognitionService.recognizeText(in: image)
            var translated: [TranslatedBlock] = []
            for item in recognized {
                let text = try await vm.translateStandalone(item.text, from: vm.sourceLanguage, to: vm.targetLanguage)
                translated.append(TranslatedBlock(visionRect: item.boundingBox, text: text))
            }
            blocks = translated
        } catch {
            errorMessage = error.localizedDescription
        }
        isProcessing = false
    }
}
