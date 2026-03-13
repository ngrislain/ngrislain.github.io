import VersoBlog

open Verso Genre Blog

#doc (Post) "Don't Vibe — Prove" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 03, day := 12 }
%%%

```leanInit ctx
```

AI can write code fast. But can it write *correct* code?

Vibe coding has grown up. What started as "prompt and pray" has evolved into a serious engineering discipline: practitioners design verification harnesses, write rule files, set up automated test suites, and let AI agents run autonomously for hours. The human role has shifted from writing code to defining constraints and reviewing outputs. The results are impressive — and improving fast.

This shift has a corollary that is rarely stated: if humans no longer read most of the generated code, then optimizing a language for human readability is no longer the priority it once was. The appeal of Python or JavaScript — clear syntax, gentle learning curve — mattered when humans were the primary authors *and* readers. In a world where AI writes the implementation and humans mostly define intent, the value of a language increasingly lies in how precisely it can express *what* the code should do, not in how pleasantly a human can read *how* it does it. Languages will likely shift their focus from implementation ergonomics to specification power.

Yet today, a fundamental tension remains. However sophisticated the harness, the specification and the implementation are separate artifacts. The constraints live in one place, the code in another, and the link between them must be continuously checked by external tooling. There is always a gap between intent and implementation — a gap that can be narrowed, but never closed.

What if the type system *were* the specification?

# Types as specifications

Any type system expresses *some* properties — even `int` vs `string` rules out a class of errors. Richer type systems express richer properties: generics constrain relationships between types, linear types track resource ownership, refinement types attach predicates to base types. But *dependent types* go further: types can depend on *values*, which makes the type language expressive enough to state arbitrary logical propositions. Not just "this is a list" but "this is a list *of length n*." Not just "this function returns a list" but "this function returns a list *and here is a machine-checked proof that it is sorted*."

This is not speculative. This is [Lean 4](https://lean-lang.org/) today.

The theoretical foundation is the *Curry-Howard correspondence*: types *are* propositions, and programs *are* proofs. A function of type `A → B` is not merely a piece of code that transforms `A` into `B` — it is a constructive proof that "if `A`, then `B`." When one writes `List α → SortedList α`, one is simultaneously defining a function and stating a theorem: "for every list, there exists a sorted version, and here is the evidence." The compiler does not merely check that the code runs — it checks that the *proof* is valid.

The thesis follows directly: *if the specification can be expressed as a type, the compiler becomes the verifier.* The AI can produce whatever implementation it wants — insertion sort, merge sort, something entirely novel — and the compiler will reject it unless it comes with a valid proof that the output satisfies the specification. The proof *is* the guarantee.

There is good reason to believe we are entering a golden age of type-driven development. Not despite AI, but *because* of it. AI is effective at generating code and filling in proof obligations. Humans are effective at stating what they want. Dependent types are the bridge.

# A worked example: sorting with proof

The following example defines a linked list, expresses what it means for a list to be sorted, defines the type of sorted lists, and then demonstrates two AI-generated sort implementations — using different algorithms — where the *type* alone forces correctness.

All code is in Lean 4 and compiles without `sorry`.

## Defining a list

A standard inductive type — a list is either empty (`nil`) or an element followed by another list (`cons`):

```
inductive List (α : Type) where
  | nil : List α
  | cons : α → List α → List α
```

This is the standard definition found in any functional programming textbook.

## Expressing "sorted"

Here is where dependent types shine. We define `Sorted` as an *inductive predicate* — a type indexed by a `List α` that can only be constructed if the list is actually sorted:

```
inductive Sorted [LE α] : List α → Prop where
  | nil : Sorted .nil
  | singleton (x : α) : Sorted (.cons x .nil)
  | cons (x y : α) (xs : List α)
      (hxy : x ≤ y) (h : Sorted (.cons y xs)) :
      Sorted (.cons x (.cons y xs))
```

Read it bottom-up: you can prepend `x` to a sorted list starting with `y`, but *only if you provide a proof that `x ≤ y`*. The empty list and singletons are trivially sorted. There is no way to construct a `Sorted` witness for an unsorted list — the type system prevents it.

## The type `SortedList`

Now we bundle a list together with its proof of sortedness:

```
structure SortedList (α : Type) [LE α] where
  list : List α
  sorted : Sorted list
```

A `SortedList` is not merely a list. It is a list *together with a certificate* that it is sorted. There is no way to construct one without providing the proof.

## The specification *is* the type

The key insight is in the signature:

```
def List.sort : List α → SortedList α
```

This is simultaneously a *function signature* and a *specification*. It says: "give me any list, and I will return a sorted list — and here is a proof." The implementation can use any algorithm it wants. The type alone guarantees the output is sorted. The compiler checks the proof. No tests needed.

In practice, this is what gets handed to an AI agent:

```
def List.sort : List α → SortedList α :=
  sorry
  -- Hey AI, please implement this
```

The `sorry` is Lean's way of saying "proof missing" — the code compiles but the obligation is unfulfilled. The agent's job is to replace `sorry` with an implementation that satisfies the type. Below are two attempts, using different algorithms, both generated by Claude.

# First attempt: insertion sort ($`O(n^2)`)

The first attempt uses insertion sort: insert each element into its correct position in an already-sorted list.

```
def List.insert (x : α) : List α → List α
  | .nil => .cons x .nil
  | .cons y ys =>
      if x ≤ y then .cons x (.cons y ys)
      else .cons y (ys.insert x)

def List.insertionSort : List α → List α
  | .nil => .nil
  | .cons x xs => (xs.insertionSort).insert x
```

The algorithm itself is short. The real work is proving that `insert` preserves sortedness. The proof proceeds by induction on the list, case-splitting on whether the new element goes before or after the head, and threading the ordering proof through each branch:

```
theorem List.insert_sorted
    (total : ∀ (a b : α), a ≤ b ∨ b ≤ a)
    (x : α) : ∀ (l : List α), Sorted l → Sorted (l.insert x) := by
  intro l
  induction l with
  | nil => intro _; exact .singleton x
  | cons y ys ih =>
    intro h
    unfold List.insert
    split
    case isTrue hxy => exact .cons x y ys hxy h
    case isFalse hxy =>
      have hyx := (total x y).resolve_left hxy
      cases ys with
      | nil =>
        simp [List.insert]
        exact .cons y x .nil hyx (.singleton x)
      | cons z zs =>
        have hyz : y ≤ z := by cases h with | cons _ _ _ h _ => exact h
        have htail : Sorted (.cons z zs) := by
          cases h with | cons _ _ _ _ h => exact h
        have ih' := ih htail
        unfold List.insert at ih' ⊢
        split
        next hxz =>
          rw [if_pos hxz] at ih'
          exact .cons y x (.cons z zs) hyx ih'
        next hxz =>
          rw [if_neg hxz] at ih'
          exact .cons y z (zs.insert x) hyz ih'
```

The theorem is longer than the algorithm. This is expected — and precisely the point. The compiler checks every step. The final `sort` is straightforward assembly:

```
def List.sort (total : ∀ (a b : α), a ≤ b ∨ b ≤ a) (l : List α) : SortedList α :=
  ⟨l.insertionSort, List.insertionSort_sorted total l⟩
```

Notice the `total` parameter. The original specification said nothing about the ordering being total — but the agent, forced by the type system to *prove* that every comparison resolves one way or the other, discovered the missing assumption and made it explicit. This is not pedantry. IEEE floating-point numbers are *not* totally ordered: `NaN` is neither less than, greater than, nor equal to anything, including itself. A sort function that assumes totality without requiring it will silently produce wrong results on lists containing `NaN`. This is the same issue that led Rust to distinguish `PartialOrd` from `Ord` and to refuse to let you sort a `Vec<f64>` with `.sort()` — except that here, the requirement was not designed into the language by its authors; it was *discovered* by the agent as a necessary condition for the proof to go through. This is exactly the kind of subtle bug that tests rarely catch and code review often misses.

The implementation is proven correct ([full code](https://gist.github.com/ngrislain/2f0c8486aea1a0977092ed1fb38d55ad)). However, it is $`O(n^2)`.

# Second attempt: merge sort ($`O(n \log n)`)

The next prompt to Claude was: "make the sort method N log(N) fast." Same specification. Same type. Different algorithm.

Merge sort splits the list in two, recursively sorts both halves, and merges the results. The core merge function:

```
def List.merge : List α → List α → List α
  | .nil, r => r
  | .cons x xs, .nil => .cons x xs
  | .cons x xs, .cons y ys =>
    if x ≤ y then .cons x (merge xs (.cons y ys))
    else .cons y (merge (.cons x xs) ys)
termination_by l r => l.length + r.length
```

The `termination_by` annotation is required because this is not structurally recursive — Lean needs to verify that the recursion terminates by checking that the combined length decreases at each call.

Proving merge preserves sortedness requires a helper predicate `LeHead` ("x is less than or equal to the head of the list, if any") and two theorems:

```
-- If z ≤ both heads, then z ≤ the head of the merged list
theorem List.merge_leHead (z : α) :
    ∀ (l r : List α), LeHead z l → LeHead z r → LeHead z (l.merge r)

-- Merging two sorted lists produces a sorted list
theorem List.merge_sorted (total : ∀ (a b : α), a ≤ b ∨ b ≤ a) :
    ∀ (l r : List α), Sorted l → Sorted r → Sorted (l.merge r)
```

Then the sort itself, with its termination proof relying on the fact that `split` produces strictly smaller halves:

```
def List.mergeSort : List α → List α
  | .nil => .nil
  | .cons x .nil => .cons x .nil
  | .cons x (.cons y rest) =>
    let p := (List.cons x (.cons y rest)).split
    (p.1.mergeSort).merge (p.2.mergeSort)
termination_by l => l.length
```

And the final assembly, same type signature as before:

```
def List.sort (total : ∀ (a b : α), a ≤ b ∨ b ≤ a) (l : List α) : SortedList α :=
  ⟨l.mergeSort, List.mergeSort_sorted total l⟩
```

Same spec. Better algorithm. The compiler is happy either way ([full code](https://gist.github.com/ngrislain/19eff850b02e4cca2af10fdf451e4580)).

# The feedback loop

The workflow that emerges is:

1. *Human writes the type* — the specification, the contract, the "what."
2. *AI writes the implementation* — the algorithm, the proof obligations, the "how."
3. *The compiler checks everything* — no ambiguity, no "looks good to me," no flaky tests.

If the proof doesn't go through, the code doesn't compile. The AI can try again, try a different approach, or ask for help. But it cannot ship broken code. The types won't let it.

Harness-first vibe coding already moves in this direction — TLA+ specifications, deterministic simulation, model checking. Type-driven development takes the next step: the specification *is* the code. There is no gap between the invariant and the implementation, because the type system enforces them as one. The compiler doesn't check a sample of behaviors or a separate formal model; it verifies that the implementation *necessarily* satisfies the specification, for all inputs, by construction.

# Why hasn't this taken off before?

The idea of proving programs correct is as old as computer science itself. Hoare logic dates from 1969. The Curry-Howard correspondence was understood in the 1930s-60s. Coq has existed since 1989. So why isn't all software written this way?

Because the proofs are extremely difficult to write by hand.

Consider the insertion sort example above. The algorithm is 6 lines. The proof that it is correct is 25 lines of careful case analysis, threading ordering witnesses through every branch, managing hypotheses, and guiding the type checker through each step. For merge sort, the situation is worse — it requires termination proofs, helper predicates, and lemmas about list splitting. A working programmer would reasonably conclude: "a test suite is sufficient."

And that conclusion would be correct — in a world where humans write all the proofs. The cost-benefit ratio did not justify the effort. Writing a specification is fast, but *constructing the proof* that an implementation satisfies it is slow, demanding, and requires deep expertise in both the domain and the proof assistant. For most software, tests and code review were adequate, and formal verification was reserved for avionics, cryptography, and compilers — domains where bugs cause fatalities or significant financial loss.

There is a deeper reason as well. The experience of working with a proof assistant is *adversarial*. Every line of code triggers a proof obligation. Every step must be justified. The compiler rejects the attempt, presents a goal state, and waits. The developer adjusts, retries, and is rejected again. For a human programmer, this constant, unforgiving feedback is exhausting. It resembles less programming than an argument with a very patient, very pedantic bureaucrat. Most developers understandably preferred the more forgiving world of unit tests.

AI flips the economics entirely.

# A golden age

The proofs that took an hour of back-and-forth to construct by hand, Claude generated in seconds. Not perfectly on the first attempt — the merge sort proof required iteration, especially around termination arguments and well-founded recursion. But the crucial observation is this: the adversarial feedback loop that *exhausts* human programmers is exactly the environment where AI *excels*.

An AI does not become frustrated when the compiler rejects its proof for the fifteenth time. It does not lose motivation confronting an opaque goal state. It reads the error, adjusts its approach, and tries again. The tight, unforgiving feedback from the type checker — the very property that made formal verification impractical for humans — is precisely the kind of signal that makes AI effective. Where a human sees tedium, the AI encounters a well-defined optimization problem: find the term that satisfies the type checker.

Proof construction is mechanical, pattern-heavy, and requires persistence more than creativity. The human states the intent (the type). The AI constructs the proof obligations. The compiler catches every mistake and returns it for another attempt. Unlike a human, the AI never concludes "close enough."

This is a closed, formal feedback loop — a natural evolution of the harness-first approach that the best vibe-coding practitioners already use. The difference is one of *integration*: in a harness-first workflow, the formal specification (TLA+, invariant checkers) and the implementation are separate artifacts maintained in parallel. In type-driven development, they are the same artifact. The type *is* the specification, the program *is* the proof, and the compiler is the verifier. There is no drift between spec and code, because they cannot diverge.

Lean 4, in particular, is well-positioned for this moment. It is a modern language with good tooling, a fast compiler, and a type system powerful enough to express real-world specifications. The Curry-Howard correspondence is not merely a theoretical curiosity — it is the engineering principle. Every type is a theorem. Every program is a proof. Every compilation is a verification.

Harness-first vibe coding established the right pattern: humans specify, AI implements, automated systems verify. Type-driven development is the natural culmination of that pattern — one where specification, implementation, and verification are unified in the same language, with no gaps between them.
