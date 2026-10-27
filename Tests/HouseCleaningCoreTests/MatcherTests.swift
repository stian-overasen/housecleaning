import Foundation
import Testing
@testable import HouseCleaningCore

struct MatcherTests {
    let matcher: Matcher = {
        var inventory = AppInventory()
        inventory.addBundleID("com.tinyspeck.slackmacgap", owner: "Slack")
        inventory.addName("Slack", owner: "Slack")
        inventory.addBundleID("com.google.Chrome", owner: "Google Chrome")
        inventory.addName("Google Chrome", owner: "Google Chrome")
        inventory.addBundleID("com.microsoft.VSCode", owner: "Visual Studio Code")
        inventory.addName("Visual Studio Code", owner: "Visual Studio Code")
        inventory.addName("act", owner: "act")
        inventory.zapPatterns["/Users/me/Library/Application Support/1Password*"] = "1Password"
        return Matcher(inventory: inventory)
    }()

    func isKept(_ name: String, path: String = "/Users/me/Library/Caches/x") -> Bool {
        if case .keep = matcher.evaluate(entryName: name, path: path) { return true }
        return false
    }

    @Test func extractsIdentifiers() {
        #expect(Matcher.identifier(fromFileName: "com.foo.Bar.plist") == "com.foo.Bar")
        #expect(Matcher.identifier(fromFileName: "BQR82RBBHL.com.tinyspeck.slackmacgap") == "com.tinyspeck.slackmacgap")
        #expect(Matcher.identifier(fromFileName: "group.com.docker") == "com.docker")
        #expect(Matcher.identifier(fromFileName: "com.postmanlabs.mac.savedState") == "com.postmanlabs.mac")
    }

    @Test func recognisesBundleIdentifiers() {
        #expect(Matcher.isBundleIdentifier("com.barco.ClickShare Client"))
        #expect(Matcher.isBundleIdentifier("dev.warp.Warp-Stable"))
        #expect(!Matcher.isBundleIdentifier("default.store"))
        #expect(!Matcher.isBundleIdentifier("Vivaldi Snapshot"))
        #expect(!Matcher.isBundleIdentifier("PhotosSearch.aapbz"))
    }

    @Test func keepsInstalledAppsAndRelatives() {
        #expect(isKept("com.tinyspeck.slackmacgap"))
        #expect(isKept("BQR82RBBHL.slack"))
        #expect(isKept("com.microsoft.VSCode.ShipIt"))
        #expect(isKept("com.google.Keystone.Agent.plist"))
        #expect(isKept("Code"))
        #expect(isKept("Google"))
        #expect(isKept("chrome_crashpad_handler"))
        #expect(isKept("act"))
    }

    @Test func keepsSystemItems() {
        #expect(isKept("com.apple.Safari"))
        #expect(isKept("CloudDocs"))
        #expect(isKept("familycircled"))
        #expect(isKept("group.is.workflow.shortcuts"))
        #expect(isKept("5F0E4CF7-EC56-44AA-A821-BB3199829F91"))
        #expect(isKept("io.sentry"))
    }

    @Test func keepsHomebrewZapPaths() {
        #expect(isKept("1Password", path: "/Users/me/Library/Application Support/1Password"))
    }

    @Test func flagsLeftovers() {
        #expect(
            matcher.evaluate(entryName: "com.postmanlabs.mac.plist", path: "/x")
                == .leftover(.high, "No installed app uses com.postmanlabs.mac"))
        #expect(
            matcher.evaluate(entryName: "Vivaldi Snapshot", path: "/x")
                == .leftover(.low, "No installed app named “Vivaldi Snapshot”"))
        #expect(!isKept("com.vivaldi.Vivaldi"))
        #expect(!isKept("BraveSoftware"))
    }
}

struct ProtectionTests {
    func matcher(gitHubTool: String?) -> Matcher {
        var inventory = AppInventory()
        inventory.gitHubToolOwner = gitHubTool
        return Matcher(inventory: inventory)
    }

    @Test func neverTouchesICloud() {
        let matcher = matcher(gitHubTool: nil)
        #expect(
            matcher.evaluate(entryName: "iCloud~com~foo~bar", path: "/x/iCloud~com~foo~bar")
                == .keep("iCloud data is never touched"))
        #expect(
            matcher.evaluate(entryName: "com.foo.CloudDocsHelper", path: "/x") == .keep("iCloud data is never touched"))
        #expect(
            matcher.evaluate(entryName: "x", path: "/Users/me/Library/Mobile Documents/x")
                == .keep("iCloud data is never touched"))
    }

    @Test func keepsGitHubDataOnlyWithGitHubTool() {
        let expected = Verdict.keep("GitHub data is kept while GitHub CLI is installed")
        #expect(
            matcher(gitHubTool: "GitHub CLI").evaluate(entryName: "com.github.GitHubClient.plist", path: "/x")
                == expected)
        #expect(matcher(gitHubTool: "GitHub CLI").evaluate(entryName: "copilot", path: "/x") == expected)
        #expect(matcher(gitHubTool: nil).evaluate(entryName: "com.github.GitHubClient.plist", path: "/x") != expected)
    }
}
