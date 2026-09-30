import Testing
import Foundation
@testable import MacMirror

@Suite("WhatsNewCatalog Tests")
struct WhatsNewCatalogTests {

    @Test("Catalog provides highlights for supported versions")
    func testCatalogHasHighlights() {
        #expect(WhatsNewCatalog.hasHighlights(for: "1.2"))
        #expect(WhatsNewCatalog.hasHighlights(for: "1.2.0"))
        #expect(WhatsNewCatalog.hasHighlights(for: "1.2-beta.1"))

        let release = WhatsNewCatalog.highlights(for: "1.2.0")
        #expect(release != nil)
        #expect(release?.items.isEmpty == false)

        let items = release?.items ?? []
        for item in items {
            #expect(!item.id.isEmpty)
            #expect(!item.iconName.isEmpty)
            #expect(!item.titleKey.isEmpty)
            #expect(!item.descriptionKey.isEmpty)
        }

        #expect(!WhatsNewCatalog.hasHighlights(for: "1.1.0"))
        #expect(!WhatsNewCatalog.hasHighlights(for: "2.0.0"))
        #expect(WhatsNewCatalog.highlights(for: "2.0.0") == nil)
        #expect(WhatsNewCatalog.latestRelease?.version == "1.2")
    }
}
