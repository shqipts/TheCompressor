import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import UIKit

enum CompressionLevel: String, CaseIterable, Identifiable {
    case light = "Light"
    case medium = "Medium"
    case strong = "Strong"
    case custom = "Custom"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .light: return "Best quality, smaller savings"
        case .medium: return "Balanced quality and size"
        case .strong: return "Max reduction for sharing"
        case .custom: return "Tune quality and resolution manually"
        }
    }
}

struct LocalPDF: Identifiable {
    let id = UUID()
    let originalName: String
    let localURL: URL
    let size: Int64
}

struct CompressionResult: Identifiable {
    let id = UUID()
    let name: String
    let before: Int64
    let after: Int64

    var saved: Int64 { max(0, before - after) }
    var reductionPercent: Int {
        guard before > 0 else { return 0 }
        return Int((Double(saved) / Double(before) * 100.0).rounded())
    }
}

struct ContentView: View {
    @State private var selectedLevel: CompressionLevel = .medium
    @State private var customJPEGQuality: CGFloat = 0.58
    @State private var customScale: CGFloat = 0.84

    @State private var files: [LocalPDF] = []
    @State private var results: [CompressionResult] = []

    @State private var showImporter = false
    @State private var isProcessing = false
    @State private var statusText = "Pick PDF files to start"

    @State private var shareItems: [Any] = []
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.05, green: 0.08, blue: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        profileCard
                        queueCard
                        actionsCard
                        if !results.isEmpty { resultsCard }
                    }
                    .padding()
                }
            }
            .navigationTitle("TheCompressor")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            importFiles(result)
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: shareItems)
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compression Profile")
                .font(.headline)
                .foregroundStyle(.white)

            Picker("Compression", selection: $selectedLevel) {
                ForEach(CompressionLevel.allCases) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text(selectedLevel.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))

            if selectedLevel == .custom {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Image quality")
                        Spacer()
                        Text("\(Int(customJPEGQuality * 100))%")
                            .foregroundStyle(.cyan)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))

                    Slider(value: $customJPEGQuality, in: 0.20...0.95, step: 0.01)
                        .tint(.cyan)

                    HStack {
                        Text("Resolution scale")
                        Spacer()
                        Text("\(Int(customScale * 100))%")
                            .foregroundStyle(.purple)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))

                    Slider(value: $customScale, in: 0.40...1.0, step: 0.01)
                        .tint(.purple)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(glassBG)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var queueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Queue")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if !files.isEmpty {
                    Text("\(files.count) file\(files.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if files.isEmpty {
                Text("No files selected")
                    .foregroundStyle(.white.opacity(0.65))
                    .font(.subheadline)
            } else {
                ForEach(files.prefix(5)) { file in
                    HStack {
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(.cyan)
                        Text(file.originalName)
                            .lineLimit(1)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                if files.count > 5 {
                    Text("+\(files.count - 5) more")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 4)
        }
        .padding(14)
        .background(glassBG)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var actionsCard: some View {
        VStack(spacing: 12) {
            Button {
                showImporter = true
            } label: {
                Text("Browse PDFs")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(NeonButtonStyle(color: .blue))

            if !files.isEmpty {
                if files.count == 1 {
                    Button {
                        Task { await compressAll() }
                    } label: {
                        Text(isProcessing ? "Compressing..." : "Compress")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(NeonButtonStyle(color: .cyan))
                    .disabled(isProcessing)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            Task { await compressAll() }
                        } label: {
                            Text(isProcessing ? "Compressing..." : "Compress All")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(NeonButtonStyle(color: .cyan))
                        .disabled(isProcessing)

                        Button {
                            Task { await mergeAllInOne() }
                        } label: {
                            Text(isProcessing ? "Merging..." : "Merge One PDF")
                                .font(.headline)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(NeonButtonStyle(color: .purple))
                        .disabled(isProcessing)
                    }
                }
            }
        }
        .padding(14)
        .background(glassBG)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var resultsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Results")
                .font(.headline)
                .foregroundStyle(.white)

            let totalSaved = results.reduce(Int64(0)) { $0 + $1.saved }
            Text("Saved \(ByteCountFormatter.string(fromByteCount: totalSaved, countStyle: .file)) total")
                .font(.subheadline)
                .foregroundStyle(.green)

            ForEach(results.prefix(6)) { item in
                HStack {
                    Text(item.name)
                        .lineLimit(1)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("-\(item.reductionPercent)%")
                        .foregroundStyle(.green)
                        .font(.subheadline.bold())
                }
            }
        }
        .padding(14)
        .background(glassBG)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var glassBG: some ShapeStyle { .ultraThinMaterial }

    private var currentCompressionSettings: (jpegQuality: CGFloat, scale: CGFloat) {
        switch selectedLevel {
        case .light:
            return (0.82, 1.0)
        case .medium:
            return (0.58, 0.84)
        case .strong:
            return (0.36, 0.62)
        case .custom:
            return (customJPEGQuality, customScale)
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            let picked = try result.get()
            var imported: [LocalPDF] = []

            for url in picked {
                let copy = try secureLocalCopy(from: url)
                let size = fileSize(at: copy)
                imported.append(LocalPDF(originalName: url.lastPathComponent, localURL: copy, size: size))
            }

            files = imported
            results = []
            statusText = "Ready: \(files.count) file(s) loaded"
        } catch {
            statusText = "Import failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func compressAll() async {
        guard !files.isEmpty else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            var outputs: [URL] = []
            var localResults: [CompressionResult] = []

            for file in files {
                let out = try PDFEngine.compress(
                    inputURL: file.localURL,
                    jpegQuality: currentCompressionSettings.jpegQuality,
                    scale: currentCompressionSettings.scale
                )
                let named = try renameForExport(tempURL: out, baseName: file.originalName.replacingOccurrences(of: ".pdf", with: ""), suffix: "-compressed")
                let outSize = fileSize(at: named)
                localResults.append(CompressionResult(name: file.originalName, before: file.size, after: outSize))
                outputs.append(named)
            }

            results = localResults
            shareItems = outputs
            showShare = true
            statusText = "Done. \(outputs.count) file(s) compressed."
        } catch {
            statusText = "Compression failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func mergeAllInOne() async {
        guard files.count > 1 else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            let merged = PDFDocument()
            var pageIndex = 0
            var totalBefore: Int64 = 0

            for file in files {
                totalBefore += file.size
                let out = try PDFEngine.compress(
                    inputURL: file.localURL,
                    jpegQuality: currentCompressionSettings.jpegQuality,
                    scale: currentCompressionSettings.scale
                )
                guard let doc = PDFDocument(url: out) else { continue }
                for i in 0..<doc.pageCount {
                    if let page = doc.page(at: i) {
                        merged.insert(page, at: pageIndex)
                        pageIndex += 1
                    }
                }
            }

            let finalURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Merged_Compressed.pdf")
            _ = merged.write(to: finalURL)
            let finalSize = fileSize(at: finalURL)

            results = [CompressionResult(name: "Merged_Compressed.pdf", before: totalBefore, after: finalSize)]
            shareItems = [finalURL]
            showShare = true
            statusText = "Done. Merged into one PDF."
        } catch {
            statusText = "Merge failed: \(error.localizedDescription)"
        }
    }

    private func secureLocalCopy(from url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)

        let data = try Data(contentsOf: url)
        try data.write(to: target, options: .atomic)
        return target
    }

    private func renameForExport(tempURL: URL, baseName: String, suffix: String) throws -> URL {
        let cleanBase = baseName.replacingOccurrences(of: ".pdf", with: "")
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(cleanBase)\(suffix)")
            .appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: tempURL, to: target)
        return target
    }

    private func fileSize(at url: URL) -> Int64 {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)) ?? 0
    }
}

enum PDFEngine {
    static func compress(inputURL: URL, jpegQuality: CGFloat, scale: CGFloat) throws -> URL {
        guard let pdfData = try? Data(contentsOf: inputURL),
              let provider = CGDataProvider(data: pdfData as CFData),
              let cgPDF = CGPDFDocument(provider) else {
            throw NSError(domain: "TheCompressor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not open PDF"])
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 10, height: 10), format: .init())

        let data = renderer.pdfData { ctx in
            for index in 1...cgPDF.numberOfPages {
                guard let cgPage = cgPDF.page(at: index) else { continue }
                var pageRect = cgPage.getBoxRect(.mediaBox)
                if pageRect.isEmpty {
                    pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
                }

                ctx.beginPage(withBounds: pageRect, pageInfo: [:])

                let renderSize = CGSize(
                    width: max(1, pageRect.width * scale),
                    height: max(1, pageRect.height * scale)
                )

                let imageRenderer = UIGraphicsImageRenderer(size: renderSize)
                let renderedImage = imageRenderer.image { imageCtx in
                    let g = imageCtx.cgContext
                    g.setFillColor(UIColor.white.cgColor)
                    g.fill(CGRect(origin: .zero, size: renderSize))

                    g.saveGState()
                    g.translateBy(x: 0, y: renderSize.height)
                    g.scaleBy(x: renderSize.width / pageRect.width, y: -(renderSize.height / pageRect.height))
                    g.drawPDFPage(cgPage)
                    g.restoreGState()
                }

                if let jpgData = renderedImage.jpegData(compressionQuality: jpegQuality),
                   let jpgImage = UIImage(data: jpgData),
                   let cgImage = jpgImage.cgImage {
                    let g = ctx.cgContext
                    g.saveGState()
                    g.translateBy(x: 0, y: pageRect.height)
                    g.scaleBy(x: 1, y: -1)
                    g.draw(cgImage, in: CGRect(origin: .zero, size: pageRect.size))
                    g.restoreGState()
                } else {
                    let g = ctx.cgContext
                    g.saveGState()
                    g.translateBy(x: 0, y: pageRect.height)
                    g.scaleBy(x: 1, y: -1)
                    g.drawPDFPage(cgPage)
                    g.restoreGState()
                }
            }
        }

        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct NeonButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.60 : 0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: color.opacity(0.55), radius: 14, x: 0, y: 8)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
