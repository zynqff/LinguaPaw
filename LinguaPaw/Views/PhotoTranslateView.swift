import SwiftUI
import PhotosUI

private enum PhotoScreenMode {
    case translate, camera, history
}

/// Вкладка «Фото»: три режима, переключаемых нижней капсулой — «Перевод»
/// (текстовый ввод, компактно), «Камера» (живой превью + съёмка), «История»
/// (тот же архив переводов, что и на одноимённой вкладке таб-бара).
struct PhotoTranslateView: View {
    @EnvironmentObject var vm: TranslatorViewModel
    @StateObject private var camera = CameraService()
    @State private var mode: PhotoScreenMode = .camera
    @State private var resultImage: UIImage?
    @State private var galleryItem: PhotosPickerItem?
    @State private var showGalleryPicker = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch mode {
                case .camera: cameraContent
                case .translate: CompactTranslateView()
                case .history: HistoryView()
                }
            }

            modeSwitcher
        }
        .background(Color(.systemBackground))
        .onAppear { if mode == .camera { camera.requestAccessAndConfigure() } }
        .onChange(of: mode) { newMode in
            if newMode == .camera { camera.requestAccessAndConfigure() } else { camera.stop() }
        }
        .onDisappear { camera.stop() }
        .photosPicker(isPresented: $showGalleryPicker, selection: $galleryItem, matching: .images)
        .onChange(of: galleryItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    resultImage = image
                }
                galleryItem = nil
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { resultImage != nil },
            set: { if !$0 { resultImage = nil } }
        )) {
            if let resultImage {
                PhotoResultView(image: resultImage).environmentObject(vm)
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("ОК") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Камера

    private var cameraContent: some View {
        ZStack {
            if camera.permissionDenied {
                permissionDeniedView
            } else {
                CameraPreviewLayerView(session: camera.session)
                    .ignoresSafeArea()
            }

            VStack {
                Spacer()
                languagePairPill
                captureControls
                    .padding(.top, 20)
                    .padding(.bottom, 110)
            }
        }
    }

    private var languagePairPill: some View {
        HStack(spacing: 10) {
            languageMenu(selection: $vm.sourceLanguage)
            Image(systemName: "arrow.right").foregroundStyle(.white.opacity(0.8))
            languageMenu(selection: $vm.targetLanguage)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private func languageMenu(selection: Binding<String>) -> some View {
        Menu {
            ForEach(supportedLanguages, id: \.self) { lang in
                Button(languageAutonym(lang)) { selection.wrappedValue = lang }
            }
        } label: {
            HStack(spacing: 4) {
                Text(languageAutonym(selection.wrappedValue)).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .foregroundStyle(.white)
        }
    }

    private var captureControls: some View {
        HStack {
            Button { showGalleryPicker = true } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            Button { capturePhoto() } label: {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 74, height: 74)
            }

            Spacer()

            Button { camera.toggleTorch() } label: {
                Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt.slash")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 32)
    }

    private func capturePhoto() {
        Task {
            do {
                resultImage = try await camera.capturePhoto()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Нет доступа к камере").font(.headline)
            Text("Разрешите доступ к камере в Настройках устройства, чтобы переводить текст с фото.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Открыть настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(BrandGradientButtonStyle())
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Переключатель режимов (нижняя капсула)

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            modeButton(.translate, icon: "captions.bubble", title: "Перевод")
            modeButton(.camera, icon: "camera.fill", title: "Камера")
            modeButton(.history, icon: "clock.arrow.circlepath", title: "История")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private func modeButton(_ target: PhotoScreenMode, icon: String, title: String) -> some View {
        Button { mode = target } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(mode == target ? LinguaPawTheme.brandStart : Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
