//
//  Copyright © 2023 Dennis Müller and all collaborators
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import SwiftUI

@propertyWrapper public struct Loadable<Value>: DynamicProperty where Value: Sendable {

    @State private var state: LoadableState<Value>
    @State private var task: Task<Void, Never>?

    /// The current state of the process.
    public var wrappedValue: LoadableState<Value> {
        get { state }
        nonmutating set {
            cancel()
            state = newValue
        }
    }

    /// Provides a manager for controlling the process.
    public var projectedValue: Manager {
        .init(state: $state, task: $task)
    }

    public init(wrappedValue initialState: LoadableState<Value> = .absent) {
        self._state = .init(initialValue: initialState)
    }

    // MARK: - Manual Process Modifiers
    
    /// Cancels any running task associated with this process.
    private func cancel() {
        task?.cancel()
        task = nil
    }
}

extension Loadable {
    /// A manager for controlling the process's state and execution.
    public struct Manager {
        @Binding var state: LoadableState<Value>
        @Binding var task: Task<Void, Never>?

        public func cancel() {
            task?.cancel()
            task = nil
        }

        public func reset() {
            if case .absent = state {} else {
                state = .absent
            }
            cancel()
        }

        @discardableResult public func load(
            silently runSilently: Bool = false,
            priority: TaskPriority? = nil,
            block: @escaping (_ yield: (_ result: Value) -> Void) async throws -> Void
        ) -> Task<Void, Never> {
            cancel()
            let task = Task(priority: priority) {
                do {
                    if !runSilently { state = .loading }
                    try await block { result in
                        state = .loaded(result)
                    }
                } catch is CancellationError {
                    // Task was cancelled. Don't change the state anymore
                } catch is LoadableReset {
                    cancel()
                } catch {
                    state = .error(error)
                }
            }
            self.task = task
            return task
        }

        public func load(
            silently runSilently: Bool = false,
            priority: TaskPriority? = nil,
            block: @escaping (_ yield: (_ result: Value) -> Void) async throws -> Void
        ) async {
            await load(silently: runSilently, priority: priority, block: block).value
        }

        @discardableResult public func load(
            silently runSilently: Bool = false,
            priority: TaskPriority? = nil,
            block: @escaping () async throws -> Value
        ) -> Task<Void, Never> {
            cancel()
            let task = Task(priority: priority) {
                do {
                    if !runSilently { state = .loading }
                    state = try await .loaded(block())
                } catch is CancellationError {
                    // Task was cancelled. Don't change the state anymore
                } catch is LoadableReset {
                    cancel()
                } catch {
                    state = .error(error)
                }
            }
            self.task = task
            return task
        }

        public func load(
            silently runSilently: Bool = false,
            priority: TaskPriority? = nil,
            block: @escaping () async throws -> Value
        ) async {
            await load(silently: runSilently, priority: priority, block: block).value
        }
    }
}

extension Loadable: Equatable where Value: Equatable {
    public static func == (lhs: Loadable<Value>, rhs: Loadable<Value>) -> Bool {
        lhs.state == rhs.state
    }
}