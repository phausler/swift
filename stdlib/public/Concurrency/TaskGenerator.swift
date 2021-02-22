//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//


import Swift
@_implementationOnly import _SwiftConcurrencyShims

@_silgen_name("swift_task_generator_yield")
internal func _taskGeneratorResume<T>(
  _ task: Builtin.NativeObject,
  yielding value: T?
)

@_silgen_name("swift_task_generator_resume_throwing")
internal func _taskGeneratorResume<T>(
  _ task: Builtin.NativeObject,
  throwing: Error, 
  _ type: T.Type
)

extension Task {
  public struct Generator<T> {
    private let task: Builtin.NativeObject

    init(_ task: Builtin.NativeObject) {
      self.task = task
      _swiftRetain(task)
    }

    public func next() async throws -> T? {
      let rawResult = await _taskGroupWaitNext(on: self.task)

      if rawResult.hadErrorResult {
        let error = unsafeBitCast(rawResult.storage, to: Error.self)
        throw error
      }

      guard let storage = rawResult.storage else {
        return nil
      }

      let storagePtr =
        storage.bindMemory(to: T.self, capacity: 1)
      let value = UnsafeMutablePointer<T>(mutating: storagePtr).pointee
      return value
    }

    public struct Continuation {
      final class Referent { }
      private let task: Builtin.NativeObject
      var referent = Referent()

      init(_ task: Builtin.NativeObject) {
        self.task = task
        _swiftRetain(task)
      }

      public func resume(yielding value: T?) {
      	_taskGeneratorResume(task, yielding: value)
        _fixLifetime(value)
      }

      public func resume(throwing error: Error) {
      	_taskGeneratorResume(task, throwing: error, T.self)
        _fixLifetime(error)
      }
    }
  }

  public static func generator<T>(
    of: T.Type, 
    _ build: @escaping (Generator<T>.Continuation) async -> Void
  ) async -> Generator<T> {
    let parent = Builtin.getCurrentAsyncTask()

    var flags = JobFlags()
    flags.kind = .task
    flags.isChildTask = true
    flags.isTaskGroup = true
    flags.isFuture = false
    flags.isTaskGenerator = true

    let (generator, _) 
      = Builtin.createAsyncTask(flags.bits, parent) { () async -> Void in
      let task = Builtin.getCurrentAsyncTask()
      var continuation = Generator<T>.Continuation(task)
      await build(continuation)
      if isKnownUniquelyReferenced(&continuation.referent) {
        continuation.resume(yielding: nil)
      }
    }
    _taskGroupAddPendingTask(generator) // allow for the first pending next
    _enqueueJobGlobal(Builtin.convertTaskToJob(generator))
    return Generator(generator)
  }
}