import SwiftUI
import UIKit

/// Démonstration en grand : l'animation d'abord, puis on glisse vers les photos départ/arrivée et la photo de la machine.
struct ExerciseDemoViewer: View {
    let exercise: ExerciseInfo
    let machinePhoto: UIImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page?
    @State private var animation: UIImage?
    @State private var photos: [UIImage] = []
    @State private var sideBySide = false

    enum Page: Hashable { case animation, photos, machine }

    private var pages: [Page] {
        var pages: [Page] = []
        if exercise.hasAnimation { pages.append(.animation) }
        if exercise.photoCount > 0 { pages.append(.photos) }
        if machinePhoto != nil { pages.append(.machine) }
        return pages
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                ForEach(pages, id: \.self) { page in
                    pageView(page).tag(Optional(page))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .background(.black)
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer", systemImage: "xmark") { dismiss() }
                }
                if (page ?? pages.first) == .photos, photos.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(sideBySide ? "Animer" : "Côte à côte", systemImage: sideBySide ? "play" : "rectangle.split.1x2") {
                            withAnimation(.snappy) { sideBySide.toggle() }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationBackground(.black)
        .task {
            page = pages.first
            animation = ExerciseMedia.cachedAnimation(for: exercise.id)
            photos = ExerciseMedia.cachedPhotos(for: exercise.id, count: exercise.photoCount)
            if exercise.hasAnimation, animation == nil { animation = await ExerciseMedia.animation(for: exercise.id) }
            if photos.count < exercise.photoCount { photos = await ExerciseMedia.photos(for: exercise.id, count: exercise.photoCount) }
        }
    }

    @ViewBuilder private func pageView(_ page: Page) -> some View {
        switch page {
        case .animation:
            if let animation {
                ZoomableMedia {
                    Group {
                        if reduceMotion {
                            Image(uiImage: animation.images?.first ?? animation).resizable().interpolation(.high)
                        } else {
                            AnimatedImage(image: animation)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .background(Color.white, in: .rect(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 16)
                }
                .accessibilityLabel("Animation du mouvement")
            } else {
                loading
            }
        case .photos:
            if photos.isEmpty {
                loading
            } else if sideBySide || reduceMotion {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(index == 0 ? "Départ" : "Arrivée")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
                .accessibilityLabel("Photos de départ et d'arrivée")
            } else {
                ZoomableMedia {
                    DemoPhotos(images: photos, fit: true)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                }
                .accessibilityLabel("Photos du mouvement, de la position de départ à l'arrivée")
            }
        case .machine:
            if let machinePhoto {
                ZoomableMedia {
                    Image(uiImage: machinePhoto)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 16)
                }
                .accessibilityLabel("Photo de la machine")
            }
        }
    }

    private var loading: some View {
        ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Pincer pour zoomer, double-toucher pour revenir à la taille d'origine.
private struct ZoomableMedia<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = min(4, max(1, lastScale * $0.magnification)) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale == 1 { reset() }
                    }
            )
            // Le déplacement n'est actif qu'une fois zoomé, pour laisser le balayage entre les pages.
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset },
                isEnabled: scale > 1
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    if scale > 1 { reset() } else {
                        scale = 2
                        lastScale = 2
                    }
                }
            }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

/// Photos départ → arrivée en fondu enchaîné, en boucle (immobile si « Réduire les animations »).
struct DemoPhotos: View {
    let images: [UIImage]
    var fit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    var body: some View {
        ZStack {
            ForEach(Array(images.enumerated()), id: \.offset) { offset, image in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
                    .opacity(offset == index ? 1 : 0)
            }
        }
        .task(id: images.count) {
            guard images.count > 1, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.3))
                withAnimation(.easeInOut(duration: 0.45)) { index = (index + 1) % images.count }
            }
        }
    }
}

/// GIF animé (SwiftUI n'anime pas les GIF nativement).
struct AnimatedImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image { view.image = image }
    }
}
