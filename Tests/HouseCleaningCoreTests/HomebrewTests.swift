import Foundation
import Testing
@testable import HouseCleaningCore

struct HomebrewTests {
    @Test func parsesCaskArtifacts() throws {
        let json = """
            {
              "formulae": [
                {"name": "act", "aliases": ["nektos-act"], "dependencies": ["libyaml"]},
                {"name": "libyaml", "aliases": [], "dependencies": []},
                {"name": "php", "dependencies": [], "installed": [{"runtime_dependencies": [{"full_name": "icu4c@78"}]}]},
                {"name": "icu4c@78", "dependencies": []}
              ],
              "casks": [{
                "token": "1password",
                "name": ["1Password"],
                "artifacts": [
                  {"uninstall": [{"launchctl": ["2BUA8C4S2C.com.1password.browser-helper"], "quit": "com.1password.1password"}]},
                  {"app": ["1Password.app"], "target": "/Applications/1Password.app"},
                  {"zap": [{"trash": ["~/Library/Application Support/1Password", "/Library/Foo"]}]}
                ]
              }]
            }
            """
        let inventory = try Homebrew.parse(Data(json.utf8), home: "/Users/me")

        #expect(inventory.formulae == ["act", "nektos-act", "libyaml", "php", "icu4c@78"])
        #expect(inventory.leaves == ["act", "php"])
        let cask = try #require(inventory.casks.first)
        #expect(cask.appNames == ["1Password.app"])
        #expect(Set(cask.identifiers) == ["2BUA8C4S2C.com.1password.browser-helper", "com.1password.1password"])
        #expect(cask.zapPatterns == ["/Users/me/Library/Application Support/1Password"])
    }
}
