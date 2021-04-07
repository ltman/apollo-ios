import Foundation
import Dispatch

/// A cache policy that specifies whether results should be fetched from the server or loaded from the local cache.
public enum CachePolicy {
  /// Return data from the cache if available, else fetch results from the server.
  case returnCacheDataElseFetch
  ///  Always fetch results from the server.
  case fetchIgnoringCacheData
  ///  Always fetch results from the server, and don't store these in the cache.
  case fetchIgnoringCacheCompletely
  /// Return data from the cache if available, else return nil.
  case returnCacheDataDontFetch
  /// Return data from the cache if available, and always fetch results from the server.
  case returnCacheDataAndFetch
  
  /// The current default cache policy.
  public static var `default`: CachePolicy {
    .returnCacheDataElseFetch
  }
}

/// A handler for operation results.
///
/// - Parameters:
///   - result: The result of a performed operation. Will have a `GraphQLResult` with any parsed data and any GraphQL errors on `success`, and an `Error` on `failure`.
public typealias GraphQLResultHandler<Data> = (Result<GraphQLResult<Data>, Error>) -> Void

/// The `ApolloClient` class implements the core API for Apollo by conforming to `ApolloClientProtocol`.
public class ApolloClient {

  let networkTransport: NetworkTransport

  public let store: ApolloStore // <- conformance to ApolloClientProtocol

  public enum ApolloClientError: Error, LocalizedError {
    case noUploadTransport

    public var errorDescription: String? {
      switch self {
      case .noUploadTransport:
        return "Attempting to upload using a transport which does not support uploads. This is a developer error."
      }
    }
  }

  /// Creates a client with the specified network transport and store.
  ///
  /// - Parameters:
  ///   - networkTransport: A network transport used to send operations to a server.
  ///   - store: A store used as a local cache. Note that if the `NetworkTransport` or any of its dependencies takes a store, you should make sure the same store is passed here so that it can be cleared properly.
  public init(networkTransport: NetworkTransport, store: ApolloStore) {
    self.networkTransport = networkTransport
    self.store = store
  }

  /// Creates a client with a `RequestChainNetworkTransport` connecting to the specified URL.
  ///
  /// - Parameter url: The URL of a GraphQL server to connect to.
  public convenience init(url: URL) {
    let store = ApolloStore(cache: InMemoryNormalizedCache())
    let provider = LegacyInterceptorProvider(store: store)
    let transport = RequestChainNetworkTransport(interceptorProvider: provider,
                                                 endpointURL: url)
    
    self.init(networkTransport: transport, store: store)
  }
}

// MARK: - ApolloClientProtocol conformance

extension ApolloClient: ApolloClientProtocol {

  public var cacheKeyForObject: CacheKeyForObject? {
    get {
      return self.store.cacheKeyForObject
    }
    set {
      self.store.cacheKeyForObject = newValue
    }
  }

  public func clearCache(callbackQueue: DispatchQueue = .main,
                         completion: ((Result<Void, Error>) -> Void)? = nil) {
    self.store.clearCache(completion: completion)
  }
  
  @discardableResult public func fetch<Query: GraphQLQuery>(query: Query,
                                                            cachePolicy: CachePolicy = .returnCacheDataElseFetch,
                                                            contextIdentifier: UUID? = nil,
                                                            queue: DispatchQueue = DispatchQueue.main,
                                                            resultHandler: GraphQLResultHandler<Query.Data>? = nil) -> Cancellable {
    return self.networkTransport.send(operation: query,
                                      cachePolicy: cachePolicy,
                                      contextIdentifier: contextIdentifier,
                                      callbackQueue: queue) { result in
      resultHandler?(result)
    }
  }

  public func watch<Query: GraphQLQuery>(query: Query,
                                         cachePolicy: CachePolicy = .returnCacheDataElseFetch,
                                         resultHandler: @escaping GraphQLResultHandler<Query.Data>) -> GraphQLQueryWatcher<Query> {
    let watcher = GraphQLQueryWatcher(client: self,
                                      query: query,
                                      resultHandler: resultHandler)
    watcher.fetch(cachePolicy: cachePolicy)
    return watcher
  }

  @discardableResult
  public func perform<Mutation: GraphQLMutation>(mutation: Mutation,
                                                 publishResultToStore: Bool = true,
                                                 queue: DispatchQueue = .main,
                                                 resultHandler: GraphQLResultHandler<Mutation.Data>? = nil) -> Cancellable {
    return self.networkTransport.send(
      operation: mutation,
      cachePolicy: publishResultToStore ? .default : .fetchIgnoringCacheCompletely,
      contextIdentifier: nil,
      callbackQueue: queue,
      completionHandler: { result in
        resultHandler?(result)
      }
    )
  }

  @discardableResult
  public func upload<Operation: GraphQLOperation>(operation: Operation,
                                                  files: [GraphQLFile],
                                                  queue: DispatchQueue = .main,
                                                  resultHandler: GraphQLResultHandler<Operation.Data>? = nil) -> Cancellable {
    guard let uploadingTransport = self.networkTransport as? UploadingNetworkTransport else {
      assertionFailure("Trying to upload without an uploading transport. Please make sure your network transport conforms to `UploadingNetworkTransport`.")
      queue.async {
        resultHandler?(.failure(ApolloClientError.noUploadTransport))
      }
      return EmptyCancellable()
    }

    return uploadingTransport.upload(operation: operation,
                                     files: files,
                                     callbackQueue: queue) { result in
      resultHandler?(result)
    }
  }
  
  @discardableResult
  public func subscribe<Subscription: GraphQLSubscription>(subscription: Subscription,
                                                           queue: DispatchQueue = .main,
                                                           resultHandler: @escaping GraphQLResultHandler<Subscription.Data>) -> Cancellable {
    return self.networkTransport.send(operation: subscription,
                                      cachePolicy: .default,
                                      contextIdentifier: nil,
                                      callbackQueue: queue,
                                      completionHandler: resultHandler)
  }
}

public extension ApolloClient {
  @discardableResult
  func fetch<Query: GraphQLQuery>(
    query: Query,
    cachePolicy: CachePolicy,
    contextIdentifier: UUID?,
    queue: DispatchQueue,
    additionalHeaders: [String: String] = [:],
    resultHandler: GraphQLResultHandler<Query.Data>?) -> Cancellable
  {
    if let networkTransport = self.networkTransport as? RequestChainNetworkTransport {
      return networkTransport.send(operation: query,
                                   additionalHeaders: additionalHeaders,
                                   cachePolicy: cachePolicy,
                                   contextIdentifier: contextIdentifier,
                                   callbackQueue: queue) { result in
        resultHandler?(result)
      }
    }
    
    return self.networkTransport.send(operation: query,
                                      cachePolicy: cachePolicy,
                                      contextIdentifier: contextIdentifier,
                                      callbackQueue: queue) { result in
      resultHandler?(result)
    }
  }
  
  @discardableResult
  func perform<Mutation: GraphQLMutation>(
    mutation: Mutation,
    publishResultToStore: Bool = true,
    queue: DispatchQueue = .main,
    additionalHeaders: [String: String] = [:],
    resultHandler: GraphQLResultHandler<Mutation.Data>? = nil) -> Cancellable
  {
    if let networkTransport = self.networkTransport as? RequestChainNetworkTransport {
      return networkTransport.send(
        operation: mutation,
        additionalHeaders: additionalHeaders,
        cachePolicy: publishResultToStore ? .default : .fetchIgnoringCacheCompletely,
        contextIdentifier: nil,
        callbackQueue: queue,
        completionHandler: { result in
          resultHandler?(result)
        }
      )
    }
    
    return self.networkTransport.send(
      operation: mutation,
      cachePolicy: publishResultToStore ? .default : .fetchIgnoringCacheCompletely,
      contextIdentifier: nil,
      callbackQueue: queue,
      completionHandler: { result in
        resultHandler?(result)
      }
    )
  }
  
  func watch<Query: GraphQLQuery>(
    query: Query,
    cachePolicy: CachePolicy = .returnCacheDataElseFetch,
    additionalHeaders: [String: String] = [:],
    resultHandler: @escaping GraphQLResultHandler<Query.Data>) -> BditQueryWatcher<Query>
  {
    let watcher = BditQueryWatcher(
      client: self,
      query: query,
      additionalHeaders: additionalHeaders,
      resultHandler: resultHandler
    )
    watcher.fetch(cachePolicy: cachePolicy)
    return watcher
  }
}

extension RequestChainNetworkTransport {
  func send<Operation: GraphQLOperation>(
    operation: Operation,
    additionalHeaders: [String: String] = [:],
    cachePolicy: CachePolicy = .default,
    contextIdentifier: UUID? = nil,
    callbackQueue: DispatchQueue = .main,
    completionHandler: @escaping (Result<GraphQLResult<Operation.Data>, Error>) -> Void) -> Cancellable {
    
    let interceptors = self.interceptorProvider.interceptors(for: operation)
    let chain = RequestChain(interceptors: interceptors, callbackQueue: callbackQueue)
    chain.additionalErrorHandler = self.interceptorProvider.additionalErrorInterceptor(for: operation)
    let request = self.constructRequest(for: operation,
                                        cachePolicy: cachePolicy,
                                        contextIdentifier: contextIdentifier)
    
    additionalHeaders.forEach { (key, value) in
      request.addHeader(name: key, value: value)
    }
    
    chain.kickoff(request: request, completion: completionHandler)
    return chain
  }
  
}







