import Foundation

/// Settings > About > Trademarks and Attributions (docs/NAMES.md section 3, which cites each owner's page). Text only:
/// no logo of any company is shown anywhere in the app.
///
/// Wording rule: where an owner publishes its own notice, the line follows that notice (Dolby's site footer, Xperi's media
/// kit, Apple's "Guidelines for Using Apple Trademarks", HDMI Licensing Administrator's brand page, Microsoft's general
/// trademark guidelines); every other name is covered by the closing "respective owners" sentence. The data-provider
/// notices (TMDB, JustWatch) are the App's `Attribution` constants and are shown in the same screen.
/// PROVISIONAL: Dolby's footer lists Dolby, the double-D symbol, Dolby Atmos and Dolby Vision; Dolby Digital, Dolby Digital
/// Plus and Dolby TrueHD were added to the same sentence because the app names them (alternative: move them to the
/// "respective owners" sentence). Xperi's notice names DTS only; DTS-HD, DTS-HD Master Audio, DTS-HD High Resolution Audio
/// and DTS:X were added the same way.
public enum TrademarkNotices {
    public static let heading = "Trademarks and Attributions"

    /// The plain "not affiliated" sentence (rule 3b) and what naming a format means (rule 4).
    public static let notAffiliated = "This app is not affiliated with, endorsed by, sponsored by or certified by any company, project or service named in it. Names of formats, servers and services are used only to say what a file contains or what the app connects to; naming a format does not mean that this app or your equipment is certified for it."

    public static let dolby = "Dolby, Dolby Vision, Dolby Atmos, Dolby Digital, Dolby Digital Plus, Dolby TrueHD and the double-D symbol are trademarks or registered trademarks of Dolby Laboratories Licensing Corporation or its affiliates."

    public static let dts = "DTS, DTS-HD, DTS-HD Master Audio, DTS-HD High Resolution Audio and DTS:X are trademarks or registered trademarks of Xperi Inc. or its subsidiaries in the United States and other countries."

    /// Apple's form for materials distributed outside the U.S. (no trademark symbols).
    public static let apple = "Apple, Apple TV, AirPlay, HomePod, iCloud, iCloud Drive, Siri and Siri Remote are trademarks of Apple Inc., registered in the U.S. and other countries and regions."

    public static let hdmi = "The terms HDMI, HDMI High-Definition Multimedia Interface, HDMI Trade Dress and the HDMI Logos are trademarks or registered trademarks of HDMI Licensing Administrator, Inc."

    public static let microsoft = "Microsoft, OneDrive and Windows are trademarks of the Microsoft group of companies."

    public static let others = "HDR10+, AV1, Plex, Jellyfin, Emby, Dropbox, Google Drive, Google Docs, TMDB, OMDb, IMDb, Rotten Tomatoes, Metacritic, JustWatch, Bluetooth, Opus, Vorbis, FLAC and all other names mentioned are trademarks or names of their respective owners."

    /// In display order.
    public static let lines: [String] = [notAffiliated, dolby, dts, apple, hdmi, microsoft, others]
}

/// One open-source library linked into the app, as the licence notice shows it.
public struct LicenseNotice: Equatable, Sendable, Identifiable {
    public var name: String
    public var license: String
    public var copyright: String
    public var use: String
    public var id: String { name }
}

/// One LGPL library covered by the written source offer: its exact version and where its upstream source is.
public struct SourceLink: Equatable, Sendable, Identifiable {
    public var library: String
    public var upstream: String
    public var id: String { library }
}

/// One full licence or notice text bundled in the app (App/Licenses/<fileName>.txt).
public struct BundledLicenseText: Equatable, Sendable, Identifiable {
    public var title: String
    public var fileName: String
    public var id: String { fileName }
}

/// The open-source licence notices (rule 3d). PROVISIONAL: the list is read from Package.swift, the vendored packages'
/// LICENSE files and Packages/VideoPlayerCore/Frameworks (MediaCodecs/LICENSES/README.md, DolbyVisionRPULib-LICENSE.txt)
/// on 2026-11-17; nothing has been archived yet, so the first archive's linked-library list must be compared with it.
/// The full licence texts are bundled in App/Licenses (OPEN_QUESTIONS R149) and shown by "Full Licence Texts".
public enum LicenseNotices {
    public static let heading = "Open-Source Licences"
    public static let intro = "This app includes the following open-source software, each under its own licence. The full licence texts are in Full Licence Texts, on the About page."

    /// The public repository that holds this app's source, the build scripts and the patches. It is the address the
    /// runbook creates (docs/GITHUB_ACTIONS_RUNBOOK.md); it does not exist until the first push.
    public static let repositoryURL = "https://github.com/liampmcdowell7-rgb/video-player"

    /// Written offer under LGPL-2.1 section 6(c) (OPEN_QUESTIONS R149, PROVISIONAL; docs/NAMES.md section 4a).
    public static let sourceOffer = "Written offer for source code: some libraries in this app are licensed under the GNU Lesser General Public License, version 2.1 or later (LGPL). For at least three years from the day you received this app, anyone who has it may get the complete corresponding source code of each of these libraries, together with the build scripts and patches used to build them, at no charge other than the cost of physically delivering a copy. Everything is published in this app’s public source repository, listed below with each library’s exact version and upstream source. This app’s own source is in the same repository, so you can change these libraries and rebuild the app with your changes."

    public static let repositoryLine = "Source code, build scripts and patches: \(repositoryURL)"

    /// Exact versions, read from Frameworks/MediaCodecs/upstream-build-record/BUILD-INFO.txt, Vendor/AMSMB2/VENDORED_FROM.txt
    /// (libsmb2 commit from AMSMB2 tag 4.0.3's submodule pointer, GitHub API 2026-11-17) and docs/SOURCES.md (libnfs).
    public static let sourceLinks: [SourceLink] = [
        SourceLink(library: "FFmpeg 8.1.3 (libavcodec, libavutil, libswresample), with the FFmpegBuild 3.15.0 patches",
                   upstream: "https://github.com/FFmpeg/FFmpeg/tree/1041abdc962f4cc4f394aa8de9dc5236c0c3b9e7 (tag n8.1.3) and https://github.com/superuser404notfound/FFmpegBuild/tree/3.15.0"),
        SourceLink(library: "libzvbi 0.2.46, with the FFmpegBuild 3.15.0 build changes",
                   upstream: "https://github.com/zapping-vbi/zvbi/tree/34bb6f660c5c1bacd4a66cc7b22311e4ca3c1ab5 (tag v0.2.46)"),
        SourceLink(library: "libnfs 5.0.2",
                   upstream: "https://github.com/sahlberg/libnfs/tree/465a12d45703d4c8b1ba534323f911cf28b71501"),
        SourceLink(library: "libsmb2 (the version included in AMSMB2 4.0.3)",
                   upstream: "https://github.com/sahlberg/libsmb2/tree/aff9fa6ba9f41cfd3c15d184554601ec3f6d8d03"),
        SourceLink(library: "AMSMB2 4.0.3, with this app’s Swift 6.4 patch",
                   upstream: "https://github.com/amosavian/AMSMB2/tree/4942c3b336dc6cc5ae93a60a65961a66535e482a (tag 4.0.3)"),
    ]

    /// The bundled texts, in display order. Each file is in App/Licenses and copied into the app as a resource.
    public static let texts: [BundledLicenseText] = [
        BundledLicenseText(title: "GNU Lesser General Public License 2.1 (FFmpeg, libzvbi, libnfs, libsmb2)", fileName: "License-LGPL-2.1"),
        BundledLicenseText(title: "AMSMB2 licence", fileName: "License-AMSMB2"),
        BundledLicenseText(title: "libsmb2 licence notes", fileName: "License-libsmb2"),
        BundledLicenseText(title: "dav1d (BSD-2-Clause)", fileName: "License-dav1d-BSD-2-Clause"),
        BundledLicenseText(title: "libzvbi ure.c (MIT)", fileName: "License-libzvbi-ure-MIT"),
        BundledLicenseText(title: "libdovi (MIT)", fileName: "License-libdovi-MIT"),
        BundledLicenseText(title: "Citadel (MIT)", fileName: "License-Citadel-MIT"),
        BundledLicenseText(title: "Apache License 2.0 (SwiftNIO, SwiftNIO SSH, Swift Crypto)", fileName: "License-Apache-2.0"),
        BundledLicenseText(title: "SwiftNIO notice", fileName: "Notice-SwiftNIO"),
        BundledLicenseText(title: "Swift Crypto notice", fileName: "Notice-SwiftCrypto"),
    ]

    public static let all: [LicenseNotice] = [
        LicenseNotice(name: "FFmpeg (libavcodec, libavutil, libswresample)", license: "LGPL-2.1-or-later",
                      copyright: "Copyright the FFmpeg developers", use: "Audio decoding"),
        LicenseNotice(name: "dav1d", license: "BSD-2-Clause",
                      copyright: "Copyright © 2018-2019, VideoLAN and dav1d authors", use: "AV1 decoding inside the FFmpeg build"),
        LicenseNotice(name: "libzvbi", license: "LGPL-2.0-or-later (used under LGPL-2.1); ure.c under MIT",
                      copyright: "Copyright the libzvbi authors", use: "Teletext subtitles inside the FFmpeg build"),
        LicenseNotice(name: "libdovi", license: "MIT", copyright: "Copyright (c) 2025 quietvoid",
                      use: "Dolby Vision metadata conversion"),
        LicenseNotice(name: "libnfs", license: "LGPL-2.1-or-later", copyright: "Copyright the libnfs authors", use: "NFS sources"),
        LicenseNotice(name: "AMSMB2 and libsmb2", license: "LGPL-2.1", copyright: "Copyright the AMSMB2 and libsmb2 authors", use: "SMB sources"),
        LicenseNotice(name: "Citadel", license: "MIT", copyright: "Copyright (c) 2022 Orlandos", use: "SFTP sources"),
        LicenseNotice(name: "SwiftNIO SSH, SwiftNIO and Swift Crypto", license: "Apache-2.0",
                      copyright: "Copyright Apple Inc. and the SwiftNIO project authors", use: "SFTP connections"),
    ]
}
