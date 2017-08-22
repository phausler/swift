// RUN: %target-swift-frontend  -primary-file %s -O -sil-verify-all -Xllvm -sil-disable-pass=FunctionSignatureOpts -module-name=test -emit-sil | %FileCheck %s

// Also do an end-to-end test to check all components, including IRGen.
// RUN: %empty-directory(%t) 
// RUN: %target-build-swift -O -Xllvm -sil-disable-pass=FunctionSignatureOpts -module-name=test %s -o %t/a.out
// RUN: %target-run %t/a.out | %FileCheck %s -check-prefix=CHECK-OUTPUT
// REQUIRES: executable_test,swift_stdlib_no_asserts,optimized_stdlib

// Check if the optimizer is able to convert array literals to statically initialized arrays.

// CHECK-LABEL: sil_global private @{{.*}}main{{.*}} = {
// CHECK-DAG:     integer_literal $Builtin.Int64, 100
// CHECK-DAG:     integer_literal $Builtin.Int64, 101
// CHECK-DAG:     integer_literal $Builtin.Int64, 102
// CHECK:         object {{.*}} ({{[^,]*}}, [tail_elems] {{[^,]*}}, {{[^,]*}}, {{[^,]*}})
// CHECK-NEXT:  }

// CHECK-LABEL: outlined variable #0 of arrayLookup(_:)
// CHECK-NEXT:  sil_global private @{{.*}}arrayLookup{{.*}} = {
// CHECK-DAG:     integer_literal $Builtin.Int64, 10
// CHECK-DAG:     integer_literal $Builtin.Int64, 11
// CHECK-DAG:     integer_literal $Builtin.Int64, 12
// CHECK:         object {{.*}} ({{[^,]*}}, [tail_elems] {{[^,]*}}, {{[^,]*}}, {{[^,]*}})
// CHECK-NEXT:  }

// CHECK-LABEL: outlined variable #0 of returnArray()
// CHECK-NEXT:  sil_global private @{{.*}}returnArray{{.*}} = {
// CHECK-DAG:     integer_literal $Builtin.Int64, 20
// CHECK-DAG:     integer_literal $Builtin.Int64, 21
// CHECK:         object {{.*}} ({{[^,]*}}, [tail_elems] {{[^,]*}}, {{[^,]*}})
// CHECK-NEXT:  }

// CHECK-LABEL: outlined variable #0 of passArray()
// CHECK-NEXT:  sil_global private @{{.*}}passArray{{.*}} = {
// CHECK-DAG:     integer_literal $Builtin.Int64, 27
// CHECK-DAG:     integer_literal $Builtin.Int64, 28
// CHECK:         object {{.*}} ({{[^,]*}}, [tail_elems] {{[^,]*}}, {{[^,]*}})
// CHECK-NEXT:  }

// CHECK-LABEL: outlined variable #1 of passArray()
// CHECK-NEXT:  sil_global private @{{.*}}passArray{{.*}} = {
// CHECK:         integer_literal $Builtin.Int64, 29
// CHECK:         object {{.*}} ({{[^,]*}}, [tail_elems] {{[^,]*}})
// CHECK-NEXT:  }

// CHECK-LABEL: outlined variable #0 of storeArray()
// CHECK-NEXT:  sil_global private @{{.*}}storeArray{{.*}} = {
// CHECK-DAG:     integer_literal $Builtin.Int64, 227
// CHECK-DAG:     integer_literal $Builtin.Int64, 228
// CHECK:         object {{.*}} ({{[^,]*}}, [tail_elems] {{[^,]*}}, {{[^,]*}})
// CHECK-NEXT:  }

// CHECK-LABEL: outlined variable #0 of overwriteLiteral(_:)
// CHECK-NEXT:  sil_global private @{{.*}}overwriteLiteral{{.*}} = {
// CHECK-DAG:     integer_literal $Builtin.Int64, 1
// CHECK-DAG:     integer_literal $Builtin.Int64, 2
// CHECK-DAG:     integer_literal $Builtin.Int64, 3
// CHECK:         object {{.*}} ({{[^,]*}}, [tail_elems] {{[^,]*}}, {{[^,]*}}, {{[^,]*}})
// CHECK-NEXT:  }

// CHECK-LABEL: sil @main
// CHECK:   global_value @{{.*}}main{{.*}}
// CHECK:   return
public let globalVariable = [ 100, 101, 102 ]

// CHECK-LABEL: sil {{.*}}arrayLookup{{.*}} : $@convention(thin) (Int) -> Int {
// CHECK:   global_value @{{.*}}arrayLookup{{.*}}
// CHECK:   return
@inline(never)
public func arrayLookup(_ i: Int) -> Int {
  let lookupTable = [10, 11, 12]
  return lookupTable[i]
}

// CHECK-LABEL: sil {{.*}}returnArray{{.*}} : $@convention(thin) () -> @owned Array<Int> {
// CHECK:   global_value @{{.*}}returnArray{{.*}}
// CHECK:   return
@inline(never)
public func returnArray() -> [Int] {
  return [20, 21]
}

public var gg: [Int]?

@inline(never)
public func receiveArray(_ a: [Int]) {
  gg = a
}

// CHECK-LABEL: sil {{.*}}passArray{{.*}} : $@convention(thin) () -> () {
// CHECK:   global_value @{{.*}}passArray{{.*}}
// CHECK:   global_value @{{.*}}passArray{{.*}}
// CHECK:   return
@inline(never)
public func passArray() {
  receiveArray([27, 28])
  receiveArray([29])
}

// CHECK-LABEL: sil {{.*}}storeArray{{.*}} : $@convention(thin) () -> () {
// CHECK:   global_value @{{.*}}storeArray{{.*}}
// CHECK:   return
@inline(never)
public func storeArray() {
  gg = [227, 228]
}

// CHECK-LABEL: sil {{.*}}overwriteLiteral{{.*}} : $@convention(thin) (Int) -> @owned Array<Int> {
// CHECK:   global_value @{{.*}}overwriteLiteral{{.*}}
// CHECK:   is_unique
// CHECK:   store
// CHECK:   return
@inline(never)
func overwriteLiteral(_ x: Int) -> [Int] {
  var a = [ 1, 2, 3 ]
  a[x] = 0
  return a
}

// CHECK-OUTPUT:      [100, 101, 102]
print(globalVariable)
// CHECK-OUTPUT-NEXT: 11
print(arrayLookup(1))
// CHECK-OUTPUT-NEXT: [20, 21]
print(returnArray())
passArray()
// CHECK-OUTPUT-NEXT: [29]
print(gg!)
storeArray()
// CHECK-OUTPUT-NEXT: [227, 228]
print(gg!)
// CHECK-OUTPUT-NEXT: [0, 2, 3]
print(overwriteLiteral(0))
// CHECK-OUTPUT-NEXT: [1, 0, 3]
print(overwriteLiteral(1))
