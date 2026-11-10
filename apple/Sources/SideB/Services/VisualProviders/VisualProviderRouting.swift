import Foundation
import SideBCore

/// Apple remains authoritative. Optional providers are fallback only in the vertical sidebar.
enum VisualProviderRouting {
    static func resolve(verticalPlayer: Bool, extensionEnabled: Bool,
                        primary: () async throws -> AnimatedArtworkAsset?,
                        secondary: () async throws -> AnimatedArtworkAsset?) async throws -> AnimatedArtworkAsset? {
        let allowSecondary = verticalPlayer && extensionEnabled
        do {
            if let asset = try await primary() {
                try Task.checkCancellation()
                return asset
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            if !allowSecondary { throw error }
        }
        try Task.checkCancellation()
        guard allowSecondary else { return nil }
        return try await secondary()
    }
}
