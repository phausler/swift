//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

/// A namespace for observation tracking utilities.
@available(SwiftStdlib 5.9, *)
public struct ObservationTracking: Sendable {
  struct Id {
    var willSet: Int?
    var didSet: Int?
    var `deinit`: Int?
  }

  struct Entry: @unchecked Sendable {
    let context: ObservationRegistrar.Context
    
    var properties: Set<AnyKeyPath>
    
    init(_ context: ObservationRegistrar.Context, properties: Set<AnyKeyPath> = []) {
      self.context = context
      self.properties = properties
    }
    
    func addWillSetObserver(_ changed: @Sendable @escaping (AnyKeyPath) -> Void) -> Int {
      return context.registerTracking(for: properties, willSet: changed)
    }

    func addDidSetObserver(_ changed: @Sendable @escaping (AnyKeyPath) -> Void) -> Int {
      return context.registerTracking(for: properties, didSet: changed)
    }

    func addDeinitObserver(_ changed: @Sendable @escaping () -> Void) -> Int {
      return context.registerTracking(deinit: changed)
    }
    
    func removeObserver(_ token: Int) {
      context.cancel(token)
    }
    
    mutating func insert(_ keyPath: AnyKeyPath) {
      properties.insert(keyPath)
    }
    
    func union(_ entry: Entry) -> Entry {
      return Entry(context, properties: properties.union(entry.properties))
    }
  }
  
  @_spi(SwiftUI)
  public struct _AccessList: Sendable {
    internal var entries = [ObjectIdentifier : Entry]()

    internal init() { }
    
    internal mutating func addAccess<Subject: Observable>(
      keyPath: PartialKeyPath<Subject>,
      context: ObservationRegistrar.Context
    ) {
      entries[context.id, default: Entry(context)].insert(keyPath)
    }
    
    internal mutating func merge(_ other: _AccessList) {
      entries.merge(other.entries) { existing, entry in
        existing.union(entry)
      }
    }
  }

  @available(SwiftStdlib 6.4, *)
  static func _installTracking(
    options: ObservationTracking.Options,
    _ tracking: ObservationTracking,
    willSet: (@Sendable (ObservationTracking) -> Void)? = nil,
    didSet: (@Sendable (ObservationTracking) -> Void)? = nil,
    `deinit`: (@Sendable () -> Void)? = nil
  ) {
    let values = tracking.list.entries.mapValues { 
      var id = Id()
      if let willSet {
        id.willSet = $0.addWillSetObserver { property in
          tracking.state.withCriticalRegion { $0.changed = property }
          willSet(tracking)
        }
      }
      if let didSet {
        id.didSet = $0.addDidSetObserver { property in
          tracking.state.withCriticalRegion { $0.changed = property }
          didSet(tracking)
        }
      }
      if let `deinit` {
        id.deinit = $0.addDeinitObserver(`deinit`)
      }
      return id
    }
    
    tracking.install(values)
  }

  @_spi(SwiftUI)
  public static func _installTracking(
    _ tracking: ObservationTracking,
    willSet: (@Sendable (ObservationTracking) -> Void)? = nil,
    didSet: (@Sendable (ObservationTracking) -> Void)? = nil
  ) {
    let values = tracking.list.entries.mapValues { 
      var id = Id()
      if let willSet {
        id.willSet = $0.addWillSetObserver { property in
          tracking.state.withCriticalRegion { $0.changed = property }
          willSet(tracking)
        }
      }
      if let didSet {
        id.didSet = $0.addDidSetObserver { property in
          tracking.state.withCriticalRegion { $0.changed = property }
          didSet(tracking)
        }
      }
      return id
    }
    
    tracking.install(values)
  }

  @_spi(SwiftUI)
  public static func _installTracking(
    _ list: _AccessList,
    onChange: @escaping @Sendable () -> Void
  ) {
    let tracking = ObservationTracking(list)
    _installTracking(tracking, willSet: { _ in
      onChange()
      tracking.cancel()
    })
  }

  struct State: @unchecked Sendable {
    var values = [ObjectIdentifier: ObservationTracking.Id]()
    var cancelled = false
    var changed: AnyKeyPath?
  }
  
  private let state = _ManagedCriticalState(State())
  private let list: _AccessList
  
  @_spi(SwiftUI)
  public init(_ list: _AccessList?) {
    self.init(list, changed: nil)
  }

  init(_ list: _AccessList?, changed: AnyKeyPath?) {
    self.list = list ?? _AccessList()
    if let changed {
      state.withCriticalRegion { $0.changed = changed }
    }
  }

  var isCancelled: Bool {
    state.withCriticalRegion { $0.cancelled }
  }

  internal func install(_ values:  [ObjectIdentifier : ObservationTracking.Id]) {
    state.withCriticalRegion {
      if !$0.cancelled {
        $0.values = values
      }
    }
  }

  @_spi(SwiftUI)
  public func cancel() {
    let values = state.withCriticalRegion {
      $0.cancelled = true
      let values = $0.values
      $0.values = [:]
      return values
    }
    for (id, observationId) in values {
        if let token = observationId.willSet {
          list.entries[id]?.removeObserver(token)
        }
        if let token = observationId.didSet {
          list.entries[id]?.removeObserver(token)
        }
        if let token = observationId.deinit {
          list.entries[id]?.removeObserver(token)
        }
      }
  }

  @available(SwiftStdlib 6.0, *)
  @_spi(SwiftUI)
  public var changed: AnyKeyPath? {
      state.withCriticalRegion { $0.changed }
  }

  static func deactivateAccessList(_ ptr: UnsafeMutablePointer<_AccessList?>) -> ObservationRegistrar.Dirty? {
    var found: ObservationRegistrar.Dirty? = nil
    if let entries = ptr.pointee?.entries.values {
      for entry in entries {
        let dirty = entry.context.clearDirty(ptr)
        if found == nil {
          found = dirty
        }
      }
    }
    return found
  }

  /// Options for configuring observation tracking behavior.
  ///
  /// Use `Options` to specify when to receive change notifications and what types of
  /// events to observe. You can specify multiple options using array literal syntax
  /// or set algebra operations.
  ///
  /// ## Examples
  ///
  /// Observe property changes before they occur:
  ///
  /// ```swift
  /// withObservationTracking(options: .willSet) {
  ///     print(model.value)
  /// } onChange: { event in
  ///     // Called before the property actually changes
  ///     print("About to change")
  /// }
  /// ```
  ///
  /// Observe either changes or deinitialization:
  ///
  /// ```swift
  /// withObservationTracking(options: [.willSet, .deinit]) {
  ///     print(model.value)
  /// } onChange: { event in
  ///     if event.kind == .willSet {
  ///         print("Value changing")
  ///     } else if event.kind == .deinit {
  ///         print("Model deallocated")
  ///     }
  /// }
  /// ```
  @available(SwiftStdlib 6.4, *)
  public struct Options {
    struct RawValue: OptionSet {
      var rawValue: Int

      init(rawValue: Int) {
        self.rawValue = rawValue
      }

      static var willSet: RawValue { .init(rawValue: 1 << 0) }
      static var didSet: RawValue { .init(rawValue: 1 << 1) }
      static var `deinit`: RawValue { .init(rawValue: 1 << 2) }
      static var continuous: RawValue { .init(rawValue: 1 << 3) }
      static var updating: RawValue { .init(rawValue: 1 << 4) }
    }
    var rawValue: RawValue

    init(rawValue: RawValue) {
      self.rawValue = rawValue
    }

    @available(SwiftStdlib 6.4, *)
    public init() { 
      rawValue = RawValue()
    }

    /// Receive notifications before an accessed property of an observable
    /// type changes.
    @available(SwiftStdlib 6.4, *)
    public static var willSet: Options { Options(rawValue: .willSet) }

    /// Receive notifications after an accessed property of an observable type
    /// changes.
    @available(SwiftStdlib 6.4, *)
    public static var didSet: Options { Options(rawValue: .didSet) }
    
    /// Receive notifications when an accessed observable object is
    /// deallocated.
    @available(SwiftStdlib 6.4, *)
    public static var `deinit`: Options { Options(rawValue: .deinit) }
  }

  /// An event that describes a change to an observed property.
  ///
  /// `Event` provides information about what triggered an observation change handler,
  /// including the type of event (`willSet`, `didSet`, or `deinit`) and the specific
  /// property that changed.
  ///
  /// ## Checking Event Types
  ///
  /// Use the ``kind`` property to determine what type of event occurred:
  ///
  /// ```swift
  /// withObservationTracking(options: [.willSet, .didSet]) {
  ///     print(model.value)
  /// } onChange: { event in
  ///     switch event.kind {
  ///     case .willSet:
  ///         print("Before change")
  ///     case .didSet:
  ///         print("After change")
  ///     case .deinit:
  ///         print("Object deallocated")
  ///     default: break
  ///     }
  /// }
  /// ```
  ///
  /// ## Matching Specific Properties
  ///
  /// Use ``matches(_:)`` to check if a specific property triggered the event:
  ///
  /// ```swift
  /// onChange: { event in
  ///     if event.matches(\Model.name) {
  ///         print("Name property changed")
  ///     }
  /// }
  /// ```
  ///
  /// - Note: The event kind of `.initial` is only used for the
  ///   `withContinuousObservation` function.
  @available(SwiftStdlib 6.4, *)
  public struct Event: ~Copyable {
    /// The kind of observation event that occurred.
    @available(SwiftStdlib 6.4, *)
    public struct Kind: Equatable, Sendable {
      enum RawValue {
        case initial
        case willSet
        case didSet
        case `deinit`
      }

      var rawValue: RawValue
      
      /// An event that occurs upon the initial setup of continuous observation.
      @available(SwiftStdlib 6.4, *)
      public static var initial: Kind { Kind(rawValue: .initial) }
      
      /// An event that occurs before a property value changes.
      @available(SwiftStdlib 6.4, *)
      public static var willSet: Kind { Kind(rawValue: .willSet) }
      
      /// An event that occurs after a property value changes.
      @available(SwiftStdlib 6.4, *)
      public static var didSet: Kind { Kind(rawValue: .didSet) }
      
      /// An event that occurs when the observed object is deallocated.
      @available(SwiftStdlib 6.4, *)
      public static var `deinit`: Kind { Kind(rawValue: .deinit) }
    }

    /// The kind of event that triggered this observation.
    ///
    /// Check this property to determine what type of change occurred:
    ///
    /// ```swift
    /// if event.kind == .willSet {
    ///     print("Property is about to change")
    /// }
    /// ```
    @available(SwiftStdlib 6.4, *)
    public private(set) var kind: Kind

    var tracking: ObservationTracking?
    var continuousState: _ManagedCriticalState<ContinuousObservation.State>?

    init(_ tracking: ObservationTracking?, kind: Kind) {
      self.kind = kind
      self.tracking = tracking
    }

    init(_ tracking: ObservationTracking?, continuousState: _ManagedCriticalState<ContinuousObservation.State>, kind: Kind) {
      self.kind = kind
      self.tracking = tracking
      self.continuousState = continuousState
    }

    /// Returns a Boolean value indicating whether the specified key path matches the
    /// property that changed.
    ///
    /// Use this method to determine if a specific property triggered the observation:
    ///
    /// ```swift
    /// @Observable
    /// class Model {
    ///     var name: String = ""
    ///     var age: Int = 0
    /// }
    ///
    /// withObservationTracking(options: .willSet) {
    ///     print(model.name, model.age)
    /// } onChange: { event in
    ///     if event.matches(\Model.name) {
    ///         print("Name changed")
    ///     } else if event.matches(\Model.age) {
    ///         print("Age changed")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter keyPath: A key path to a property on an observable object.
    /// - Returns: `true` if the specified property triggered this event;
    ///   otherwise, `false`.
    @available(SwiftStdlib 6.4, *)
    public func matches(_ keyPath: PartialKeyPath<some Observable>) -> Bool {
      return tracking?.changed == keyPath
    }

    /// Cancels continuous observation tracking.
    ///
    /// Use this method within the closure parameter to the `withContinuousObservation`
    /// function to stop observing changes.
    ///
    /// ```swift
    /// withContinuousObservation(options: .willSet) { event in
    ///     print(model.value)
    ///     if someCondition {
    ///         event.cancel()
    ///     }
    /// }
    /// ```
    ///
    /// This method has no effect when used in conjunction with a `withObservationTracking`
    /// function, since those functions finish after the first observation.
    @available(SwiftStdlib 6.4, *)
    public func cancel() {
      tracking?.cancel()
      if let continuousState {
        ContinuousObservation.State.cancel(continuousState)
      }
    }
  }
}

@available(SwiftStdlib 6.4, *)
extension ObservationTracking.Options: SetAlgebra {
  @available(SwiftStdlib 6.4, *)
  public init(arrayLiteral elements: ObservationTracking.Options...) {
    var rawValue = RawValue()
    for element in elements {
      rawValue.rawValue |= element.rawValue.rawValue
    }
    self.init(rawValue: rawValue)
  }

  @available(SwiftStdlib 6.4, *)
  public func union(_ other: Self) -> Self {
    Self(rawValue: rawValue.union(other.rawValue))
  }

  @available(SwiftStdlib 6.4, *)
  public func intersection(_ other: Self) -> Self {
    Self(rawValue: rawValue.intersection(other.rawValue))
  }

  @available(SwiftStdlib 6.4, *)
  public func symmetricDifference(_ other: Self) -> Self {
    Self(rawValue: rawValue.symmetricDifference(other.rawValue))
  }

  @available(SwiftStdlib 6.4, *)
  public mutating func formUnion(_ other: Self) {
    rawValue.formUnion(other.rawValue)
  }

  @available(SwiftStdlib 6.4, *)
  public mutating func formIntersection(_ other: Self) {
    rawValue.formIntersection(other.rawValue)
  }

  @available(SwiftStdlib 6.4, *)
  public mutating func formSymmetricDifference(_ other: Self) {
    rawValue.formSymmetricDifference(other.rawValue)
  }
  
  @available(SwiftStdlib 6.4, *)
  public func contains(_ member: Self) -> Bool {
    rawValue.contains(member.rawValue)
  }

  @available(SwiftStdlib 6.4, *)
  @discardableResult
  public mutating func insert(_ newMember: Self) -> (inserted: Bool, memberAfterInsert: Self) {
    let (inserted, memberAfterInsert) = rawValue.insert(newMember.rawValue)
    return (inserted, Self(rawValue: memberAfterInsert))
  }
  
  @available(SwiftStdlib 6.4, *)
  @discardableResult
  public mutating func remove(_ member: Self) -> Self? {
    rawValue.remove(member.rawValue).map { Self(rawValue: $0) }
  }

  @available(SwiftStdlib 6.4, *)
  @discardableResult
  public mutating func update(with newMember: Self) -> Self? {
    rawValue.update(with: newMember.rawValue).map { Self(rawValue: $0) }
  }
}

@available(SwiftStdlib 6.4, *)
extension ObservationTracking.Options: Sendable { }

@available(SwiftStdlib 5.9, *)
struct AccessListResult<T: ~Copyable>: ~Copyable {
  var result: T
  var accessList: ObservationTracking._AccessList?
  var dirty: ObservationRegistrar.Dirty?
}

@available(SwiftStdlib 5.9, *)
fileprivate func generateAccessList<T: ~Copyable, Failure: Error>(
  _ apply: () throws(Failure) -> T
) throws(Failure) -> AccessListResult<T> {
  var accessList: ObservationTracking._AccessList?
  var dirty: ObservationRegistrar.Dirty? = nil
  let result = try withUnsafeMutablePointer(to: &accessList) { (ptr: UnsafeMutablePointer<ObservationTracking._AccessList?>) throws(Failure) -> T in
    let previous = _ThreadLocal.value
    _ThreadLocal.value = UnsafeMutableRawPointer(ptr)
    defer {
      if let scoped = ptr.pointee, let previous {
        if var prevList = previous.assumingMemoryBound(to: ObservationTracking._AccessList?.self).pointee {
          prevList.merge(scoped)
          previous.assumingMemoryBound(to: ObservationTracking._AccessList?.self).pointee = prevList
        } else {
          previous.assumingMemoryBound(to: ObservationTracking._AccessList?.self).pointee = scoped
        }
      }
      _ThreadLocal.value = previous
    }
    let result = try apply()
    dirty = ObservationTracking.deactivateAccessList(ptr)
    return result
  }
  return AccessListResult(result: result, accessList: accessList, dirty: dirty)
}

/// Tracks access to properties and informs on the first change given a specific
/// set of options.
///
/// This method tracks access to any property within the `apply` closure, and
/// informs the caller of the first value change made to participating properties
/// by way of the `onChange` closure, or upon deinitialization of an observed object,
/// depending on the specified options.
///
/// This method is a more advanced version of the `withObservationTracking` method.
/// You can specify whether to track changes on the `willSet` edge of changes, the
/// `didSet` edge of changes, or deinitialization, or any combination of the three.
///
/// Use the ``ObservationTracking.Event`` parameter with the `onChange` closure to
/// determine the origin and kind of the change.
///
/// - Note: It is more often useful to specify the options of `.willSet` or
///   `[.willSet, .deinit]`, since that starts the transaction at the first access of
///   a tracked property. The use of `.didSet` should be restricted to
///   cases where needed for compatibility and other advanced use cases.
///
/// - Parameters:
///   - options: Options to specify how to observe the tracked changes.
///   - apply: A closure that contains properties to track.
///   - onChange: The closure invoked when the value of a property changes.
/// - Returns: The value that the `apply` closure returns if it has a return
///   value; otherwise, there is no return value.
@available(SwiftStdlib 6.4, *)
public func withObservationTracking<Result: ~Copyable, Failure: Error>(
  options: ObservationTracking.Options,
  _ apply: () throws(Failure) -> Result,
  onChange: @escaping @Sendable (borrowing ObservationTracking.Event) -> Void
) throws(Failure) -> Result {
  let accessListResult = try generateAccessList(apply)
  let willSet: (@Sendable (ObservationTracking) -> Void)?
  if options.contains(.willSet) {
    willSet = { tracking in
      onChange(ObservationTracking.Event(tracking, kind: .willSet))
      if !options.rawValue.contains(.continuous) && !options.contains(.didSet) {
        tracking.cancel()
      }
    }
  } else {
    willSet = nil
  }
  let didSet: (@Sendable (ObservationTracking) -> Void)?
  if options.contains(.didSet) {
    didSet = { tracking in
      onChange(ObservationTracking.Event(tracking, kind: .didSet))
      if !options.rawValue.contains(.continuous) {
        tracking.cancel()
      }
    }
  } else {
    didSet = nil
  }
  let `deinit`: (@Sendable () -> Void)?
  if options.contains(.deinit) {
    `deinit` = { 
      onChange(ObservationTracking.Event(nil, kind: .deinit))
    }
  } else {
    `deinit` = nil
  }
  let tracking = ObservationTracking(accessListResult.accessList)
  ObservationTracking._installTracking(options: options, tracking, willSet: willSet, didSet: didSet, deinit: `deinit`)
  switch accessListResult.dirty {
  case .willSet(let keyPath):
    willSet?(ObservationTracking(accessListResult.accessList, changed: keyPath))
  case .didSet(let keyPath):
    didSet?(ObservationTracking(accessListResult.accessList, changed: keyPath))
  case .deinit:
    `deinit`?()
  default:
    break
  }
  return accessListResult.result
}


/// Tracks access to properties and informs on the first change.
///
/// This method tracks access to any property within the `apply` closure, and
/// informs the caller of the first value change made to participating properties
/// by way of the `onChange` closure. The `onChange` closure is invoked within the
/// property mutation on the `willSet` side of the change, to allow for the
/// development of starts of transactions.
///
/// Because the `withObservationTracking` function finishes after the first change,
/// for continuous observation, schedule some action to re-evaluate the tracking later
/// from within the `onChange` closure.
///
/// - Note: Transactions started in the onChange should be ready to handle being
/// called while a transaction is already active. This should appropriately avoid
/// piling up additional invocations of the end of the transaction.
///
/// The following code tracks changes to the name of cars, but it doesn't track
/// changes to any other property of `Car`:
///
///     func render() {
///         withObservationTracking {
///             for car in cars {
///                 print(car.name)
///             }
///         } onChange: {
///             print("Schedule renderer.")
///         }
///     }
///
/// - Parameters:
///     - apply: A closure that contains properties to track.
///     - onChange: The closure invoked when the value of a property changes.
///
/// - Returns: The value that the `apply` closure returns if it has a return
///   value; otherwise, there is no return value.
@available(SwiftStdlib 5.9, *)
public func withObservationTracking<T>(
  _ apply: () -> T,
  onChange: @autoclosure () -> @Sendable () -> Void
) -> T {
  let accessListResult = generateAccessList(apply)
  if let accessList = accessListResult.accessList {
    ObservationTracking._installTracking(accessList, onChange: onChange())
  }
  return accessListResult.result
}

@available(SwiftStdlib 5.9, *)
@_spi(SwiftUI)
public func withObservationTracking<T>(
  _ apply: () -> T,
  willSet: @escaping @Sendable (ObservationTracking) -> Void,
  didSet: @escaping @Sendable (ObservationTracking) -> Void
) -> T {
  let accessListResult = generateAccessList(apply)
  ObservationTracking._installTracking(ObservationTracking(accessListResult.accessList), willSet: willSet, didSet: didSet)
  return accessListResult.result
}

@available(SwiftStdlib 5.9, *)
@_spi(SwiftUI)
public func withObservationTracking<T>(
  _ apply: () -> T,
  willSet: @escaping @Sendable (ObservationTracking) -> Void
) -> T {
  let accessListResult = generateAccessList(apply)
  ObservationTracking._installTracking(ObservationTracking(accessListResult.accessList), willSet: willSet, didSet: nil)
  return accessListResult.result
}

@available(SwiftStdlib 5.9, *)
@_spi(SwiftUI)
public func withObservationTracking<T>(
  _ apply: () -> T,
  didSet: @escaping @Sendable (ObservationTracking) -> Void
) -> T {
  let accessListResult = generateAccessList(apply)
  ObservationTracking._installTracking(ObservationTracking(accessListResult.accessList), willSet: nil, didSet: didSet)
  return accessListResult.result
}
