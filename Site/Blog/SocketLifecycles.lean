import VersoBlog

open Verso Genre Blog

#doc (Post) "Why Lean let me close a socket twice" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 11, day := 26 }
%%%

In March I wrote that Lean would prevent callers from closing the same POSIX socket twice. A reader pointed out that the old handle was still in scope. Saving the result of the first close gives you a closed handle, but Lean also lets you keep using the old one. Both calls type-check. [The bug report](https://github.com/typednotes/linen/issues/13) was right.

# What the type was checking

The direct socket API takes a handle tagged with a state. The compiler checks the tag on the argument you pass. Closing returns a new value tagged `.closed`. Both values refer to the same native resource, and the earlier value keeps its `.connected` tag.

```
def closeTwice (s : Socket .connected) : IO Unit := do
  let _ ← Network.Socket.close s
  let _ ← Network.Socket.close s
```

The proof attached to `close` asks whether the argument's tag differs from `.closed`. It succeeds both times. The native shim treats the second sequential close as a no-op, but the API never delivered the compile-time guarantee the documentation claimed.

![Before closing, s points to an open descriptor. After closing, the old connected tag and the new closed tag both refer to the same native socket object.](static/blog/socket-lifecycles/stale-alias.svg)

_Figure 1. Closing changes the native descriptor. Returning a value with a new tag leaves the older value’s tag intact._

# Put the state on the program

The report pointed to [Idris's socket tutorial](https://docs.idris-lang.org/en/latest/st/examples.html). In that design, the interpreter owns the socket and the caller composes actions that describe transitions. Linen now has a scoped API based on the same idea.

A value of type `SocketM .connected .closed Unit` is a program that starts with a connected socket and ends with it closed. Its caller never gets a reference to the native handle. Indexed bind requires the next action to start where the preceding one finished.

```
def closeOnce : SocketM .connected .closed Unit :=
  SocketM.close

-- Lean rejects this definition.
def closeTwiceAgain : SocketM .connected .closed Unit :=
  Program.ibind (SocketM.close (state := .connected)) fun () => SocketM.close
```

The second close would need a proof that `.closed ≠ .closed`. That's the proposition the first implementation was meant to make the caller prove. The scope makes the proposition about the current program state. It also releases the socket if an I/O operation throws before the program reaches its explicit close.

![The scoped socket starts fresh. A server binds and listens, then accepts a separate connected child. A client can connect immediately or go through a connecting phase. Any live socket can close.](static/blog/socket-lifecycles/scoped-socket-states.svg)

_Figure 2. Server and client paths through the scoped API. Accepting a child preserves the listener’s state. After polling a pending connection, only a successful `connectFinish` advances it to connected. If an operation throws, the runner cleans up._

# The peer can still change the connection

Owning the local descriptor gives the interpreter control over who closes it. The remote peer can send a FIN or reset the TCP connection between calls. A `.connected` index tells me what I can attempt. It cannot promise that the next read will deliver data.

Idris's example uses a runtime result to choose the next state. Linen's `recvOrClose` does the same for protocols that want to stop on EOF or a receive error. When a read returns data or would block, the continuation gets a connected socket. When it returns EOF or an error, the interpreter closes the socket and the continuation starts closed. An application can use `recv` if it wants to keep writing after the peer stops sending.

![Data and backpressure run a connected handler. For EOF or error, recvOrClose closes the local socket before running the handler in the closed state.](static/blog/socket-lifecycles/receive-outcomes.svg)

_Figure 3. The OS supplies the result. The scope uses it to decide whether to close, and each handler is checked against its resulting state._

```
def receiveOne : SocketM .connected .closed (Option ByteArray) :=
  Program.bind (SocketM.recvOrClose 1) fun outcome =>
    match outcome with
    | .data bytes =>
      Program.map (fun () => some bytes) (SocketM.close (state := .connected))
    | .wouldBlock => Program.map (fun () => none) SocketM.close
    | .eof => Program.pure none
    | .error error => Program.lift (throw error)
```

The compiler checks what each branch does after it knows the result. The socket still does real work at runtime. A [loopback test](https://github.com/typednotes/linen/blob/6bc4d71a56bbe802ede71555cdbc105c661e8219/LinenTest/Linen/Network/Socket/ScopedTest.lean) drives all four results. For the EOF case the peer shuts down just its send side, then checks that it can already see our close while the EOF handler is running.

The same pattern lets a SQLite cursor expose columns only when a step returns a row. The common idea is to put ownership and sequencing under the interpreter's control, then turn the observations it gets from I/O into typed continuations.

[PR #16](https://github.com/typednotes/linen/pull/16) contains the implementation. The [Linen resource guide](https://github.com/typednotes/linen/blob/main/docs/resource-lifecycles.md) explains the scope boundaries. From the Linen checkout, run `lake test --wfail` to run the regression.
