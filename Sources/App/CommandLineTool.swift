import AppKit

/// 명령줄 모드: 앱을 띄우지 않고 작업 하나만 하고 종료.
///
///   TermPet --make-character <이미지> [--name 이름] [--facing right|left|front] [--select]
///
/// 예) build/Build/Products/Debug/TermPet.app/Contents/MacOS/TermPet --make-character ~/me.png --name 나 --facing left --select
/// Node 비유: `process.argv`를 보고 CLI 명령을 처리한 뒤 `process.exit()`.
@MainActor
enum CommandLineTool {
    /// 처리했으면 true (이미 종료 예약됨), 일반 실행이면 false
    static func run(arguments: [String], library: CharacterLibrary) -> Bool {
        guard let index = arguments.firstIndex(of: "--make-character") else { return false }

        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }

        guard index + 1 < arguments.count else {
            finish("usage: TermPet --make-character <image> [--name N] [--facing right|left|front] [--select]", code: 2)
            return true
        }
        let url = URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath)
        let facing = value("--facing").flatMap(ImageCharacterMaker.Facing.init(rawValue:)) ?? .right
        let name = value("--name") ?? url.deletingPathExtension().lastPathComponent

        do {
            let result = try ImageCharacterMaker.make(from: url, name: name, facing: facing, into: library.directory)
            library.reload()
            let entryId = CharacterLibrary.packEntryId(result.packId)
            if arguments.contains("--select") { library.select(entryId) }
            finish("ok \(entryId) method=\(result.method) folder=\(result.folder.path)", code: 0)
        } catch {
            finish("error: \(error)", code: 1)
        }
        return true
    }

    private static func finish(_ message: String, code: Int32) {
        print(message)
        fflush(stdout)
        exit(code)
    }
}
