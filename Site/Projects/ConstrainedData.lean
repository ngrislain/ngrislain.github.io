import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "Don't Vibe — Constrain" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 06, day := 22 }
%%%

Vibe coding is great. You describe what you want, the agent writes it, the tests pass, you ship. It keeps working right up to the moment it does not: the job gets killed by the OOM reaper in production, or it opens ten thousand file descriptors and falls over, or it runs fine on the sample and melts on the real dataset. The code was _correct_. It just assumed it had infinite memory and infinite file handles, because nothing in the problem statement said otherwise.

These are not logic bugs. They are resource bugs, and they surface late: at integration, at scale, in production. Tests rarely catch them because the test data fits in memory. Code review rarely catches them because the offending line looks completely reasonable. "Load the file, sort it, write the result" is a perfectly good sentence until the file is 400GB.

In a [previous post](/projects/2026-3-12-dont-vibe--prove) I argued that Lean 4's type system can encode _correctness_ specifications, so the compiler verifies them and the AI cannot ship code that violates them. This post is about the same idea applied to a different class of property: _resource constraints_. What if "this program never holds more than 100 records in memory" and "this program never has more than 3 files open at once" were facts the compiler checks, not hopes you have at review time?

The full experiment is on [GitHub](https://github.com/ngrislain/lean-lab/tree/main/constrained-data). The short version: encode the limits in the types, hand the agent the unconstrained version, then turn the limits on and watch the implementation reorganise itself into something correct under the budget.

# Resource-aware types

The trick is to make resources _count_ in the type. Two resources here: open files and live records in memory. Both follow the same pattern, so I will sketch one carefully and the other quickly.

Start with a single configuration point. A cap is either `none` (unlimited) or `some k` (at most `k`). The proof obligation at every allocation site is `capOk`:

```
def capOk (n : Nat) : Option Nat → Prop
  | some k => n < k     -- with k allowed, the n-th allocation needs n < k
  | none   => True      -- unlimited: always fine

-- both branches are decidable, so `by decide` discharges the proof automatically
instance (n : Nat) (cap : Option Nat) : Decidable (capOk n cap) := ...
```

Now files. The key idea is to thread the _number of currently open files_ through the type. `FileIO filesCap n m α` is an IO action that starts with `n` files open, ends with `m` open, and produces an `α`. Opening a file goes from `n` to `n + 1`; closing goes from `n + 1` back to `n`.

```
-- an indexed IO: count of open files goes from n to m
def FileIO (filesCap : Option Nat) (n m : Nat) (α : Type) :=
  FileToken n → IO (FileToken m × α)

-- opening requires a proof that we are under the cap, then increments the count
def FileIO.openRead (path : FilePath) (_ : capOk n filesCap := by decide)
    : FileIO filesCap n (n + 1) (Handle FileMode.Read) := ...

-- closing decrements the count
def FileIO.closeHandle (handle : Handle mode) : FileIO filesCap (n + 1) n Unit := ...

-- running requires you to start and end at zero open files
def FileIO.run (env : Env) (x : FileIO env.filesCap 0 0 α) : IO α := ...
```

Two things make this airtight. The `Handle` constructor is `private`, so the only way to get a handle is through `openRead` / `openWrite`, which charge you for it. And `FileIO.run` demands you start and end at zero, so every file you open must be closed. You cannot leak a handle, and you cannot open one past the cap, because the `capOk n filesCap` proof would not check.

Memory works the same way, with a twist. Records do not live in your program; they live in a fixed-size `Pool`. You never hold an `Event`, you hold a `Ref` into the pool, and the pool has `cap` slots. `MemM cap n m α` tracks the number of live refs from `n` to `m`:

```
-- a bounded pool of `cap` slots; allocation physically fails when full
structure Pool (α : Type) where
  cap  : Option Nat
  data : Array (Option α)
  ...

-- an opaque reference into the pool — constructor is private
structure Ref (α : Type) where
  private mk ::
  private idx : Nat

-- allocating a ref needs room (n < cap) and bumps the live count
def MemM.alloc (obj : Event) (_ : capOk n cap := by decide)
    : MemM cap n (n + 1) (Ref Event) := ...

-- releasing a ref frees its slot and drops the count
def MemM.release (r : Ref Event) : MemM cap (n + 1) n Unit := ...
```

The `Ref` constructor is private and the record content never escapes the pool, so the pool's slot count is a hard physical ceiling on how many records can exist at once. This is not a soft limit checked at runtime and logged. It is a count the type system carries.

# Code that does not compile

Here is the payoff. With a cap of, say, 2 open files, this is fine:

```
FileIO.run env do
  let a ← FileIO.openRead "x.jsonl"   -- 0 → 1, needs 0 < 2 ✓
  let b ← FileIO.openRead "y.jsonl"   -- 1 → 2, needs 1 < 2 ✓
  FileIO.closeHandle a
  FileIO.closeHandle b                -- back to 0, run is happy
```

Open one file too many and the program does not run, it does not compile:

```
FileIO.run env do
  let a ← FileIO.openRead "x.jsonl"   -- 0 → 1, 0 < 2 ✓
  let b ← FileIO.openRead "y.jsonl"   -- 1 → 2, 1 < 2 ✓
  let c ← FileIO.openRead "z.jsonl"   -- 2 → 3, needs 2 < 2 ✗
  ...
  -- error: failed to synthesize proof of `capOk 2 (some 2)`, i.e. `2 < 2`
```

Forget to close a handle and `run` rejects you, because the action ends at a nonzero count and `run` only accepts `FileIO filesCap 0 0 α`. The memory pool behaves identically: try to keep a 101st record alive in a 100-slot pool and the `capOk` proof for `alloc` fails to elaborate. The constraint is not a runtime check you might forget to write. It is the precondition of the operation.

# The unconstrained version

Now the experiment. The task: take a month of daily event logs (one JSONL file per day, lots of events each), sort all events by entity and time, group them per entity, and write the result out in shards.

With no caps (`filesCap := none`, `memCap := none`), this is the obvious program any of us, or any agent, would write. Read everything into one big pool, sort the refs, group, write:

```
def collectAndWrite (numShards : Nat := 10) : IO Unit := do
  let mut pool : Pool Event := Pool.empty none      -- unbounded, grows on demand
  let mut all : Array EventRef := #[]
  -- Phase 1: read every event into the pool
  for day in [:31] do
    let path := s!"data/2025-12-{fmt day}.jsonl"
    let (pool', refs) ← FileIO.run env (readDayInto env path pool)
    pool := pool'
    all  := all ++ refs
  -- Phase 2: sort and group, in memory
  let seqs := groupRefs (sortRefs all)
  -- Phase 3: write each shard
  for i in [:numShards] do
    pool ← FileIO.run env (writeShardInto env pool seqs i numShards s!"shard_{i}.jsonl")
```

Read, sort, group, write. It is correct. It is also exactly the program that OOMs on a real month of data, because `all` and the pool grow without bound. The agent had no reason to do anything else, because nothing told it the data would not fit.

# Turn the constraints on

Now flip the caps: at most 3 files open, a pool of exactly 100 slots.

```
abbrev conEnv : Env := { filesCap := some 3, memCap := some 100 }
```

Suddenly the unconstrained program does not type-check. You cannot read 3 million events into a 100-slot pool, the `alloc` proof fails. You cannot hold all the refs and sort them in memory, there is nowhere to put them. The agent has to find an algorithm that sorts more data than fits in memory using a handful of files. That algorithm exists and has a name: external merge sort. A human _can_ write it, but it is fiddly, easy to get subtly wrong, and nobody enjoys it. An AI, handed the type error and the cap, writes it without complaint, because the type checker tells it precisely when it has overstepped.

What it produced is three phases:

```
-- Phase A: split each input into sorted runs of ≤ 100 events
--   read until the pool is full, sort those, spill to a run file, free the pool, repeat
def File.makeRuns (inputPath runDir : String) (startIdx : Nat) (pool : Pool Event)
    : IO (Pool Event × Array String × Nat) := do
  ...
  while !done do
    let (pool', refs, eof) ← File.fillToCap inH pool   -- reads at most `cap` events
    let sorted := refs.qsort EventRef.lt
    let outH ← openW s!"{runDir}/run_{idx}.jsonl"
    for r in sorted do File.writeOne r pool outH
    closeH outH
    pool := File.releaseAll sorted pool                -- pool back to empty
    ...

-- Phase B: 2-way merge runs pairwise until one sorted run remains
--   only the two frontier events are ever live at once
def File.mergeTwo (aPath bPath outPath : String) (pool : Pool Event) : IO (Pool Event) := do
  let (p1, ra) ← File.readOne aH pool ; ...   -- one event from each side
  let (p2, rb) ← File.readOne bH pool ; ...
  while curA.isSome && curB.isSome do
    if EventRef.le a b then
      File.writeOne a pool outH
      pool := File.release a pool             -- free before reading the next
      ...

-- Phase C: stream the single sorted run, emit one shard's entities per pass,
--   chunked so a buffer never exceeds the cap
def File.shardPass (mergedPath outPath : String) (shardIdx numShards : Nat)
    (pool : Pool Event) : IO (Pool Event) := ...
```

The shape of `collectAndWrite` changes to match: build sorted runs, merge them pairwise down to one, then a shard pass per output file.

```
def collectAndWrite (numShards : Nat := 10) : IO Unit := do
  let mut pool : Pool Event := Pool.empty (some 100)
  -- Phase A: sorted runs, each ≤ 100 events
  let mut runs : Array String := #[]
  for day in [:31] do
    let (pool', newRuns, idx') ← File.makeRuns path runDir idx pool
    pool := pool'; runs := runs ++ newRuns; idx := idx'
  -- Phase B: pairwise merge until one run remains
  while runs.size > 1 do
    -- merge runs[j] and runs[j+1] into one, repeat
    ...
  -- Phase C: one shard pass per output file
  for i in [:numShards] do
    pool ← File.shardPass merged s!"shard_{i}.jsonl" i numShards pool
```

# What the constraint produced

Here is the thing worth sitting with. Nobody asked for external merge sort. The prompt did not say "implement Knuth's algorithm." The only new input was two numbers: 3 files, 100 records. The whole structure below, runs and merges and streaming shard passes, is what falls out of those two numbers once the type checker refuses every shortcut.

![External merge sort, as forced by the resource budget](static/projects/constrained-data/pipeline.svg)

Memory stays flat across all three phases. Phase A holds at most one run (100 events) before spilling. Phase B holds the two frontier events of the merge. Phase C holds one entity's buffer, chunked at the cap. At no point are more than 100 event contents alive, and that is not a comment in the code promising good behaviour, it is a property the pool's type enforces.

# Type-driven vibe coding

This is the same bet as [Don't Vibe — Prove](/projects/2026-3-12-dont-vibe--prove), pointed at a different target. There, the type carried a correctness spec and the compiler rejected any implementation that was not provably sorted. Here, the type carries a resource budget and the compiler rejects any implementation that would blow it. In both cases the human writes the constraint, the AI writes the code, and the compiler is the thing that cannot be fooled.

The division of labour is the point. Writing external merge sort by hand is miserable, and reviewing it for a hidden third open file or an unfreed buffer is worse. But _stating_ the budget is trivial: two numbers in an `Env`. The hard, error-prone part, getting the algorithm right under that budget, is exactly what AI is good at when the feedback is a precise type error rather than a vague "looks fine to me." Resource bugs are some of the most expensive bugs in production precisely because they hide until scale. Pulling them forward into the type checker, where they show up as a red squiggle on your laptop, is a very good trade.

The broader thesis, which also runs through [how AI changes the economics of software](/projects/2026-2-20-how-to-die-optimally--ai-meets-economics), is that the value of a programming language is shifting from how nicely a human can read the _how_ to how precisely a human can state the _what_. Resource limits are part of the _what_. So put them in the type, and let the agent vibe within the lines.
