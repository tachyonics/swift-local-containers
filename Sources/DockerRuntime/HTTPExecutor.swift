import AsyncHTTPClient
import Logging
import NIOCore

package protocol HTTPExecutor: Sendable {
    func execute(
        _ request: HTTPClientRequest,
        timeout: TimeAmount,
        logger: Logger?
    ) async throws -> HTTPClientResponse
}

// HTTPClient already has this exact signature with `logger: Logger? = nil`
extension HTTPClient: HTTPExecutor {}
