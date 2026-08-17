import Foundation

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
            let extras = [p.hasMirroring ? "mirrored" : nil,
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
    default:
        return fail("usage: DisplayManager [list | apply <a|b|c> | capture <path> | restore <path> | profiles | profile <name>]")
    }
}

let cliArgs = Array(CommandLine.arguments.dropFirst())
if cliArgs.isEmpty {
    DisplayManagerApp.main()
} else {
    exit(runCLI(cliArgs))
}
