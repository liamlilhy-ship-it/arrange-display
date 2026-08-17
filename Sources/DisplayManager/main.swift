import AppKit
import Foundation
import SwiftUI

// CLI mode for headless testing and scripting:
//   DisplayManager list                print connected displays
//   DisplayManager apply <a|b|c>       apply a preset
//   DisplayManager capture <path>      save current arrangement to JSON
//   DisplayManager restore <path>      apply arrangement from JSON
//   DisplayManager profiles            list saved custom profiles
//   DisplayManager profile <name>      apply a saved custom profile
// With no arguments, runs as the menu bar app.

func fail(_ message: String) -> Int32 {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    return 1
}

func runCLI(_ args: [String]) -> Int32 {
    let displays = DisplayService.currentDisplays()

    switch args.first {
    case "list":
        for d in displays {
            let flags = [d.isBuiltin ? "builtin" : "external",
                         d.isMain ? "main" : nil,
                         d.mirrorSourceID.map { "mirrors=\($0)" }]
                .compactMap { $0 }.joined(separator: ",")
            print("\(d.id)\t\(d.name)\t(\(Int(d.bounds.minX)),\(Int(d.bounds.minY))) \(Int(d.bounds.width))x\(Int(d.bounds.height))\t[\(flags)]\t\(d.uuid)")
        }
        return 0
    case "apply":
        guard args.count == 2, let preset = Preset(rawValue: args[1]) else {
            return fail("usage: DisplayManager apply <a|b|c>")
        }
        guard let target = PresetLayouts.placements(for: preset, displays: displays) else {
            return fail("preset '\(args[1])' needs \(preset.requiredExternalCount) external display(s)")
        }
        let placements = target.map {
            Placement(displayID: $0.display.id, x: Int32($0.origin.x.rounded()), y: Int32($0.origin.y.rounded()))
        }
        do {
            try DisplayService.apply(placements: placements)
            print("applied preset \(preset.rawValue): \(preset.title)")
            return 0
        } catch {
            return fail(error.localizedDescription)
        }
    case "capture":
        guard args.count == 2 else { return fail("usage: DisplayManager capture <path>") }
        let placements = displays.map { d in
            Placement(displayID: d.id,
                      x: Int32(d.bounds.origin.x), y: Int32(d.bounds.origin.y),
                      mirrorOf: d.mirrorSourceID)
        }
        do {
            try JSONEncoder().encode(placements).write(to: URL(fileURLWithPath: args[1]))
            print("captured \(placements.count) displays to \(args[1])")
            return 0
        } catch {
            return fail(error.localizedDescription)
        }
    case "restore":
        guard args.count == 2 else { return fail("usage: DisplayManager restore <path>") }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            let placements = try JSONDecoder().decode([Placement].self, from: data)
            try DisplayService.apply(placements: placements)
            print("restored \(placements.count) displays from \(args[1])")
            return 0
        } catch {
            return fail(error.localizedDescription)
        }
    case "profiles":
        for p in ProfileStore().profiles {
            let extras = [p.displays.contains { $0.mirrorSourceUUID != nil } ? "mirrored" : nil,
                          p.placements(matching: displays) == nil ? "not applicable now" : nil]
                .compactMap { $0 }.joined(separator: ", ")
            print("\(p.name)\t\(p.displays.count) displays\(extras.isEmpty ? "" : "\t(\(extras))")")
        }
        return 0
    case "profile":
        guard args.count == 2 else { return fail("usage: DisplayManager profile <name>") }
        guard let profile = ProfileStore().profiles.first(where: { $0.name == args[1] }) else {
            return fail("no profile named '\(args[1])'")
        }
        guard let placements = profile.placements(matching: displays) else {
            return fail("profile '\(profile.name)' doesn't match the connected displays")
        }
        do {
            try DisplayService.apply(placements: placements)
            print("applied profile '\(profile.name)'")
            return 0
        } catch {
            return fail(error.localizedDescription)
        }
    case "thumb":
        // Debug: render every arrangement thumbnail to PNG for visual inspection.
        guard args.count == 2 else { return fail("usage: DisplayManager thumb <dir>") }
        let dir = URL(fileURLWithPath: args[1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var views: [(String, ArrangementThumbView)] = Preset.allCases.map { preset in
            ("preset-\(preset.rawValue)",
             ArrangementThumbView(placements: PresetLayouts.placements(for: preset, displays: displays)
                ?? PresetLayouts.genericPlacements(for: preset)))
        }
        views += ProfileStore().profiles.map { ("profile-\($0.name)", ArrangementThumbView(profile: $0)) }
        return MainActor.assumeIsolated {
            for (name, view) in views {
                let renderer = ImageRenderer(content: view.frame(width: 72, height: 46)
                    .background(Color(white: 0.95)))
                renderer.scale = 4
                guard let cg = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
                else { return fail("failed to render \(name)") }
                do {
                    try png.write(to: dir.appendingPathComponent("\(name).png"))
                } catch {
                    return fail(error.localizedDescription)
                }
            }
            print("rendered \(views.count) thumbnails to \(dir.path)")
            return 0
        }
    default:
        return fail("usage: DisplayManager [list | apply <a|b|c> | capture <path> | restore <path> | profiles | profile <name> | thumb <dir>]")
    }
}

let cliArgs = Array(CommandLine.arguments.dropFirst())
if cliArgs.isEmpty {
    DisplayManagerApp.main()
} else {
    exit(runCLI(cliArgs))
}
