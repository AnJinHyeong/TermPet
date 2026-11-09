import AppKit

/// 명령줄 모드: 앱을 띄우지 않고 작업 하나만 하고 종료.
///
///   TermPet --make-character <이미지> [--name 이름] [--facing right|left|front]   (내 캐릭터를 교체하고 선택)
///   TermPet --state-image <이미지> --states dragged,fall   (내 캐릭터의 일부 상태만 다른 그림으로)
///
/// 예) build/Build/Products/Debug/TermPet.app/Contents/MacOS/TermPet --make-character ~/me.png --name 나 --facing left
/// Node 비유: `process.argv`를 보고 CLI 명령을 처리한 뒤 `process.exit()`.
@MainActor
enum CommandLineTool {
    /// 처리했으면 true (이미 종료 예약됨), 일반 실행이면 false
    static func run(arguments: [String], library: CharacterLibrary) -> Bool {
        func value(_ flag: String) -> String? {
            guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }

        if let imagePath = value("--state-image") {
            guard let statesArg = value("--states") else {
                finish("usage: TermPet --state-image <image> --states dragged,fall", code: 2)
                return true
            }
            let actions = statesArg.split(separator: ",").compactMap { PetAction(rawValue: String($0)) }
            let folder = library.customFolder
            do {
                let url = URL(fileURLWithPath: (imagePath as NSString).expandingTildeInPath)
                let method = try ImageCharacterMaker.replaceStates(actions, in: folder, from: url)
                finish("ok custom states=\(actions.map(\.rawValue)) method=\(method)", code: 0)
            } catch {
                finish("error: \(error)", code: 1)
            }
            return true
        }

        guard let index = arguments.firstIndex(of: "--make-character") else { return false }

        guard index + 1 < arguments.count else {
            finish("usage: TermPet --make-character <image> [--name N] [--facing right|left|front]", code: 2)
            return true
        }
        let url = URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath)
        let facing = value("--facing").flatMap(ImageCharacterMaker.Facing.init(rawValue:)) ?? .right
        let name = value("--name") ?? "내 캐릭터"
        let staging = library.directory.appendingPathComponent(".staging", isDirectory: true)

        do {
            try? FileManager.default.removeItem(at: staging)
            let result = try ImageCharacterMaker.make(from: url, name: name, facing: facing, into: staging)
            try library.installCustom(from: result.folder)
            try? FileManager.default.removeItem(at: staging)
            finish("ok custom method=\(result.method) folder=\(library.customFolder.path)", code: 0)
        } catch {
            try? FileManager.default.removeItem(at: staging)
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
