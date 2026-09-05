import Foundation
import VigilShared

final class PrivilegedDaemonClient {
    private var connection: NSXPCConnection?
    private let requestTimeout: TimeInterval = 5

    func ensurePolicyApplied(completion: @escaping (Result<Void, Error>) -> Void) {
        withProxy(timeoutMessage: "The daemon did not respond.") { proxy, finish in
            proxy.ensurePolicyApplied { success, message in
                if success {
                    finish(.success(()))
                } else {
                    finish(.failure(DaemonError(message ?? "The daemon could not apply the sleep policy.")))
                }
            }
        } completion: { (result: Result<Void, Error>) in
            completion(result)
        }
    }

    func getPolicyStatus(completion: @escaping (Result<Bool, Error>) -> Void) {
        withProxy(timeoutMessage: "The daemon did not respond.") { proxy, finish in
            proxy.getPolicyStatus { success, enabled, message in
                if success {
                    finish(.success(enabled))
                } else {
                    finish(.failure(DaemonError(message ?? "The daemon could not read the sleep policy.")))
                }
            }
        } completion: { (result: Result<Bool, Error>) in
            completion(result)
        }
    }

    func disablePolicy(completion: @escaping (Result<Void, Error>) -> Void) {
        withProxy(timeoutMessage: "The daemon did not respond.") { proxy, finish in
            proxy.disablePolicy { success, message in
                if success {
                    finish(.success(()))
                } else {
                    finish(.failure(DaemonError(message ?? "The daemon could not disable the sleep policy.")))
                }
            }
        } completion: { (result: Result<Void, Error>) in
            completion(result)
        }
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    private func withProxy<T>(
        timeoutMessage: String,
        body: @escaping (VigilDaemonProtocol, @escaping (Result<T, Error>) -> Void) -> Void,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        var didComplete = false
        let finish: (Result<T, Error>) -> Void = { result in
            DispatchQueue.main.async {
                guard !didComplete else { return }
                didComplete = true
                completion(result)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + requestTimeout) { [weak self] in
            guard !didComplete else { return }
            self?.invalidate()
            finish(.failure(DaemonError(timeoutMessage)))
        }

        remoteProxy { proxyResult in
            switch proxyResult {
            case .failure(let error):
                finish(.failure(error))
            case .success(let proxy):
                body(proxy, finish)
            }
        }
    }

    private func remoteProxy(
        completion: @escaping (Result<VigilDaemonProtocol, Error>) -> Void
    ) {
        let connection = self.connection ?? makeConnection()
        self.connection = connection

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            DispatchQueue.main.async {
                self.invalidate()
                completion(.failure(error))
            }
        }

        guard let typedProxy = proxy as? VigilDaemonProtocol else {
            completion(.failure(DaemonError("Could not create the daemon XPC proxy.")))
            return
        }

        completion(.success(typedProxy))
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: VigilConstants.daemonMachServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: VigilDaemonProtocol.self)
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.connection = nil
            }
        }
        connection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.connection = nil
            }
        }
        connection.resume()
        return connection
    }

    struct DaemonError: LocalizedError {
        let message: String

        init(_ message: String) {
            self.message = message
        }

        var errorDescription: String? { message }
    }
}
