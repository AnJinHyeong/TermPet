import Foundation

// 앱 시작점.
// `TermPet --mcp`: Claude 데스크톱 앱이 MCP 서버로 실행한 경우 → 펫 화면 없이 표준 입출력으로만 대화하고 끝난다.
// 그 밖에는 평소처럼 메뉴바 앱 실행. (Node 비유: `if (process.argv.includes('--mcp')) runMcp(); else startApp()`)
if CommandLine.arguments.contains(ClaudeAppMCP.flag) {
    ClaudeAppMCP.runStdio()
    exit(0)
}
TermPetApp.main()
