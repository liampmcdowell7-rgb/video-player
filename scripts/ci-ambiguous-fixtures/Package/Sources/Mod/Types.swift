// Fixture for scripts/test-ci-ambiguous-types.sh (never compiled).
public struct LibraryItem {}
public final class SharedClass {}
public protocol SharedProto {}
public struct OnlyOurs {}
/// Apple's `Nested` is nested inside another type, so it does not collide.
public struct Nested {}
