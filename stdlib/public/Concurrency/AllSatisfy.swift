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
  public func allSatisfy(_ predicate: (Element) async throws -> Bool) async rethrows -> Bool {
    var it = makeAsyncIterator()
    while let element = try await it.next() {
      if !(try await predicate(element)) {
        return false
      }
    }
    return true
  }
}
