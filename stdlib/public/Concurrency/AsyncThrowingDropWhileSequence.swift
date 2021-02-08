//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Swift

extension AsyncSequence {
  @inlinable
  public __consuming func drop(
    while predicate: @escaping (Element) async throws -> Bool
  ) -> AsyncThrowingDropWhileSequence<Self> {
    AsyncThrowingDropWhileSequence(self, predicate: predicate)
  }
}

@frozen
public struct AsyncThrowingDropWhileSequence<Base: AsyncSequence> {
  @usableFromInline
  let base: Base

  @usableFromInline
  let predicate: (Base.Element) async throws -> Bool

  @usableFromInline
  init(
    _ base: Base, 
    predicate: @escaping (Base.Element) async throws -> Bool
  ) {
    self.base = base
    self.predicate = predicate
  }
}

extension AsyncThrowingDropWhileSequence: AsyncSequence {
  public typealias Element = Base.Element
  public typealias AsyncIterator = Iterator

  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    @usableFromInline
    var baseIterator: Base.AsyncIterator

    @usableFromInline
    let predicate: (Base.Element) async throws -> Bool

    @usableFromInline
    var finished = false

    @usableFromInline
    init(
      _ baseIterator: Base.AsyncIterator, 
      predicate: @escaping (Base.Element) async throws -> Bool
    ) {
      self.baseIterator = baseIterator
      self.predicate = predicate
    }

    @inlinable
    public mutating func next() async throws -> Base.Element? {
      while !finished {
        guard let element = try await baseIterator.next() else {
          return nil
        }
        do {
          if try await predicate(element) == false {
            finished = true
            return element
          }
        } catch {
          finished = true
          throw error
        }
      }
      return try await baseIterator.next()
    }
  }

  @inlinable
  public __consuming func makeAsyncIterator() -> Iterator {
    return Iterator(base.makeAsyncIterator(), predicate: predicate)
  }
}
