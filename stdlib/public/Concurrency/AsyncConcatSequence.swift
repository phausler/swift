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
  public func append<Suffix>(_ suffix: Suffix) -> AsyncConcatSequence<Self, Suffix> where Suffix: AsyncSequence, Suffix.Element == Element {
    return AsyncConcatSequence(prefix: self, suffix: suffix)
  }
  
  public func prepend<Prefix>(_ prefix: Prefix) -> AsyncConcatSequence<Prefix, Self> where Prefix: AsyncSequence, Prefix.Element == Element {
    return AsyncConcatSequence(prefix: prefix, suffix: self)
  }
}

public struct AsyncConcatSequence<Prefix, Suffix>: AsyncSequence where Prefix: AsyncSequence, Suffix: AsyncSequence, Prefix.Element == Suffix.Element {
  public typealias Element = Prefix.Element
  public typealias AsyncIterator = Iterator
  
  public struct Iterator: AsyncIteratorProtocol {
    var prefixIterator: _OptionalAsyncIterator<Prefix.AsyncIterator>
    var suffixIterator: _OptionalAsyncIterator<Suffix.AsyncIterator>
    
    init(_ prefixIterator: Prefix.AsyncIterator, _ suffixIterator: Suffix.AsyncIterator) {
      self.prefixIterator = _OptionalAsyncIterator(prefixIterator)
      self.suffixIterator = _OptionalAsyncIterator(suffixIterator)
    }
    
    public mutating func next() async rethrows -> Prefix.Element? {
      if let item = try await prefixIterator.next() {
        return item
      }
      prefixIterator = .none
      return try await suffixIterator.next()
    }
    
    public mutating func cancel() {
      prefixIterator.cancel()
      suffixIterator.cancel()
    }
  }
  
  public let prefix: Prefix
  public let suffix: Suffix
  
  public init(prefix: Prefix, suffix: Suffix) {
    self.prefix = prefix
    self.suffix = suffix
  }
  
  public func makeAsyncIterator() -> Iterator {
    return Iterator(prefix.makeAsyncIterator(), suffix.makeAsyncIterator())
  }
}
