import Testing
@testable import GRFCore

struct ArchiveFolderTests {
    @Test func sharedParentsAreMergedAndSameNamesKeepDistinctPaths() throws {
        let tree = ArchiveFolder.tree(filePaths: [
            "readme.txt", "data/sprite/npc/a.spr", "data/sprite/npc/b.act",
            "data/palette/npc/a.pal", "other/npc/a.spr", "data/sprite/player/a.spr"
        ])
        #expect(tree.map(\.name) == ["data", "other"])
        let data = try #require(tree.first)
        let sprite = try #require(data.children?.first { $0.name == "sprite" })
        #expect(sprite.path == "data/sprite")
        #expect(sprite.children?.map(\.name) == ["npc", "player"])
        #expect(sprite.children?.first?.children == nil)
        #expect(sprite.children?.first?.id == "data/sprite/npc")
        #expect(tree.last?.children?.first?.id == "other/npc")
    }

    @Test func emptyAndRootOnlyArchivesDoNotInventFolders() {
        #expect(ArchiveFolder.tree(filePaths: []).isEmpty)
        #expect(ArchiveFolder.tree(filePaths: ["a.spr", "b.act"]).isEmpty)
    }
}
