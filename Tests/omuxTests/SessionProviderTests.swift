import XCTest
@testable import omux

final class SessionProviderTests: XCTestCase {
    func testLegacyWorkspacePreservesClaudeIdentityAndCommand() throws {
        let id = UUID()
        let data = Data("""
        {"command":"claude --model opus","tabs":[{"claudeSessionID":"\(id)","name":"Existing"}]}
        """.utf8)
        let group = try JSONDecoder().decode(TabGroup.self, from: data)
        XCTAssertEqual(group.provider, .claude)
        XCTAssertEqual(group.tabs[0].claudeSessionID, id)
        XCTAssertEqual(group.tabs[0].resolvedProvider(in: group), .claude)
        XCTAssertEqual(group.command, "claude --model opus")
    }

    func testValuesFromANewerVersionDoNotDropTheWorkspace() throws {
        let data = Data("""
        {"groups":[{"name":"Work","command":"codex","provider":"future","tabs":[{"name":"A","provider":"future","color":"future","command":"claude"}]}]}
        """.utf8)
        let group = try XCTUnwrap(JSONDecoder().decode(Workspace.self, from: data).groups.first)
        XCTAssertEqual(group.provider, .codex)
        XCTAssertNil(group.tabs[0].provider)
        XCTAssertEqual(group.tabs[0].resolvedProvider(in: group), .claude)
        XCTAssertEqual(group.tabs[0].color, TabColor.none)
    }

    func testShellOverrideDoesNotInheritProjectAgent() {
        var group = TabGroup(name: "Project")
        group.command = "agy"
        group.provider = .gemini
        let tab = TabItem(name: "Shell", command: "")
        XCTAssertEqual(tab.resolvedProvider(in: group), .shell)
    }

    func testNewProjectStartsWithPlainTerminal() throws {
        let group = TabGroup(name: "Project", tabs: [TabItem(name: "Session 1")])
        let restored = try JSONDecoder().decode(TabGroup.self, from: JSONEncoder().encode(group))
        XCTAssertEqual(restored.command, "")
        XCTAssertEqual(restored.tabs[0].resolvedProvider(in: restored), .shell)
    }

    func testCodexIdentitySurvivesRoundTrip() throws {
        var group = TabGroup(name: "Project")
        group.provider = .codex
        group.command = "codex"
        var tab = TabItem(name: "Codex")
        tab.codexThreadID = "thread-assigned-by-server"
        group.tabs = [tab]
        let restored = try JSONDecoder().decode(TabGroup.self, from: JSONEncoder().encode(group))
        XCTAssertEqual(restored.tabs[0].resolvedProvider(in: restored), .codex)
        XCTAssertEqual(restored.tabs[0].codexThreadID, tab.codexThreadID)
    }

    func testCustomCommandsRemainCustom() {
        for command in ["env codex", "codex exec task", "env gemini", "npm run dev", "/path/to/wrapper"] {
            XCTAssertEqual(SessionProvider.infer(command: command), .custom)
        }
    }

    func testGeminiCommandsAreRecognized() {
        XCTAssertEqual(SessionProvider.infer(command: "gemini"), .gemini)
        XCTAssertEqual(SessionProvider.infer(command: "gemini --model gemini-2.5-pro"), .gemini)
        XCTAssertEqual(SessionProvider.infer(command: "agy"), .gemini)
        XCTAssertEqual(SessionProvider.gemini.command, "agy")
    }

    func testAgentCommandsAreStableWhenProjectDefaultsChange() throws {
        var group = TabGroup(name: "Project")
        group.provider = .gemini
        group.command = "agy"
        var tab = TabItem(name: "Existing", command: "agy")
        tab.provider = .gemini
        group.tabs = [tab]
        group.provider = .codex
        group.command = "codex"
        XCTAssertEqual(group.tabs[0].resolvedProvider(in: group), .gemini)
        XCTAssertEqual(group.tabs[0].command, "agy")
    }

    func testClaudeStartsANewPinnedConversationInsteadOfContinuingAnotherTab() {
        let id = UUID()
        XCTAssertEqual(SessionProvider.claudeCommand("claude --model opus", sessionID: id, conversationExists: false),
                       "claude --session-id \(id.uuidString.lowercased()) --model opus")
        XCTAssertEqual(SessionProvider.claudeCommand("claude", sessionID: id, conversationExists: true),
                       "claude --resume \(id.uuidString.lowercased())")
    }

    func testExplicitClaudeSessionFlagsArePreserved() {
        for raw in ["claude --resume abc", "claude --resume=abc", "claude --session-id=abc", "claude --continue"] {
            XCTAssertEqual(SessionProvider.claudeCommand(raw, sessionID: UUID(), conversationExists: false), raw)
        }
    }

    func testAgentsDoNotStartOnTheirOwnInTheHomeFolder() {
        let home = "/Users/me"
        for provider in [SessionProvider.claude, .codex, .gemini] {
            XCTAssertFalse(provider.startsAutomatically(in: "/Users/me", home: home))
            XCTAssertFalse(provider.startsAutomatically(in: "/Users/me/", home: home))
            XCTAssertFalse(provider.startsAutomatically(in: "/Users/me/app/..", home: home))
            XCTAssertTrue(provider.startsAutomatically(in: "/Users/me/app", home: home))
        }
    }

    func testTildeMeansTheHomeFolder() {
        XCTAssertFalse(SessionProvider.claude.startsAutomatically(in: "~"))
        XCTAssertTrue(SessionProvider.claude.startsAutomatically(in: "~/app"))
    }

    func testShellsAndCustomCommandsStillStartInTheHomeFolder() {
        XCTAssertTrue(SessionProvider.shell.startsAutomatically(in: "/Users/me", home: "/Users/me"))
        XCTAssertTrue(SessionProvider.custom.startsAutomatically(in: "/Users/me", home: "/Users/me"))
    }
}
