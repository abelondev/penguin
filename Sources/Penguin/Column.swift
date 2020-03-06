// Copyright 2020 Penguin Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import PenguinCSV

/// A dtype-erased column of data.
public struct PColumn {
    public init<T: ElementRequirements>(_ col: PTypedColumn<T>) {
        self.underlying = PColumnBoxImpl(underlying: col)
    }

    public init<T: ElementRequirements>(empty: T.Type) {
        self.underlying = PColumnBoxImpl(underlying: PTypedColumn(empty: empty))
    }

    public init<T: ElementRequirements>(_ contents: [T]) {
        self.underlying = PColumnBoxImpl(underlying: PTypedColumn(contents))
    }

    public init<T: ElementRequirements>(_ contents: [T?]) {
        self.underlying = PColumnBoxImpl(underlying: PTypedColumn(contents))
    }

    init<T: ElementRequirements>(_ contents: [T], nils: PIndexSet) {
        self.underlying = PColumnBoxImpl(underlying: PTypedColumn(contents, nils: nils))
    }

    fileprivate var underlying: PColumnBox
}

public extension PColumn {
    var count: Int { underlying.count }

    func asDType<DT: ElementRequirements>() throws -> PTypedColumn<DT> {
        return try underlying.asDType()
    }

    func asString() -> PTypedColumn<String> { try! asDType() }
    func asInt() -> PTypedColumn<Int> { try! asDType() }
    func asDouble() -> PTypedColumn<Double> { try! asDType() }
    func asBool() -> PTypedColumn<Bool> { try! asDType() }

    var dtypeString: String { underlying.dtypeString }

    subscript(strAt index: Int) -> String? { underlying[strAt: index] }
    subscript(indexSet: PIndexSet) -> PColumn { underlying[indexSet] }
    subscript<T: ElementRequirements>(index: Int) -> T? {
        get {
            underlying[index]
        }
        set {
            underlying[index] = newValue
        }
    }
    var nils: PIndexSet { underlying.nils }
    func hasNils() -> Bool { underlying.hasNils() }
    func compare(lhs: Int, rhs: Int) -> PThreeWayOrdering { underlying.compare(lhs: lhs, rhs: rhs) }
    @discardableResult mutating func append(_ entry: String) -> Bool { underlying.append(entry) }
    mutating func appendNil() { underlying.appendNil() }
    @discardableResult mutating func append(_ entry: CSVCell) -> Bool { underlying.append(entry) }
    mutating func _sort(_ indices: [Int]) { underlying._sort(indices) }
    func summarize() -> PColumnSummary { underlying.summarize() }
}

extension PColumn: Equatable {
    public static func == (lhs: PColumn, rhs: PColumn) -> Bool {
        return lhs.underlying._isEqual(to: rhs.underlying)
    }
}

fileprivate protocol PColumnBox {
    var count: Int { get }
    func asDType<DT: ElementRequirements>() throws -> PTypedColumn<DT>
    var dtypeString: String { get }
    subscript (strAt index: Int) -> String? { get }
    subscript (indexSet: PIndexSet) -> PColumn { get }
    subscript<T: ElementRequirements>(index: Int) -> T? { get set }
    var nils: PIndexSet { get }
    func hasNils() -> Bool
    func compare(lhs: Int, rhs: Int) -> PThreeWayOrdering
    @discardableResult mutating func append(_ entry: String) -> Bool
    mutating func appendNil()
    @discardableResult mutating func append(_ entry: CSVCell) -> Bool

    mutating func _sort(_ indices: [Int])

    func summarize() -> PColumnSummary

    // A "poor-man's" equality check (without breaking PColumn as an existential
    func _isEqual(to box: PColumnBox) -> Bool

    // Ensure no one else can conform to PColumn other than PTypedColumn. This is to ensure
    // equality behaves in a reasonable manner, due to having to work around Swift's
    // existential type implementation.
    var _doNotConformToPColumn: _PTypedColumnToken { get }
}

fileprivate struct PColumnBoxImpl<T: ElementRequirements>: PColumnBox, Equatable {
    var underlying: PTypedColumn<T>

    var count: Int { underlying.count }
    func asDType<DT: ElementRequirements>() throws -> PTypedColumn<DT> {
        guard T.self == DT.self else {
            throw PError.dtypeMisMatch(have: String(describing: T.self), want: String(describing: DT.self))
        }
        return underlying as! PTypedColumn<DT>
    }
    var dtypeString: String { String(describing: T.self) }

    subscript(strAt index: Int) -> String? { underlying[strAt: index] }
    subscript(indexSet: PIndexSet) -> PColumn {
        return PColumn(underlying[indexSet])
    }
    subscript<DT: ElementRequirements>(index: Int) -> DT? {
        get {
            guard T.self == DT.self else {
                preconditionFailure(PError.dtypeMisMatch(have: String(describing: T.self), want: String(describing: DT.self)).description)
            }
            let tmp: T? = underlying[index]  // TODO: remove the type annotation after the ambiguous subscript is removed.
            return tmp as! DT?
        }
        set {
            guard T.self == DT.self else {
                preconditionFailure(PError.dtypeMisMatch(have: String(describing: T.self), want: String(describing: DT.self)).description)
            }
            let tmp = newValue as! T?
            underlying[index] = tmp
        }
    }
    var nils: PIndexSet { underlying.nils }
    func hasNils() -> Bool { underlying.hasNils() }
    func compare(lhs: Int, rhs: Int) -> PThreeWayOrdering { underlying.compare(lhs: lhs, rhs: rhs) }
    @discardableResult mutating func append(_ entry: String) -> Bool { underlying.append(entry) }
    mutating func appendNil() { underlying.appendNil() }
    @discardableResult mutating func append(_ entry: CSVCell) -> Bool { underlying.append(entry) }

    mutating func _sort(_ indices: [Int]) { underlying._sort(indices) }

    func summarize() -> PColumnSummary {
        if T.self == String.self {
            return (self as! PColumnBoxImpl<String>).underlying.stringSummary()
        }
        if let s = underlying as? HasNumericSummary {
            return s.numericSummary()
        }
        return PColumnSummary(rowCount: count, missingCount: nils.count, details: nil)
    }

    // A "poor-man's" equality check (without breaking PColumn as an existential
    func _isEqual(to box: PColumnBox) -> Bool {
        // TODO: IMPLEMENT ME!
        if type(of: self) != type(of: box) { return false }
        let rhsC = box as! PColumnBoxImpl<T>
        return self == rhsC
    }

    // Ensure no one else can conform to PColumn other than PTypedColumn. This is to ensure
    // equality behaves in a reasonable manner, due to having to work around Swift's
    // existential type implementation.
    var _doNotConformToPColumn: _PTypedColumnToken { _PTypedColumnToken() }

}

fileprivate protocol HasNumericSummary {
    func numericSummary() -> PColumnSummary
}

extension PTypedColumn: HasNumericSummary where T: DoubleConvertible {}

/// A token type that has a package-private initializer to ensure that no other type other than PTypedColumn can confirm to PColumn
public struct _PTypedColumnToken {
    fileprivate init() {}
}
