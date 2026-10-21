import XCTest
@testable import SpaceCrunchCore

final class TreemapLayoutTests: XCTestCase {
    func testTilesStayInsideBoundsAndFillTheRect() {
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let tiles = TreemapLayout.layout(values: values, in: rect)

        XCTAssertEqual(tiles.count, values.count)
        var area: CGFloat = 0
        for tile in tiles {
            XCTAssertTrue(rect.insetBy(dx: -0.5, dy: -0.5).contains(tile), "Tile escaped bounds: \(tile)")
            XCTAssertGreaterThan(tile.width, 0)
            XCTAssertGreaterThan(tile.height, 0)
            area += tile.width * tile.height
        }
        XCTAssertEqual(Double(area), Double(rect.width * rect.height), accuracy: 1)
    }

    func testTilesDoNotOverlap() {
        let values: [Double] = [12, 9, 8, 5, 4, 3, 2, 1, 1, 0.5]
        let tiles = TreemapLayout.layout(values: values, in: CGRect(x: 0, y: 0, width: 800, height: 500))

        for first in tiles.indices {
            for second in tiles.indices where second > first {
                let intersection = tiles[first].intersection(tiles[second])
                let overlap = intersection.isNull ? 0 : intersection.width * intersection.height
                XCTAssertLessThan(overlap, 0.5, "Tiles \(first) and \(second) overlap")
            }
        }
    }

    func testLargerValuesGetLargerTiles() {
        let values: [Double] = [10, 5, 1]
        let tiles = TreemapLayout.layout(values: values, in: CGRect(x: 0, y: 0, width: 500, height: 500))
        let areas = tiles.map { $0.width * $0.height }
        XCTAssertGreaterThan(areas[0], areas[1])
        XCTAssertGreaterThan(areas[1], areas[2])
    }

    func testSingleValueFillsRect() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 200)
        let tiles = TreemapLayout.layout(values: [42], in: rect)
        XCTAssertEqual(tiles[0], rect)
    }

    func testEmptyAndZeroValuesAreSafe() {
        XCTAssertTrue(TreemapLayout.layout(values: [], in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
        let tiles = TreemapLayout.layout(values: [0, 0], in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(tiles.count, 2)
        XCTAssertEqual(tiles[0], .zero)
    }
}

final class SizeTextTests: XCTestCase {
    func testDecimalUnits() {
        XCTAssertEqual(SizeText.string(0), "0 bytes")
        XCTAssertEqual(SizeText.string(1), "1 byte")
        XCTAssertEqual(SizeText.string(999), "999 bytes")
        XCTAssertEqual(SizeText.string(1_000), "1 KB")
        XCTAssertEqual(SizeText.string(1_500), "1.5 KB")
        XCTAssertEqual(SizeText.string(123_000), "123 KB")
        XCTAssertEqual(SizeText.string(1_500_000_000), "1.5 GB")
    }

    func testPercent() {
        XCTAssertEqual(SizeText.percent(0), "0%")
        XCTAssertEqual(SizeText.percent(0.5), "50%")
        XCTAssertEqual(SizeText.percent(0.004), "<1%")
        XCTAssertEqual(SizeText.percent(1.5), "100%")
    }

    func testAbbreviatedPath() {
        XCTAssertEqual(SizeText.abbreviatedPath("/Users/sam/Documents/a.pdf", home: "/Users/sam"), "~/Documents/a.pdf")
        XCTAssertEqual(SizeText.abbreviatedPath("/Users/sam", home: "/Users/sam"), "~")
        XCTAssertEqual(SizeText.abbreviatedPath("/Applications", home: "/Users/sam"), "/Applications")
    }
}

final class FileClassifierTests: XCTestCase {
    func testExtensionCategories() {
        XCTAssertEqual(FileClassifier.extensionCategory("HEIC"), .photos)
        XCTAssertEqual(FileClassifier.extensionCategory("mov"), .video)
        XCTAssertEqual(FileClassifier.extensionCategory("flac"), .audio)
        XCTAssertEqual(FileClassifier.extensionCategory("pdf"), .documents)
        XCTAssertEqual(FileClassifier.extensionCategory("dmg"), .archives)
        XCTAssertNil(FileClassifier.extensionCategory(""))
        XCTAssertNil(FileClassifier.extensionCategory("weirdext"))
    }

    func testStructuralCategories() {
        XCTAssertEqual(
            FileClassifier.structuralCategory(forPath: "/Users/sam/Library/Caches/App/x.bin", home: "/Users/sam"),
            .caches
        )
        XCTAssertEqual(
            FileClassifier.structuralCategory(forPath: "/Users/sam/Projects/app/node_modules/x/index.js", home: "/Users/sam"),
            .developer
        )
        XCTAssertEqual(
            FileClassifier.structuralCategory(forPath: "/Applications/Mail.app/Contents/MacOS/Mail", home: "/Users/sam"),
            .apps
        )
        XCTAssertEqual(
            FileClassifier.structuralCategory(
                forPath: "/Users/sam/Library/Containers/com.example.App/Data/Library/Caches/blob.bin",
                home: "/Users/sam"
            ),
            .caches
        )
    }

    func testInstallerDetection() {
        XCTAssertTrue(FileClassifier.isInstaller(name: "Thing.dmg"))
        XCTAssertTrue(FileClassifier.isInstaller(name: "Thing.PKG"))
        XCTAssertFalse(FileClassifier.isInstaller(name: "Thing.jpg"))
    }

    func testFolderNamesRecogniseDeveloperWork() {
        XCTAssertEqual(FileClassifier.folderNameCategory(name: "Developer"), .developer)
        XCTAssertEqual(FileClassifier.folderNameCategory(name: "projects"), .developer)
        XCTAssertEqual(FileClassifier.folderNameCategory(name: "node_modules"), .developer)
        XCTAssertEqual(FileClassifier.folderNameCategory(name: ".build"), .developer)
        XCTAssertNil(FileClassifier.folderNameCategory(name: "Pictures"))
        XCTAssertNil(FileClassifier.folderNameCategory(name: ""))
    }

    func testTopLevelCategoriesLeaveContentNeutralFoldersAlone() {
        XCTAssertEqual(FileClassifier.topLevelCategory(path: "/Users/sam/Downloads"), .downloads)
        XCTAssertEqual(FileClassifier.topLevelCategory(path: "/Users/sam/Movies"), .video)
        XCTAssertEqual(FileClassifier.topLevelCategory(path: "/Users/sam/Pictures"), .photos)
        XCTAssertEqual(FileClassifier.topLevelCategory(path: "/Users/sam/Documents"), .documents)
        // `~/Library` is wherever apps happen to keep their data, so its colour
        // has to come from its contents, not its path.
        XCTAssertNil(FileClassifier.topLevelCategory(path: "/Users/sam/Library"))
        XCTAssertNil(FileClassifier.topLevelCategory(path: "/Users/sam/.Trash"))
    }

    func testVirtualMachineDisksCountAsArchives() {
        XCTAssertEqual(FileClassifier.extensionCategory("vmdk"), .archives)
        XCTAssertEqual(FileClassifier.extensionCategory("vmem"), .archives)
        XCTAssertEqual(FileClassifier.extensionCategory("qcow2"), .archives)
    }
}

final class ScannerTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceCrunchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixture {
            try? FileManager.default.removeItem(at: fixture)
        }
    }

    func testScanFindsSizesCategoriesAndCleanupGroups() async throws {
        let home = fixture!
        try writeFile("Documents/report.txt", megabytes: 0.01, in: home)
        try writeFile("Library/Caches/BigApp/cache.bin", megabytes: 2, in: home)
        try writeFile("Library/Logs/App/app.log", megabytes: 1, in: home)
        try writeFile("Projects/app/node_modules/pkg/index.js", megabytes: 11, in: home)
        try writeFile("Projects/app/.build/debug/out.o", megabytes: 11, in: home)
        try writeFile("Library/Developer/Xcode/DerivedData/Project-abc/build.o", megabytes: 6, in: home)
        try writeFile(".Trash/old.bin", megabytes: 2, in: home)

        let installer = home.appendingPathComponent("Downloads/old.dmg")
        try writeFile("Downloads/old.dmg", megabytes: 2, in: home)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60 * 24 * 60 * 60)],
            ofItemAtPath: installer.path
        )

        let scanner = DiskScanner(
            configuration: ScanConfiguration(
                homeURL: home,
                extraRoots: [],
                largeFileThreshold: 5_000_000,
                now: Date(),
                maxConcurrentRoots: 2,
                oldInstallerMinimumSize: 1_000_000,
                oldInstallerMinimumAge: 30 * 24 * 60 * 60
            )
        )

        let snapshot = try await scanner.scan()

        XCTAssertGreaterThan(snapshot.totalScanned, 30_000_000)
        XCTAssertGreaterThan(snapshot.fileCount, 5)
        XCTAssertEqual(snapshot.browseRoot.children["Home"]?.name, "Home")
        XCTAssertGreaterThan(snapshot.categories[.caches] ?? 0, 2_000_000)
        XCTAssertGreaterThan(snapshot.categories[.developer] ?? 0, 20_000_000)
        XCTAssertFalse(snapshot.largeFiles.isEmpty)

        let groupIDs = Set(snapshot.cleanupGroups.map(\.id))
        XCTAssertTrue(groupIDs.contains("caches"))
        XCTAssertTrue(groupIDs.contains("logs"))
        XCTAssertTrue(groupIDs.contains("xcode-derived"))
        XCTAssertTrue(groupIDs.contains("node-modules"))
        XCTAssertTrue(groupIDs.contains("build-artifacts"))
        XCTAssertTrue(groupIDs.contains("trash"))
        XCTAssertTrue(groupIDs.contains("old-installers"))

        // Home folder contains the fixture's top-level entries.
        let homeRoot = try XCTUnwrap(snapshot.homeRoot)
        XCTAssertNotNil(homeRoot.children["Documents"])
        XCTAssertNotNil(homeRoot.children["Library"])
        XCTAssertNotNil(homeRoot.children["Projects"])
    }

    func testApplyDeletionUpdatesSnapshotWithoutRescan() async throws {
        let home = fixture!
        try writeFile("Projects/app/node_modules/pkg/index.js", megabytes: 11, in: home)
        try writeFile("Documents/report.txt", megabytes: 0.01, in: home)

        let scanner = DiskScanner(
            configuration: ScanConfiguration(
                homeURL: home,
                extraRoots: [],
                largeFileThreshold: 5_000_000,
                now: Date(),
                maxConcurrentRoots: 1
            )
        )

        var snapshot = try await scanner.scan()
        let nodeModules = try XCTUnwrap(
            snapshot.cleanupGroups.first(where: { $0.id == "node-modules" })?.items.first
        )
        let beforeTotal = snapshot.totalScanned
        let beforeNodeSize = snapshot.homeRoot?.children["Projects"]?.children["app"]?.children["node_modules"]?.size

        snapshot.applyDeletion(of: [nodeModules])

        XCTAssertEqual(snapshot.totalScanned, beforeTotal - nodeModules.size)
        XCTAssertFalse(snapshot.cleanupGroups.contains(where: { $0.id == "node-modules" }))
        XCTAssertNil(snapshot.homeRoot?.children["Projects"]?.children["app"]?.children["node_modules"])
        if let beforeNodeSize {
            XCTAssertLessThan(
                snapshot.homeRoot?.children["Projects"]?.children["app"]?.size ?? 0,
                beforeNodeSize
            )
        }
    }

    private func writeFile(_ relativePath: String, megabytes: Double, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = Data(repeating: 0x42, count: Int(megabytes * 1_000_000))
        try data.write(to: url)
    }
}

final class FolderClassificationTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceCrunchClassification-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixture {
            try? FileManager.default.removeItem(at: fixture)
        }
    }

    func testFolderIsColouredByWhatActuallyFillsIt() async throws {
        let home = fixture!
        // A folder whose name says nothing, holding almost nothing but video.
        try write("Archive/holiday.mov", megabytes: 12, in: home)
        try write("Archive/notes.txt", megabytes: 0.01, in: home)
        // A folder named like a work folder, but holding only photos.
        try write("Developer/screenshot.png", megabytes: 9, in: home)

        let scanner = DiskScanner(
            configuration: ScanConfiguration(homeURL: home, extraRoots: [], maxConcurrentRoots: 2)
        )
        let snapshot = try await scanner.scan()
        let homeRoot = try XCTUnwrap(snapshot.homeRoot)

        let archive = try XCTUnwrap(homeRoot.children["Archive"])
        XCTAssertEqual(archive.displayCategory, .video, "A folder should be coloured by its contents")

        // A folder called "Developer" is source code by convention, and that
        // convention is a stronger signal than the extension of what is inside.
        let developer = try XCTUnwrap(homeRoot.children["Developer"])
        XCTAssertEqual(developer.displayCategory, .developer)
    }

    func testLibraryIsColouredByItsContentsNotItsPath() async throws {
        let home = fixture!
        try write("Library/Caches/App/blob.bin", megabytes: 7, in: home)
        try write("Library/Logs/App/app.log", megabytes: 0.5, in: home)

        let scanner = DiskScanner(
            configuration: ScanConfiguration(homeURL: home, extraRoots: [], maxConcurrentRoots: 1)
        )
        let snapshot = try await scanner.scan()
        let library = try XCTUnwrap(snapshot.homeRoot?.children["Library"])

        // `~/Library` is not a kind of content, so it takes the colour of
        // whatever dominates it.
        XCTAssertEqual(library.displayCategory, .caches)
        XCTAssertEqual(library.dominantCategory, .caches)
        XCTAssertGreaterThan(library.subtreeTotals[SpaceCategory.caches.slot], 0)
    }

    func testSubtreeTotalsTrackTheWholeFolder() async throws {
        let home = fixture!
        try write("Pictures/a.jpg", megabytes: 3, in: home)
        try write("Pictures/nested/b.jpg", megabytes: 4, in: home)

        let scanner = DiskScanner(
            configuration: ScanConfiguration(homeURL: home, extraRoots: [], maxConcurrentRoots: 1)
        )
        let snapshot = try await scanner.scan()
        let pictures = try XCTUnwrap(snapshot.homeRoot?.children["Pictures"])

        let photoBytes = pictures.subtreeTotals[SpaceCategory.photos.slot]
        XCTAssertEqual(photoBytes, pictures.size, accuracy: 1)
        XCTAssertEqual(pictures.displayCategory, .photos)
    }

    func testTopLevelFileKeepsItsOwnCategory() async throws {
        let home = fixture!
        try write("Timeline 1.mov", megabytes: 6, in: home)
        try write("Documents/notes.txt", megabytes: 0.5, in: home)

        let scanner = DiskScanner(
            configuration: ScanConfiguration(homeURL: home, extraRoots: [], maxConcurrentRoots: 1)
        )
        let snapshot = try await scanner.scan()
        let homeRoot = try XCTUnwrap(snapshot.homeRoot)

        // A file sitting at the top of the home folder is a node in the tree
        // like any other, so it has to be coloured by what it is.
        let movie = try XCTUnwrap(homeRoot.children["Timeline 1.mov"])
        XCTAssertEqual(movie.displayCategory, .video)
        XCTAssertEqual(movie.dominantCategory, .video)
        XCTAssertEqual(movie.subtreeTotals[SpaceCategory.video.slot], movie.size)
    }

    func testDeletingUpdatesTheFolderColour() async throws {
        let home = fixture!
        try write("Downloads/clip.mov", megabytes: 10, in: home)
        try write("Downloads/notes.txt", megabytes: 0.5, in: home)

        let scanner = DiskScanner(
            configuration: ScanConfiguration(homeURL: home, extraRoots: [], maxConcurrentRoots: 1)
        )
        var snapshot = try await scanner.scan()
        let downloads = try XCTUnwrap(snapshot.homeRoot?.children["Downloads"])
        // The folder's colour agrees with the breakdown: it is full of video,
        // so it is video — not "downloads" just because of where it sits.
        XCTAssertEqual(downloads.displayCategory, .video)

        // Deleting the video should leave the folder coloured by what is left.
        // The size has to be the file's allocated size, which is what the scanner
        // recorded, or the totals would be left slightly out.
        let clipURL = URL(fileURLWithPath: downloads.path + "/clip.mov")
        let (clipSize, _) = JunkRules.allocatedSize(of: clipURL)
        let clip = CleanupItem(
            url: clipURL,
            detail: "~/Downloads",
            size: clipSize,
            safety: .review,
            category: .video,
            isDirectory: false
        )
        snapshot.applyDeletion(of: [clip])

        let after = try XCTUnwrap(snapshot.homeRoot?.children["Downloads"])
        XCTAssertEqual(after.displayCategory, .documents, "The folder should change colour once the video is gone")
        XCTAssertEqual(after.subtreeTotals[SpaceCategory.video.slot], 0)
    }

    private func write(_ relativePath: String, megabytes: Double, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x42, count: Int(megabytes * 1_000_000)).write(to: url)
    }
}

final class DeletionServiceTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpaceCrunchDeletion-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixture {
            try? FileManager.default.removeItem(at: fixture)
        }
    }

    func testItemsAlreadyInTrashAreRemovedPermanently() async throws {
        let home = fixture!
        let trash = home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let file = trash.appendingPathComponent("old.bin")
        try Data(repeating: 0x01, count: 2_000).write(to: file)

        let item = CleanupItem(
            url: file,
            detail: "~/.Trash",
            size: 2_000,
            safety: .review,
            category: .other,
            isDirectory: false
        )

        let report = await DeletionService.delete(items: [item], home: home)

        XCTAssertTrue(report.everythingSucceeded)
        XCTAssertEqual(report.removedCount, 1)
        XCTAssertEqual(report.bytesFreed, 2_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
