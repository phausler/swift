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
  public __consuming func compactMap<ElementOfResult>(
    _ transform: @escaping (Element) async throws -> ElementOfResult?
  ) -> AsyncFailableCompactMapSequence<Self, ElementOfResult> {
    return AsyncFailableCompactMapSequence(self, transform: transform)
  }
}

@frozen
public struct AsyncFailableCompactMapSequence<Base: AsyncSequence, ElementOfResult> {
  @usableFromInline
  let base: Base

  @usableFromInline
  let transform: (Base.Element) async throws -> ElementOfResult?

  @usableFromInline
  init(
    _ base: Base, 
    transform: @escaping (Base.Element) async throws -> ElementOfResult?
  ) {
    self.base = base
    self.transform = transform
  }
}

extension AsyncFailableCompactMapSequence: AsyncSequence {
  public typealias Element = ElementOfResult
  public typealias AsyncIterator = Iterator

  @frozen
  public struct Iterator: AsyncIteratorProtocol {
    public typealias Element = ElementOfResult

    @usableFromInline
    var baseIterator: Base.AsyncIterator

    @usableFromInline
    var transform: ((Base.Element) async throws -> ElementOfResult?)?

    @usableFromInline
    init(
      _ baseIterator: Base.AsyncIterator, 
      transform: @escaping (Base.Element) async throws -> ElementOfResult?
    ) {
      self.baseIterator = baseIterator
      self.transform = transform
    }

    @inlinable
    public mutating func next() async throws -> ElementOfResult? {
      guard let transform = self.transform else {
        return nil
      }
      while true {
        guard let element = try await baseIterator.next() else {
          self.transform = nil
          return nil
        }
        do {
          if let transformed = try await transform(element) {
            return transformed
          }
        } catch {
          self.transform = nil
          throw error
        }
      }
    }
  }

  @inlinable
  public __consuming func makeAsyncIterator() -> Iterator {
    return Iterator(base.makeAsyncIterator(), transform: transform)
  }
}
