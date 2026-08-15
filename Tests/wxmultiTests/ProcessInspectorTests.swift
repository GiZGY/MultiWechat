import XCTest
@testable import wxmulti

final class ProcessInspectorTests: XCTestCase {
    func testExecutablePathFilterOnlyMatchesExactMainExecutable() {
        let targetExecutable = "/Applications/WeChatPatched.app/Contents/MacOS/WeChat"
        let processes = [
            RunningProcess(pid: 100, command: "/Applications/WeChat.app/Contents/MacOS/WeChat"),
            RunningProcess(pid: 101, command: "/Applications/WeChatPatched.app/Contents/MacOS/WeChat"),
            RunningProcess(pid: 102, command: "/Applications/WeChatPatched.app/Contents/MacOS/WeChat --flag"),
            RunningProcess(pid: 103, command: "/Applications/WeChatPatched.app/Contents/MacOS/WeChatAppEx.app/Contents/MacOS/WeChatAppEx"),
            RunningProcess(pid: 104, command: "/Applications/WeChatPatched.app/Contents/Frameworks/wxutility --shared-files"),
        ]

        XCTAssertEqual(
            ProcessInspector.processes(withExecutablePath: targetExecutable, in: processes).map(\.pid),
            [101, 102]
        )
    }

    func testParsesPSOutputWithWhitespace() {
        let output = """
          12 /Applications/WeChat.app/Contents/MacOS/WeChat
        345\t/Applications/WeChatPatched.app/Contents/MacOS/WeChat --flag
        """

        XCTAssertEqual(
            ProcessInspector.processes(fromPSOutput: output),
            [
                RunningProcess(pid: 12, command: "/Applications/WeChat.app/Contents/MacOS/WeChat"),
                RunningProcess(pid: 345, command: "/Applications/WeChatPatched.app/Contents/MacOS/WeChat --flag"),
            ]
        )
    }
}
