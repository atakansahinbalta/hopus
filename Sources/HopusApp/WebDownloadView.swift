import AppKit
import SwiftUI
import HopusCore

@MainActor final class WebDownloadModel:ObservableObject {
    @Published var linkText=""
    @Published var info:WebMediaInfo?
    @Published var batch:[WebMediaInfo]=[]
    @Published var inspectingLabel="Finding the media…"
    @Published var mode:WebDownloadMode = .video
    @Published var maximumHeight=0
    @Published var inspecting=false
    @Published var downloading=false
    @Published var error:String? { didSet { errorDetails=nil } }
    @Published var errorDetails:String?
    @Published var completed:[URL]=[]
    @Published var selectedPhotos=Set<Int>()
    @Published var shortcutAvailable=false
    @Published var destination:URL
    let state:AppState
    var onUseFiles:(()->Void)?
    private var inspection:Task<Void,Never>?
    private var inspectionToken=CancellationToken()
    private var revision=UUID()
    private var pendingMode:WebDownloadMode?
    init(state:AppState) {
        self.state=state
        destination=UserDefaults.standard.string(forKey:"webDownloadDestination").map{URL(fileURLWithPath:$0,isDirectory:true)} ?? FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask)[0]
    }
    func open(_ url:URL?,mode:WebDownloadMode) {
        guard !downloading,let url else { return }
        pendingMode=mode;linkText=url.absoluteString;inspect()
    }
    func editedLink() {
        guard !downloading else { return }
        inspection?.cancel();inspectionToken.cancel();revision=UUID();inspecting=false;info=nil;batch=[];error=nil;completed=[];pendingMode=nil
    }
    func pasteLink() {
        guard !downloading else { return }
        if let text=NSPasteboard.general.string(forType:.string),let urls=try? WebDownloadEngine.links(text),!urls.isEmpty {
            pendingMode=nil;linkText=urls.map(\.absoluteString).joined(separator:"\n");inspect();return
        }
        guard let url=WebLinkPayload.clipboardLink() else { error="Copy a video share link or an image address first.";return }
        pendingMode=nil;linkText=url.absoluteString;inspect()
    }
    func inspect() {
        guard !downloading else { return }
        inspection?.cancel();inspectionToken.cancel();inspectionToken=CancellationToken();revision=UUID()
        let current=revision,token=inspectionToken
        info=nil;batch=[];completed=[];error=nil;inspecting=false;inspectingLabel="Finding the media…"
        let urls:[URL]
        do { urls=try WebDownloadEngine.links(linkText) } catch { self.error=error.localizedDescription;return }
        inspecting=true
        inspection=Task { [weak self] in
            if urls.count==1 {
                do {
                    let found=try await WebDownloadEngine.inspect(urls[0],token:token)
                    guard let self,self.revision==current,!Task.isCancelled else { return }
                    self.info=found;self.maximumHeight=0;self.selectedPhotos=Set(found.photos.map(\.id))
                    if found.kind == .image { self.linkText=found.url.absoluteString }
                    self.mode=found.modes.contains(self.pendingMode ?? .video) ? (self.pendingMode ?? .video):(found.modes.first ?? .original)
                    self.pendingMode=nil;self.error=nil;self.inspecting=false
                } catch {
                    guard let self,self.revision==current,!token.isCancelled,!Task.isCancelled else { return }
                    self.error=error.localizedDescription;self.errorDetails=(error as? WebDownloadFailure)?.details;self.inspecting=false
                }
                return
            }
            var found:[WebMediaInfo]=[],problems:[String]=[]
            for (index,url) in urls.enumerated() {
                guard let self,self.revision==current,!Task.isCancelled,!token.isCancelled else { return }
                self.inspectingLabel="Checking link \(index+1) of \(urls.count)…"
                do { found.append(try await WebDownloadEngine.inspect(url,token:token)) }
                catch {
                    guard !token.isCancelled,!Task.isCancelled else { return }
                    problems.append("\(url.host ?? "Link"): \(error.localizedDescription)")
                }
            }
            guard let self,self.revision==current,!Task.isCancelled else { return }
            self.inspecting=false;self.maximumHeight=0;self.pendingMode=nil
            guard !found.isEmpty else {
                self.error=problems.count<=1 ? "This link could not be checked.":"\(problems.count) links could not be checked."
                self.errorDetails=problems.isEmpty ? nil:problems.joined(separator:"\n")
                return
            }
            self.batch=found
            self.mode=found.allSatisfy{$0.modes.contains(.video)} ? .video:(self.sharedModes(found).first ?? found[0].modes.first ?? .original)
            if !problems.isEmpty {
                self.error="\(problems.count) links could not be checked."
                self.errorDetails=problems.joined(separator:"\n")
            }
        }
    }
    func sharedModes(_ items:[WebMediaInfo])->[WebDownloadMode] {
        guard var common=items.first.map({Set($0.modes)}) else { return [] }
        for item in items.dropFirst() { common.formIntersection(item.modes) }
        return WebDownloadMode.allCases.filter{common.contains($0)}
    }
    func saveMode(for item:WebMediaInfo)->WebDownloadMode {
        if item.modes.contains(mode) { return mode }
        if item.modes.contains(.video) { return .video }
        return item.modes.first ?? .original
    }
    var batchTallest:Int { batch.compactMap { $0.heights.max() }.max() ?? 0 }
    var batchNeedsQuality:Bool {
        let downloadsVideo=batch.contains { item in saveMode(for:item) == .video }
        return downloadsVideo && batchTallest>720
    }
    func cancelInspection() { inspection?.cancel();inspectionToken.cancel();revision=UUID();inspecting=false }
    func configurationChanged() { guard !downloading else { return };completed=[];error=nil }
    func selectPhotos(_ ids:Set<Int>) { guard !downloading else { return };selectedPhotos=ids;configurationChanged() }
    func chooseDestination() {
        guard !downloading else { return }
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true;panel.directoryURL=destination;panel.prompt=L10n.text("Save Downloads Here")
        if panel.runModal() == .OK,let url=panel.url { do { try FolderAccessPreferences.add([url]);configurationChanged();destination=url;UserDefaults.standard.set(url.path,forKey:"webDownloadDestination") } catch { self.error=error.localizedDescription } }
    }
    func download() {
        if batch.count>1 { downloadBatch();return }
        guard let info,!downloading,!state.working,info.photos.isEmpty || !selectedPhotos.isEmpty else { return }
        let mode=mode,maximum=maximumHeight>0 ? maximumHeight:nil,folder=destination
        let selection=info.photos.isEmpty ? nil:selectedPhotos
        downloading=true;error=nil;completed=[]
        state.beginJob("Starting download…")
        let token=state.token
        Task { [state] in
            defer { downloading=false;state.finishJob() }
            do {
                let files=try await WebDownloadEngine.download(info,mode:mode,maximumHeight:maximum,destination:folder,selectedPhotos:selection,token:token) { [weak state] fraction,label in
                    Task { @MainActor in state?.receiveProgress(fraction,label:label,token:token) }
                }
                state.stopProgressUpdates();state.outputs=files;state.inputs=files;state.progress=1;completed=files
                state.recordWebDownload(files,site:info.url.host ?? "Web")
            } catch {
                state.stopProgressUpdates();self.error=token.isCancelled ? "Download cancelled. No partial files were kept.":error.localizedDescription
                if !token.isCancelled { self.errorDetails=(error as? WebDownloadFailure)?.details }
                if !token.isCancelled { state.error=error.localizedDescription }
            }
        }
    }
    func downloadBatch() {
        guard batch.count>1,!downloading,!state.working else { return }
        let items=batch,chosen=mode,maximum=maximumHeight>0 ? maximumHeight:nil,folder=destination
        downloading=true;error=nil;completed=[]
        state.beginJob("Starting download…")
        let token=state.token
        Task { [state] in
            defer { downloading=false;state.finishJob() }
            var saved:[URL]=[],failures:[String]=[],firstMessage:String?,firstDetails:String?
            for (index,item) in items.enumerated() {
                if token.isCancelled { break }
                let itemMode=Self.resolvedMode(item,chosen:chosen)
                let selection=item.photos.isEmpty ? nil:Set(item.photos.map(\.id))
                let height=itemMode == .video ? maximum:nil
                do {
                    let files=try await WebDownloadEngine.download(item,mode:itemMode,maximumHeight:height,destination:folder,selectedPhotos:selection,token:token) { [weak state] fraction,label in
                        let step=fraction.isFinite && fraction>=0 ? min(1,fraction):0
                        let overall=(Double(index)+step)/Double(items.count)
                        let prefix="Link \(index+1) of \(items.count)"
                        let text=label.isEmpty ? prefix:"\(prefix) · \(label)"
                        Task { @MainActor in state?.receiveProgress(overall,label:text,token:token) }
                    }
                    saved.append(contentsOf:files)
                    state.recordWebDownload(files,site:item.url.host ?? "Web")
                } catch {
                    if token.isCancelled { break }
                    if firstMessage==nil { firstMessage=error.localizedDescription;firstDetails=(error as? WebDownloadFailure)?.details }
                    failures.append("\(item.title): \(error.localizedDescription)")
                }
            }
            state.stopProgressUpdates();state.outputs=saved;state.inputs=saved;state.progress=1;completed=saved
            if token.isCancelled {
                self.error=saved.isEmpty ? "Download cancelled. No partial files were kept.":"Download cancelled. Saved files were kept."
            } else if saved.isEmpty {
                self.error=firstMessage ?? "The site could not provide this media. Try a fresh public share link or a direct media URL."
                self.errorDetails=failures.count>1 ? failures.joined(separator:"\n"):firstDetails
                if !failures.isEmpty { state.error=self.error }
            } else if !failures.isEmpty {
                self.error="Saved \(saved.count) files. \(failures.count) links could not be downloaded."
                self.errorDetails=failures.joined(separator:"\n")
            }
        }
    }
    private static func resolvedMode(_ item:WebMediaInfo,chosen:WebDownloadMode)->WebDownloadMode {
        if item.modes.contains(chosen) { return chosen }
        if item.modes.contains(.video) { return .video }
        return item.modes.first ?? .original
    }
}

struct WebDownloadView:View {
    @ObservedObject var model:WebDownloadModel
    @ObservedObject var state:AppState
    @Environment(\.locale) private var locale
    var body:some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:14) {
                WindowCloseButton().frame(width:24,height:24)
                ZStack {
                    WindowDragRegion()
                    HStack(spacing:12) {
                        Image(systemName:"arrow.down.circle.fill").font(.system(size:26)).foregroundStyle(Color.hopus)
                        VStack(alignment:.leading,spacing:4) { Text("Download from the web").font(.system(size:21,weight:.bold,design:.rounded));Text("One link or several. Each file stays on your Mac.").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                    }.allowsHitTesting(false)
                }.frame(height:50)
            }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    HStack(alignment:.top,spacing:10) {
                        ZStack(alignment:.topLeading) {
                            TextEditor(text:Binding(get:{model.linkText},set:{ if model.linkText != $0 { model.linkText=$0;model.editedLink() } }))
                                .font(.body).frame(minHeight:72,maxHeight:120).scrollContentBackground(.hidden).padding(4)
                                .disabled(model.downloading).accessibilityLabel("Media links")
                            if model.linkText.isEmpty { Text("Paste one or more media links").foregroundStyle(.secondary).padding(.top,12).padding(.leading,8).allowsHitTesting(false) }
                        }.background(Color(nsColor:.textBackgroundColor),in:RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(Color.secondary.opacity(0.35)))
                        Button { model.pasteLink() } label:{Label("Paste",systemImage:"doc.on.clipboard")}.disabled(model.downloading)
                    }
                    if model.inspecting {
                        HStack { ProgressView().controlSize(.small);LText(model.inspectingLabel).font(.callout);Spacer();Button("Cancel") { model.cancelInspection() } }
                    }
                    if let info=model.info {
                        HStack(spacing:16) {
                            Image(systemName:info.kind == .image ? "photo":info.kind == .audio ? "waveform":"play.rectangle").font(.system(size:30)).foregroundStyle(Color.hopus).frame(width:66,height:66).background(HopusPalette.sand,in:RoundedRectangle(cornerRadius:17))
                            VStack(alignment:.leading,spacing:6) {
                                Text(info.title).font(.system(size:16,weight:.semibold,design:.rounded)).lineLimit(3).textSelection(.enabled)
                                Text(details(info)).font(.caption).foregroundStyle(.secondary)
                            };Spacer(minLength:0)
                        }.padding(17).hopusCard()
                        if !info.photos.isEmpty {
                            VStack(alignment:.leading,spacing:12) {
                                HStack {
                                    Text("Select photos").font(.headline);Spacer()
                                    Button("All") { model.selectPhotos(Set(info.photos.map(\.id))) }
                                    Button("None") { model.selectPhotos([]) }
                                }
                                if info.skippedVideoCount>0 { LText("\(info.skippedVideoCount) video items are not included. Only photos will be saved.").font(.caption).foregroundStyle(.secondary) }
                                Text("Saved in post order in a new Instagram folder.").font(.caption).foregroundStyle(.secondary)
                                ForEach(info.photos) { photo in
                                    Toggle(isOn:Binding(get:{model.selectedPhotos.contains(photo.id)},set:{ selected in
                                        var ids=model.selectedPhotos;if selected { ids.insert(photo.id) } else { ids.remove(photo.id) };model.selectPhotos(ids)
                                    })) {
                                        HStack(spacing:12) {
                                            AsyncImage(url:photo.url) { image in image.resizable().scaledToFit() } placeholder:{Image(systemName:"photo").foregroundStyle(.secondary)}
                                                .frame(width:88,height:76).background(HopusPalette.sand,in:RoundedRectangle(cornerRadius:8))
                                            VStack(alignment:.leading,spacing:4) {
                                                Text("Photo \(photo.id)").font(.callout.weight(.semibold))
                                                if let width=photo.width,let height=photo.height { Text("\(width) × \(height)").font(.caption).foregroundStyle(.secondary) }
                                            };Spacer()
                                        }
                                    }.toggleStyle(.checkbox)
                                }
                            }.padding(17).hopusCard().disabled(model.downloading)
                        }
                        if info.modes.count>1 {
                            Picker("Save as",selection:$model.mode) { ForEach(info.modes,id:\.self) { LText($0.title).tag($0) } }.pickerStyle(.segmented).disabled(model.downloading)
                        }
                        if model.mode == .video,(info.heights.max() ?? 0)>720 {
                            Picker("Video quality",selection:$model.maximumHeight) {
                                Text("Best available").tag(0)
                                if (info.heights.max() ?? 0)>1080 { Text("Up to 1080p").tag(1080) }
                                if (info.heights.max() ?? 0)>720 { Text("Up to 720p").tag(720) }
                            }.disabled(model.downloading)
                        }
                    }
                    if model.info == nil,!model.batch.isEmpty {
                        VStack(alignment:.leading,spacing:12) {
                            LText("\(model.batch.count) links").font(.headline)
                            ForEach(model.batch,id:\.url.absoluteString) { item in
                                HStack(spacing:12) {
                                    Image(systemName:item.kind == .image ? "photo":item.kind == .audio ? "waveform":"play.rectangle").foregroundStyle(Color.hopus).frame(width:28)
                                    VStack(alignment:.leading,spacing:2) {
                                        Text(item.title).font(.callout.weight(.semibold)).lineLimit(2)
                                        Text(details(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength:0)
                                }
                            }
                            Text("Each link is saved on its own. A failed link does not remove files already saved.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                            let modes=model.sharedModes(model.batch)
                            if modes.count>1 {
                                Picker("Save as",selection:$model.mode) { ForEach(modes,id:\.self) { LText($0.title).tag($0) } }.pickerStyle(.segmented).disabled(model.downloading)
                            }
                            if model.batchNeedsQuality {
                                Picker("Video quality",selection:$model.maximumHeight) {
                                    Text("Best available").tag(0)
                                    if model.batchTallest>1080 { Text("Up to 1080p").tag(1080) }
                                    if model.batchTallest>720 { Text("Up to 720p").tag(720) }
                                }.disabled(model.downloading)
                            }
                        }.padding(17).hopusCard()
                    }
                    HStack(spacing:10) {
                        Image(systemName:"folder").foregroundStyle(.secondary)
                        VStack(alignment:.leading,spacing:3) { Text("SAVE TO").font(.system(size:9,weight:.bold,design:.rounded)).foregroundStyle(.secondary);Text((model.destination.path as NSString).abbreviatingWithTildeInPath).font(.caption).lineLimit(2).textSelection(.enabled) }
                        Spacer();Button("Change…") { model.chooseDestination() }.disabled(model.downloading)
                    }.padding(15).hopusCard()
                    if model.downloading {
                        VStack(alignment:.leading,spacing:9) { HStack { LText(state.progressLabel).font(.caption);Spacer();if state.progressIsDeterminate { Text(Int(state.progress*100),format:.percent).font(.caption.monospacedDigit()) } };JobProgressBar(state:state) }
                    }
                    if !model.completed.isEmpty { Label("Ready on your Mac",systemImage:"checkmark.circle.fill").foregroundStyle(HopusPalette.forest);Text(model.completed.map(\.lastPathComponent).joined(separator:"\n")).font(.caption).textSelection(.enabled) }
                    if let error=model.error { Label { LText(error) } icon:{ Image(systemName:"exclamationmark.circle") }.font(.callout).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
                    if let details=model.errorDetails {
                        DisclosureGroup {
                            VStack(alignment:.leading,spacing:8) {
                                Text(verbatim:details).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
                                Button("Copy details") { NSPasteboard.general.clearContents();NSPasteboard.general.setString(details,forType:.string) }
                            }.padding(.top,6)
                        } label:{ LText("Details").font(.caption) }
                    }
                    if state.working,!model.downloading { Text("Another task is running. Your link is ready when it finishes.").font(.caption).foregroundStyle(.secondary) }
                    VStack(alignment:.leading,spacing:7) {
                        LText(model.shortcutAvailable ? "Copy a link → ⌃⇧D, or drag it with ⌘.":"Copy a link, then choose Download Link from the Hopus menu.").font(.caption)
                        Text("Paste one link per line to download them in order. A single Instagram photo post still opens a photo selection. For videos, use the share link; for other photos, drag the image or use Copy Image Address. Public media only; login-required and protected items may be unavailable.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                if model.downloading { Button("Cancel download") { state.token.cancel() } }
                else if !model.completed.isEmpty { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(model.completed) } }
                Spacer()
                if !model.completed.isEmpty { Button("Use in Hopus") { model.onUseFiles?() }.buttonStyle(HopusButtonStyle(.primary)).disabled(state.working) }
                else if model.batch.count>1 { Button { model.download() } label:{ LText("Download \(model.batch.count) links") }.buttonStyle(HopusButtonStyle(.primary)).disabled(model.downloading || state.working) }
                else if let info=model.info { Button(!info.photos.isEmpty ? "Download \(model.selectedPhotos.count) \(model.selectedPhotos.count==1 ? "photo":"photos")":model.mode == .audioMP3 ? "Download MP3":info.kind == .image ? "Download image":"Download") { model.download() }.buttonStyle(HopusButtonStyle(.primary)).disabled(model.downloading || state.working || (!info.photos.isEmpty && model.selectedPhotos.isEmpty)) }
                else { Button((try? WebDownloadEngine.links(model.linkText))?.count ?? 0 > 1 ? "Check links":"Check link") { model.inspect() }.buttonStyle(HopusButtonStyle(.primary)).disabled(model.linkText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.inspecting) }
            }.padding(20)
        }.onChange(of:model.mode) { _ in model.configurationChanged() }.onChange(of:model.maximumHeight) { _ in model.configurationChanged() }.frame(minWidth:620,minHeight:520).background(HopusPalette.canvas).tint(.hopus).buttonStyle(HopusButtonStyle(.secondary,compact:true))
    }
    @AppStorage("appLanguage") private var language="en"
    func details(_ info:WebMediaInfo)->String {
        var details=[info.site,AppLocalization.text(info.kind.rawValue.capitalized,language:language)]
        if !info.photos.isEmpty { details.append(AppLocalization.text(info.photos.count==1 ? "1 photo":"\(info.photos.count) photos",language:language)) }
        if let width=info.imageWidth,let height=info.imageHeight { details.append("\(width) × \(height)") }
        if let duration=info.duration { details.append("\(Int(duration)/60):\(String(format:"%02d",Int(duration)%60))") }
        if let height=info.heights.max() { details.append("\(height)p") }
        if let bytes=info.byteCount { details.append(bytes.formatted(.byteCount(style:.file).locale(locale))) }
        return details.joined(separator:" · ")
    }
}
