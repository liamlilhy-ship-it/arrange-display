import Foundation

// CLI mode for headless testing and scripting:
//   DisplayManager list                capture: print connected displays
//   DisplayManager apply <a|b|c>       apply a preset
//   DisplayManager capture <path>      save current arrangement to JSON
//   DisplayManager restore <path>      apply arrangement from JSON
// With no arguments, runs as the menu bar app.

func runCLI(_ args: [String]) -> Int32 {
    let displays = DisplayService.currentDisplays()

    switch args.first {
    case "list":
        for d in displays {
            let flags = [d.isBuiltin ? "builtin" : "external", d.isMain ? "main" : nil]
                .compactMap { $0 }.joined(separator: ",")
            print("\(d.id)\t\(d.name)\t(\(Int(d.bounds.minX)),\(Int(d.bounds.minY))) \(Int(d.bounds.width))x\(Int(d.bounds.height))\t[\(flags)]\t\(d.uuid)")
        }
        return 0
    case "apply":
        guard args.count == 2, let preset = Preset(rawValue: args[1]) else {
            FileHandle.standardError.write(Data("usage: DisplayManager apply <a|b|c>\n".utf8))
            return 1
        }
        guard let target = PresetLayouts.placements(for: preset, displays: displays) else {
            FileHandle.standardError.write(Data("preset '\(args[1])' needs \(preset.requiredExternalCount) external display(s)\n".utf8))
            return 1
        }
        let placements = target.map {
            Placement(displayID: $0.display.id, x: Int32($0.origin.x.rounded()), y: Int32($0.origin.y.rounded()))
        }
        do {
            try DisplayService.apply(placements: placements)
            print("applied preset \(preset.rawValue): \(preset.title)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
    case "capture":
        guard args.count == 2 else {
            FileHandle.standardError.write(Data("usage: DisplayManager capture <path>\n".utf8))
            return 1
        }
        let placements = displays.map {
            Placement(displayID: $0.id, x: Int32($0.bounds.origin.x), y: Int32($0.bounds.origin.y))
        }
        do {
            try JSONEncoder().encode(placements).write(to: URL(fileURLWithPath: args[1]))
            print("captured \(placements.count) displays to \(args[1])")
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
    case "restore":
        guard args.count == 2 else {
            FileHandle.standardError.write(Data("usage: DisplayManager restore <path>\n".utf8))
            return 1
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            let placements = try JSONDecoder().decode([Placement].self, from: data)
            try DisplayService.apply(placements: placements)
            print("restored \(placements.count) displays from \(args[1])")
            return 0
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            return 1
        }
    default:
        FileHandle.standardError.write(Data("usage: DisplayManager [list | apply <a|b|c> | capture <path> | restore <path>]\n".utf8))
        return 1
    }
}

let cliArgs = Array(CommandLine.arguments.dropFirst())
if cliArgs.isEmpty {
    DisplayManagerApp.main()
} else {
    exit(runCLI(cliArgs))
}
