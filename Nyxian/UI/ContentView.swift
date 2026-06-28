/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

import Foundation
import SwiftUI
import UIKit

@objc class ContentViewController: UIThemedTableViewController, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    var sessionIndex: IndexPath? = nil
    var projectsList: [String:[NXProject]] = [:]
    private var iconPickerProject: NXProject? = nil
    private var iconPickerIndexPath: IndexPath? = nil

    @objc init() {
        RevertUI()
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.tableView.register(ProjectTableCell.self, forCellReuseIdentifier: ProjectTableCell.reuseIdentifier)

        self.title = L10n("Projects")

        let createItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(presentProjectCreationSheet)
        )
        let importItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.down.fill"),
            style: .plain,
            target: self,
            action: #selector(presentImportPicker)
        )
        self.navigationItem.setRightBarButtonItems([createItem, importItem], animated: false)

        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        let rawProjectsList = NXProject.listProjects(at: NXBootstrap.shared().rootURL.appendingPathComponent("Projects")) as! [String:[NXProject]]
        let filtered = rawProjectsList.filter { !$0.value.isEmpty }

        let sorted = filtered.sorted { a, b in
            let keyA = a.key.lowercased()
            let keyB = b.key.lowercased()
            return sortKeys(keyA, keyB)
        }

        self.projectsList = Dictionary(uniqueKeysWithValues: sorted)

        self.tableView.reloadData()
    }

    @objc private func presentProjectCreationSheet() {
        let model = ProjectTemplateOptionsModel(schemeKind: .app)
        let view = ProjectCreationSheetView(
            model: model,
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            },
            onCreate: { [weak self] in
                guard let self = self else { return }
                if self.createProject(from: model) {
                    self.dismiss(animated: true)
                }
            }
        )

        if #available(iOS 16.4, *) {
            _ = view.presentationBackground(Color(uiColor: currentTheme!.backgroundColor))
        }

        let hostingController = UIHostingController(rootView: view)
        hostingController.modalPresentationStyle = .pageSheet
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        hostingController.view.backgroundColor = currentTheme!.backgroundColor;
        present(hostingController, animated: true)
    }

    @objc private func presentImportPicker() {
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip], asCopy: true)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .formSheet
        self.present(documentPicker, animated: true)
    }

    func addProject(_ project: NXProject) {
        let key = {
            switch project.projectConfig.schemeKind {
            case .app: return "applications"
            case .utility: return "utilities"
            default: return "unknown"
            }
        }()

        let oldSections = projectsList.keys.sorted { sortKeys($0, $1) }
        let oldSectionForKey = oldSections.firstIndex(of: key)

        if var list = self.projectsList[key] {
            list.append(project)
            self.projectsList[key] = list
        } else {
            self.projectsList[key] = [project]
        }

        let newSections = updateSections()
        let newSectionForKey = newSections.firstIndex(of: key)

        tableView.performBatchUpdates({
            if let oldIndex = oldSectionForKey, let newIndex = newSectionForKey {
                if oldIndex != newIndex {
                    tableView.deleteSections(IndexSet(integer: oldIndex), with: .fade)
                    tableView.insertSections(IndexSet(integer: newIndex), with: .fade)
                }
            } else if let newIndex = newSectionForKey {
                tableView.insertSections(IndexSet(integer: newIndex), with: .fade)
            }

            if let newIndex = newSectionForKey, let count = self.projectsList[key]?.count {
                let rowIndex = count - 1
                tableView.insertRows(at: [IndexPath(row: rowIndex, section: newIndex)], with: .automatic)
            }
        }, completion: { _ in
            if let newIndex = newSectionForKey {
                self.tableView.reloadSections(IndexSet(integer: newIndex), with: .none)
            }
        })
    }

    func removeProject(_ project: NXProject) {
        project.remove()
        let key = {
            switch project.projectConfig.schemeKind {
            case .app: return "applications"
            case .utility: return "utilities"
            default: return "unknown"
            }
        }()

        guard var list = self.projectsList[key] else { return }

        let oldSections = projectsList.keys.sorted { sortKeys($0, $1) }
        let oldSectionForKey = oldSections.firstIndex(of: key)
        let oldRow = list.firstIndex { $0.url == project.url }

        list.removeAll { $0.url == project.url }

        if list.isEmpty {
            self.projectsList.removeValue(forKey: key)
        } else {
            self.projectsList[key] = list
        }

        let newSections = updateSections()
        let newSectionForKey = newSections.firstIndex(of: key)

        tableView.performBatchUpdates({
            if let oldIndex = oldSectionForKey, let oldRow = oldRow {
                tableView.deleteRows(at: [IndexPath(row: oldRow, section: oldIndex)], with: .automatic)
            }

            if let oldIndex = oldSectionForKey, let newIndex = newSectionForKey, oldIndex != newIndex {
                tableView.deleteSections(IndexSet(integer: oldIndex), with: .fade)
                tableView.insertSections(IndexSet(integer: newIndex), with: .fade)
            } else if oldSectionForKey != nil && newSectionForKey == nil {
                tableView.deleteSections(IndexSet(integer: oldSectionForKey!), with: .fade)
            }
        }, completion: { _ in
            if let newIndex = newSectionForKey {
                self.tableView.reloadSections(IndexSet(integer: newIndex), with: .none)
            }
        })
    }

    private func updateSections() -> [String] {
        return projectsList
            .filter { !$0.value.isEmpty }
            .sorted { sortKeys($0.key, $1.key) }
            .map { $0.key }
    }

    private func sortKeys(_ a: String, _ b: String) -> Bool {
        let keyA = a.lowercased()
        let keyB = b.lowercased()
        if keyA == "applications" { return true }
        if keyB == "applications" { return false }
        if keyA == "unknown" { return false }
        if keyB == "unknown" { return true }
        return keyA < keyB
    }

    private func createProject(from optionsModel: ProjectTemplateOptionsModel) -> Bool {
        let name = optionsModel.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            NotificationServer.NotifyUser(level: .error, notification: L10n("Product name is required"))
            return false
        }

        optionsModel.saveOrganizationIdentifier()

        guard let project = NXProject.createProject(
            at: NXBootstrap.shared().rootURL.appendingPathComponent("Projects"),
            withName: name,
            withOrganizationIdentifier: optionsModel.normalizedOrganizationIdentifier,
            withBundleIdentifier: optionsModel.bundleIdentifier,
            withSchemeKind: optionsModel.schemeKind,
            withLanguageKind: optionsModel.selectedLanguage,
            withInterfaceKind: optionsModel.selectedInterface) else
        {
            NotificationServer.NotifyUser(level: .error, notification: L10n("Failed to create project"))
            return false
        }

        addProject(project)
        return true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let indexPath = sessionIndex {
            let keys = Array(self.projectsList.keys).sorted()
            let key = keys[indexPath.section]
            let sectionProjects = self.projectsList[key] ?? []
            let selectedProject: NXProject = sectionProjects[indexPath.row]
            selectedProject.reload()
            self.tableView.reloadRows(at: [indexPath], with: .none)
            sessionIndex = nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let keys = Array(self.projectsList.keys).sorted()
        let key = keys[section]
        let sectionProjects = self.projectsList[key] ?? []
        return String(format: L10n("%@ (%d)"), localizedProjectSectionTitle(for: key), sectionProjects.count)
    }

    private func localizedProjectSectionTitle(for key: String) -> String {
        switch key.lowercased() {
            case "applications": return L10n("Applications")
            case "utilities": return L10n("Utilities")
            case "unknown": return L10n("Unknown")
            default: return key.capitalized
        }
    }

    private func defaultIcon(for project: NXProject) -> UIImage? {
        return project.projectConfig.schemeKind == .app ? UIImage(named: "DefaultIcon") : UIImage(named: "UtilityIcon")
    }

    private func configuredPrimaryIcon(for project: NXProject) -> UIImage? {
        guard project.projectConfig.schemeKind == .app,
              let icons = project.projectConfig.infoDictionary["CFBundleIcons"] as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
              !iconFiles.isEmpty else {
            return nil
        }

        guard let resourcesURL = project.resourcesURL else {
            return nil
        }
        let fileManager = FileManager.default

        for iconFile in iconFiles.reversed() {
            let baseName = (iconFile as NSString).deletingPathExtension
            let ext = (iconFile as NSString).pathExtension
            let candidates: [String]

            if ext.isEmpty {
                candidates = [
                    "\(baseName)@3x.png",
                    "\(baseName)@2x.png",
                    "\(baseName).png",
                    "\(baseName)@3x.jpg",
                    "\(baseName)@2x.jpg",
                    "\(baseName).jpg",
                    "\(baseName)@3x.jpeg",
                    "\(baseName)@2x.jpeg",
                    "\(baseName).jpeg"
                ]
            } else {
                candidates = [
                    "\(baseName)@3x.\(ext)",
                    "\(baseName)@2x.\(ext)",
                    iconFile
                ]
            }

            for candidate in candidates {
                let path = resourcesURL.appendingPathComponent(candidate).path
                if fileManager.fileExists(atPath: path), let image = UIImage(contentsOfFile: path) {
                    return image
                }
            }
        }

        return nil
    }

    private func projectIcon(for project: NXProject) -> UIImage? {
        return configuredPrimaryIcon(for: project) ?? defaultIcon(for: project)
    }

    private func canPickIcon(for project: NXProject) -> Bool {
        return project.projectConfig.schemeKind == .app
    }

    private func presentIconPicker(for project: NXProject, at indexPath: IndexPath) {
        guard canPickIcon(for: project) else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            NotificationServer.NotifyUser(level: .error, notification: L10n("Photo Library is not available"))
            return
        }

        iconPickerProject = project
        iconPickerIndexPath = indexPath

        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = true
        picker.delegate = self
        present(picker, animated: true)
    }

    private func squareImage(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height)
        let rect = CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
        guard let cropped = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private func resizedPNGData(from image: UIImage, size: CGSize) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.pngData()
    }

    private func saveIcon(_ image: UIImage, for project: NXProject) throws {
        guard let resourcesURL = project.resourcesURL else {
            throw NSError(domain: "com.susu.code.projectIcon", code: 5, userInfo: [NSLocalizedDescriptionKey: "Resources folder is not available"])
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        guard let square = squareImage(from: image) else {
            throw NSError(domain: "com.susu.code.projectIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"])
        }

        let files: [(String, CGSize)] = [
            ("AppIcon60x60.png", CGSize(width: 60, height: 60)),
            ("AppIcon60x60@2x.png", CGSize(width: 120, height: 120)),
            ("AppIcon60x60@3x.png", CGSize(width: 180, height: 180))
        ]

        for (fileName, size) in files {
            guard let data = resizedPNGData(from: square, size: size) else {
                throw NSError(domain: "com.susu.code.projectIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to resize image"])
            }
            try data.write(to: resourcesURL.appendingPathComponent(fileName), options: .atomic)
        }

        let plistURL = project.url.appendingPathComponent("Config/Project.plist")
        let plistData = try Data(contentsOf: plistURL)
        guard var plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
            throw NSError(domain: "com.susu.code.projectIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid Project.plist"])
        }

        let iconInfo: [String: Any] = [
            "CFBundlePrimaryIcon": [
                "CFBundleIconFiles": ["AppIcon60x60"],
                "CFBundleIconName": "AppIcon"
            ]
        ]

        if var bundleInfo = plist["NXBundleInfo"] as? [String: Any] {
            bundleInfo["CFBundleIcons"] = iconInfo
            plist["NXBundleInfo"] = bundleInfo
        } else if var bundleInfo = plist["LDEBundleInfo"] as? [String: Any] {
            bundleInfo["CFBundleIcons"] = iconInfo
            plist["LDEBundleInfo"] = bundleInfo
        } else {
            plist["NXBundleInfo"] = [
                "CFBundleIcons": iconInfo
            ]
        }

        let outputData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try outputData.write(to: plistURL, options: .atomic)
        _ = project.reload()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        iconPickerProject = nil
        iconPickerIndexPath = nil
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let project = iconPickerProject else {
            picker.dismiss(animated: true)
            return
        }

        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        do {
            guard let image = image else {
                throw NSError(domain: "com.susu.code.projectIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "No image selected"])
            }
            try saveIcon(image, for: project)
            if let indexPath = iconPickerIndexPath {
                tableView.reloadRows(at: [indexPath], with: .automatic)
            } else {
                tableView.reloadData()
            }
        } catch {
            NotificationServer.NotifyUser(level: .error, notification: error.localizedDescription)
        }

        picker.dismiss(animated: true)
        iconPickerProject = nil
        iconPickerIndexPath = nil
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let keys = Array(self.projectsList.keys).sorted()
        let key = keys[section]
        let sectionProjects = self.projectsList[key] ?? []
        return sectionProjects.count
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.projectsList.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let keys = Array(self.projectsList.keys).sorted()
        let key = keys[indexPath.section]
        let sectionProjects = self.projectsList[key] ?? []
        let project: NXProject = sectionProjects[indexPath.row];
        let cell: ProjectTableCell = self.tableView.dequeueReusableCell(withIdentifier: ProjectTableCell.reuseIdentifier) as! ProjectTableCell
        cell.configure(displayName: project.projectConfig.displayName, bundleIdentifier: project.projectConfig.bundleid, appIcon: projectIcon(for: project), showArrow: UIDevice.current.userInterfaceIdiom != .pad, iconTapAction: canPickIcon(for: project) ? { [weak self] in
            self?.presentIconPicker(for: project, at: indexPath)
        } : nil)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        sessionIndex = indexPath

        let keys = Array(self.projectsList.keys).sorted()
        let key = keys[indexPath.section]
        let sectionProjects = self.projectsList[key] ?? []

        let selectedProject: NXProject = sectionProjects[indexPath.row]

        if UIDevice.current.userInterfaceIdiom == .pad {
            let padFileVC: MainSplitViewController = MainSplitViewController(project: selectedProject)
            padFileVC.modalPresentationStyle = .fullScreen
            self.present(padFileVC, animated: true)
        } else {
            let fileVC = FileListViewController(project: selectedProject)
            self.navigationController?.pushViewController(fileVC, animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggestedActions in
            let export: UIAction = UIAction(title: L10n("Export"), image: UIImage(systemName: "square.and.arrow.up.fill")) { [weak self] _ in
                DispatchQueue.global().async {
                    guard let self = self else { return }

                    let keys = Array(self.projectsList.keys).sorted()
                    let key = keys[indexPath.section]
                    let sectionProjects = self.projectsList[key] ?? []
                    let project: NXProject = sectionProjects[indexPath.row]

                    let zipPath: String = "\(NSTemporaryDirectory())/\(project.projectConfig.displayName!).zip"
                    zipDirectoryAtPath(project.url.path, zipPath, true)
                    share(url: URL(fileURLWithPath: zipPath), remove: true)
                }
            }

            let item: UIAction = UIAction(title: L10n("Remove"), image: UIImage(systemName: "trash.fill"), attributes: .destructive) { _ in
                let keys = Array(self.projectsList.keys).sorted()
                let key = keys[indexPath.section]
                let sectionProjects = self.projectsList[key] ?? []
                let project = sectionProjects[indexPath.row]

                self.presentConfirmationAlert(
                    title: L10n("Warning"),
                    message: String(format: L10n("Are you sure you want to remove \"%@\"?"), project.projectConfig.displayName!),
                    confirmTitle: L10n("Remove"),
                    confirmStyle: .destructive)
                { [weak self] in
                    guard let self = self else { return }
                    removeProject(project)
                }
            }

            return UIMenu(children: [export, item])
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        do {
            guard let selectedURL = urls.first else { return }

            let extractFirst = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Proj")

            if FileManager.default.fileExists(atPath: extractFirst.path) {
                try FileManager.default.removeItem(at: extractFirst)
            }
            try FileManager.default.createDirectory(at: extractFirst, withIntermediateDirectories: true)

            guard unzipArchiveAtPath(selectedURL.path, extractFirst.path) else {
                try? FileManager.default.removeItem(at: extractFirst)
                throw CocoaError(.fileReadCorruptFile)
            }

            // Removing the __MAXOSX shit
            let items = try FileManager.default.contentsOfDirectory(atPath: extractFirst.path).filter { !$0.hasPrefix("__") && !$0.hasPrefix(".") }

            guard let firstItem = items.first else {
                try? FileManager.default.removeItem(at: extractFirst)
                throw CocoaError(.fileReadNoSuchFile)
            }

            let projectPath = "\(NXBootstrap.shared().rootURL.appendingPathComponent("/Projects").path)/\(UUID().uuidString)"

            do {
                try FileManager.default.moveItem(
                    atPath: extractFirst.appendingPathComponent(firstItem).path,
                    toPath: projectPath
                )
            } catch {
                try? FileManager.default.removeItem(at: extractFirst)
                throw error
            }

            try? FileManager.default.removeItem(at: extractFirst)

            if let project = NXProject(url: URL(fileURLWithPath: projectPath)) {
                addProject(project)
            }
        } catch {
            NotificationServer.NotifyUser(level: .error, notification: error.localizedDescription)
        }
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let keys = Array(self.projectsList.keys).sorted()
        let key = keys[indexPath.section]
        if #available(iOS 26.0, *) {
            return 80
        } else {
            return 70
        }
    }
}

final class ProjectTemplateOptionsModel: ObservableObject {
    private static let organizationIdentifierDefaultsKey = "LDEOrganizationPrefix"
    private static let defaultOrganizationIdentifier = "com.example"
    private static let allowedIdentifierCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")

    @Published var step: ProjectCreationStep = .template
    @Published private(set) var schemeKind: NXProjectSchemeKind
    private let appLanguages: [ProjectTemplatePickerOption] = [
        ProjectTemplatePickerOption(id: "Swift", title: "Swift"),
        ProjectTemplatePickerOption(id: "ObjC", title: "Objective-C")
    ]
    private let utilityLanguages: [ProjectTemplatePickerOption] = [
        ProjectTemplatePickerOption(id: "Swift", title: "Swift"),
        ProjectTemplatePickerOption(id: "ObjC", title: "Objective-C"),
        ProjectTemplatePickerOption(id: "C++", title: "C++"),
        ProjectTemplatePickerOption(id: "C", title: "C")
    ]
    private let interfaces: [ProjectTemplatePickerOption] = [
        ProjectTemplatePickerOption(id: "SwiftUI", title: "SwiftUI"),
        ProjectTemplatePickerOption(id: "UIKit", title: "UIKit")
    ]

    @Published var productName = ""
    @Published var organizationIdentifier: String
    @Published private var selectedLanguageID = "Swift"
    @Published private var selectedInterfaceID = "SwiftUI"

    init(schemeKind: NXProjectSchemeKind) {
        self.schemeKind = schemeKind
        self.organizationIdentifier = UserDefaults.standard.string(forKey: Self.organizationIdentifierDefaultsKey) ?? Self.defaultOrganizationIdentifier
    }

    var showsAppOptions: Bool {
        return schemeKind == .app
    }

    var normalizedOrganizationIdentifier: String {
        return Self.organizationIdentifier(from: organizationIdentifier)
    }

    var bundleIdentifier: String {
        let productIdentifier = Self.productIdentifier(from: productName)
        return [normalizedOrganizationIdentifier, productIdentifier]
            .filter { !$0.isEmpty }
            .joined(separator: ".")
    }

    var selectedLanguage: NXProjectLanguageKind {
        switch selectedLanguageID {
        case "ObjC": return .objectiveC
        case "C++": return .CXX
        case "C": return .C
        default: return .swift
        }
    }

    var selectedInterface: NXProjectInterfaceKind {
        guard schemeKind == .app else { return .unknown }
        return selectedInterfaceID == "SwiftUI" ? .swiftUI : .uiKit
    }

    var languageSelection: String {
        get { selectedLanguageID }
        set { selectLanguage(id: newValue) }
    }

    var interfaceSelection: String {
        get { selectedInterfaceID }
        set { selectInterface(id: newValue) }
    }

    var languageOptions: [ProjectTemplatePickerOption] {
        if schemeKind == .utility {
            return utilityLanguages
        }
        return appLanguages
    }

    var interfaceDisabledIDs: Set<String> {
        selectedLanguageID == "ObjC" ? ["SwiftUI"] : []
    }

    var interfaceOptions: [ProjectTemplatePickerOption] {
        return interfaces
    }

    func selectProjectType(_ schemeKind: NXProjectSchemeKind) {
        self.schemeKind = schemeKind
        if schemeKind == .app {
            switch selectedLanguageID {
            case "Swift", "ObjC":
                break
            default:
                selectedLanguageID = "Swift"
            }
        }

        if selectedInterfaceID == "SwiftUI" {
            selectedLanguageID = "Swift"
        }
    }

    func saveOrganizationIdentifier() {
        let value = normalizedOrganizationIdentifier
        guard !value.isEmpty else { return }
        organizationIdentifier = value
        UserDefaults.standard.set(value, forKey: Self.organizationIdentifierDefaultsKey)
    }

    private func selectLanguage(id: String) {
        selectedLanguageID = id
        if selectedLanguageID == "ObjC" {
            selectedInterfaceID = "UIKit"
        }
    }

    private func selectInterface(id: String) {
        selectedInterfaceID = id
        if selectedInterfaceID == "SwiftUI" {
            selectedLanguageID = "Swift"
        }
    }

    private static func organizationIdentifier(from value: String) -> String {
        return value
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { productIdentifier(from: String($0).lowercased()) }
            .filter { !$0.isEmpty }
            .joined(separator: ".")
    }

    private static func productIdentifier(from value: String) -> String {
        let source = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var output = ""
        var lastWasReplacement = false

        for scalar in source.unicodeScalars {
            if allowedIdentifierCharacters.contains(scalar) {
                output.unicodeScalars.append(scalar)
                lastWasReplacement = false
            } else if !lastWasReplacement {
                output.append("-")
                lastWasReplacement = true
            }
        }

        return output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

struct ProjectTemplateOptionsView: View {
    @ObservedObject var model: ProjectTemplateOptionsModel

    private var textColor: Color { Color(uiColor: currentTheme!.textColor) }
    private var hairlineColor: Color { Color(uiColor: currentTheme!.gutterHairlineColor) }
    private var groupBackground: Color { textColor.opacity(0.05) }
    private var secondaryTextColor: Color { textColor.opacity(0.6) }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                templateTextField(
                    label: L10n("Product Name"),
                    placeholder: L10n("Product Name"),
                    text: $model.productName
                )
                themedDivider
                templateTextField(
                    label: L10n("Organization Identifier"),
                    placeholder: "com.example",
                    text: $model.organizationIdentifier,
                    keyboardType: .URL
                )
                themedDivider
                generatedIdentifierRow
            }
            .background(groupBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(spacing: 8) {
                if model.showsAppOptions {
                    ProjectTemplatePickerRow(
                        title: L10n("Interface:"),
                        options: model.interfaceOptions,
                        disabledIDs: model.interfaceDisabledIDs,
                        selectionID: Binding(
                            get: { model.interfaceSelection },
                            set: { model.interfaceSelection = $0 }
                        )
                    )
                }

                ProjectTemplatePickerRow(
                    title: L10n("Language:"),
                    options: model.languageOptions,
                    selectionID: Binding(
                        get: { model.languageSelection },
                        set: { model.languageSelection = $0 }
                    )
                )
            }
        }
        .padding(.top, 2)
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var themedDivider: some View {
        Rectangle()
            .fill(hairlineColor)
            .frame(height: 1 / UIScreen.main.scale)
            .padding(.leading, 12)
    }

    private var generatedIdentifierRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n("Bundle Identifier"))
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
            Text(model.bundleIdentifier.isEmpty ? " " : model.bundleIdentifier)
                .font(.callout)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func templateTextField(label: String,
                                   placeholder: String,
                                   text: Binding<String>,
                                   keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(textColor)
                .tint(textColor)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
