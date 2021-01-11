////===----------------------------------------------------------------------===//
////
//// This source file is part of the Swift.org open source project
////
//// Copyright (c) 2020 Apple Inc. and the Swift project authors
//// Licensed under Apache License v2.0 with Runtime Library Exception
////
//// See https://swift.org/LICENSE.txt for license information
//// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
////
////===----------------------------------------------------------------------===//

import Swift

extension AsyncSequence {
  public func flatMap<SegmentOfResult>(_ transform: @escaping (Element) async -> SegmentOfResult) -> AsyncFlatMapSequence<Self, SegmentOfResult> where SegmentOfResult: AsyncSequence {
    return AsyncFlatMapSequence(self, transform: transform)
  }
  
  public func flatMap<SegmentOfResult>(_ transform: @escaping (Element) async throws -> SegmentOfResult) -> AsyncTryFlatMapSequence<Self, SegmentOfResult> where SegmentOfResult: AsyncSequence {
    return AsyncTryFlatMapSequence(self, transform: transform)
  }
}

public struct AsyncFlatMapSequence<Upstream, SegmentOfResult: AsyncSequence>: AsyncSequence where Upstream: AsyncSequence {
  public typealias Element = SegmentOfResult.Element
  public typealias AsyncIterator = Iterator
  
  public struct Iterator: AsyncIteratorProtocol {
    var upstreamIterator: _OptionalAsyncIterator<Upstream.AsyncIterator>
    let transform: (Upstream.Element) async -> SegmentOfResult
    var currentIterator: _OptionalAsyncIterator<SegmentOfResult.AsyncIterator> = .none
    
    init(_ upstreamIterator: Upstream.AsyncIterator, transform: @escaping (Upstream.Element) async -> SegmentOfResult) {
      self.upstreamIterator = _OptionalAsyncIterator(upstreamIterator)
      self.transform = transform
    }
    
    public mutating func next() async rethrows -> SegmentOfResult.Element? {
      if let item = try await currentIterator.next() {
        return item
      } else {
        guard let item = try await upstreamIterator.next() else {
          return nil
        }
        let segment = await transform(item)
        currentIterator = _OptionalAsyncIterator(segment.makeAsyncIterator())
        return try await currentIterator.next()
      }
    }
    
    public mutating func cancel() {
      upstreamIterator.cancel()
      currentIterator.cancel()
    }
  }
  
  public let upstream: Upstream
  public let transform: (Upstream.Element) async -> SegmentOfResult
  
  public init(_ upstream: Upstream, transform: @escaping (Upstream.Element) async -> SegmentOfResult) {
    self.upstream = upstream
    self.transform = transform
  }
  
  public func makeAsyncIterator() -> Iterator {
    return Iterator(upstream.makeAsyncIterator(), transform: transform)
  }
}

public struct AsyncTryFlatMapSequence<Upstream, SegmentOfResult: AsyncSequence>: AsyncSequence where Upstream: AsyncSequence {
  public typealias Element = SegmentOfResult.Element
  public typealias AsyncIterator = Iterator
  
  public struct Iterator: AsyncIteratorProtocol {
    var upstreamIterator: _OptionalAsyncIterator<Upstream.AsyncIterator>
    let transform: (Upstream.Element) async throws -> SegmentOfResult
    var currentIterator: _OptionalAsyncIterator<SegmentOfResult.AsyncIterator> = .none
    
    init(_ upstreamIterator: Upstream.AsyncIterator, transform: @escaping (Upstream.Element) async throws -> SegmentOfResult) {
      self.upstreamIterator = _OptionalAsyncIterator(upstreamIterator)
      self.transform = transform
    }
    
    public mutating func next() async throws -> SegmentOfResult.Element? {
      if let item = try await currentIterator.next() {
        return item
      } else {
        guard let item = try await upstreamIterator.next() else {
          return nil
        }
        let segment = try await transform(item)
        currentIterator = _OptionalAsyncIterator(segment.makeAsyncIterator())
        return try await currentIterator.next()
      }
    }
    
    public mutating func cancel() {
      upstreamIterator.cancel()
      currentIterator.cancel()
    }
  }
  
  public let upstream: Upstream
  public let transform: (Upstream.Element) async throws -> SegmentOfResult
  
  public init(_ upstream: Upstream, transform: @escaping (Upstream.Element) async throws -> SegmentOfResult) {
    self.upstream = upstream
    self.transform = transform
  }
  
  public func makeAsyncIterator() -> Iterator {
    return Iterator(upstream.makeAsyncIterator(), transform: transform)
  }
}

