#if DEBUG
import Foundation
import AppLogic
import MetadataOnline

/// R455: the gallery of the screenshot job (`-UITestFixtures`): invented candidates with languages and sizes, no picture and no
/// network (the tiles show their placeholder). Not compiled into Release.
enum UITestFixtureGallery {
    static func gallery(_ kind: ArtworkGalleryKind) -> ArtworkGallery {
        let wide = kind.aspectRatio > 1
        let refs: [ImageRef] = [
            ImageRef(path: "/fixture-a.jpg", width: wide ? 3840 : 2000, height: wide ? 2160 : 3000, language: "en", voteAverage: 5.4),
            ImageRef(path: "/fixture-b.jpg", width: wide ? 1920 : 1000, height: wide ? 1080 : 1500, language: nil, voteAverage: 5.1),
            ImageRef(path: "/fixture-c.jpg", width: wide ? 1920 : 1000, height: wide ? 1080 : 1500, language: "fr", voteAverage: 4.8),
            ImageRef(path: "/fixture-d.jpg", width: wide ? 1280 : 680, height: wide ? 720 : 1000, language: "de", voteAverage: 4.2),
        ]
        return ArtworkGallery(kind: kind, candidates: ArtworkCandidates.sorted(ArtworkCandidates.online(refs), userLanguage: "en"), onlineSwitchOff: false)
    }
}
#endif
