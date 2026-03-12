import VersoBlog

open Verso Genre Blog

#doc (Post) "Vibe Coding Needs Guardrails — Enter Type-Driven Development" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 03, day := 12 }
%%%

```leanInit ctx
```

AI can write code fast. Scarily fast. But can it write *correct* code?

If you've spent any time vibe-coding — prompting an LLM, accepting the output, prompting again — you know the feeling: the code *looks* right, the tests pass (when there are tests), and yet something feels fragile. You're building on vibes, not on guarantees. The feedback loop is: prompt, eyeball, ship. And when it breaks, you prompt again.

This works surprisingly well for prototyping. It works less well for anything where correctness matters. The problem is not that AI writes buggy code — humans do that too. The problem is that the *specification* of what "correct" means usually lives in your head, in a Jira ticket, or in a comment that says `// TODO: handle edge cases`. The machine has no way to check its own work against a formal contract.

What if the type system *was* the specification?

# Types as specifications

Most programmers think of types as labels: this is an `int`, that's a `string`. But in languages with *dependent types*, types can express *properties*. Not just "this is a list" but "this is a list *that is sorted*". Not just "this function returns a list" but "this function returns a list *and here is a machine-checked proof that it is sorted*".

This is not science fiction. This is [Lean 4](https://lean-lang.org/) today.

The deep reason this works is the *Curry-Howard correspondence* — one of the most beautiful ideas in computer science. It says that types *are* propositions, and programs *are* proofs. A function of type `A → B` is not just a piece of code that transforms `A` into `B` — it is a constructive proof that "if `A`, then `B`." When you write `List α → SortedList α`, you are simultaneously defining a function and stating a theorem: "for every list, there exists a sorted version, and here is the evidence." The compiler doesn't just check that your code runs — it checks that your *proof* is valid.

The thesis is simple: *if you can express your specification as a type, the compiler becomes your verifier.* The AI can write whatever implementation it wants — insertion sort, merge sort, something bizarre — and the compiler will reject it unless it comes with a valid proof that the output satisfies the spec. No tests needed. No eyeballing. The proof *is* the guarantee.

I believe we are entering a golden age of type-driven development. Not despite AI, but *because* of it. AI is very good at generating code and filling in proof obligations. Humans are good at stating what they actually want. Dependent types are the bridge.

# A worked example: sorting with proof

Let's walk through a concrete example. We'll define a linked list, express what it means for a list to be sorted, define the type of sorted lists, and then ask AI to implement a sort function — twice, with two different algorithms — where the *type* alone forces correctness.

All code is in Lean 4 and compiles without `sorry`.

## Defining a list

A classic inductive type — a list is either empty (`nil`) or an element followed by another list (`cons`):

```
inductive List (α : Type) where
  | nil : List α
  | cons : α → List α → List α
```

Nothing surprising here. This is the same definition you'd find in any functional programming textbook.

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

A `SortedList` is not just a list. It is a list *plus a certificate* that it is sorted. You cannot forge one.

## The specification *is* the type

Here is the key insight. The signature:

```
def List.sort : List α → SortedList α
```

This is simultaneously a *function signature* and a *specification*. It says: "give me any list, and I will return a sorted list — and here is a proof." The implementation can use any algorithm it wants. The type alone guarantees the output is sorted. The compiler checks the proof. No tests needed.

# First attempt: insertion sort ($`O(n^2)`)

The first implementation, generated in a conversation with Claude, uses insertion sort. The algorithm is simple: insert each element into its correct position in an already-sorted list.

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

The theorem is longer than the algorithm. That's normal — and that's the point. The compiler checks every step. The final `sort` is just plumbing:

```
def List.sort (total : ∀ (a b : α), a ≤ b ∨ b ≤ a) (l : List α) : SortedList α :=
  ⟨l.insertionSort, List.insertionSort_sorted total l⟩
```

It works. It's proven correct. But it's $`O(n^2)`.

# Second attempt: merge sort ($`O(n \log n)`)

The next prompt was: "make the sort method N log(N) fast." Same specification. Same type. Different algorithm.

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

Same spec. Better algorithm. The compiler is happy either way.

# The feedback loop that actually works

This is the feedback loop I'm excited about:

1. *Human writes the type* — the specification, the contract, the "what."
2. *AI writes the implementation* — the algorithm, the proof obligations, the "how."
3. *The compiler checks everything* — no ambiguity, no "looks good to me," no flaky tests.

If the proof doesn't go through, the code doesn't compile. The AI can try again, try a different approach, or ask for help. But it cannot ship broken code. The types won't let it.

This is fundamentally different from the current vibe-coding workflow where correctness is checked by running the code and hoping for the best. Here, correctness is *structural*. It's baked into the types. You get it for free — or you don't get it at all.

# Why hasn't this taken off before?

The idea of proving programs correct is as old as computer science itself. Hoare logic dates from 1969. The Curry-Howard correspondence was understood in the 1930s-60s. Coq has existed since 1989. So why isn't all software written this way?

Because the proofs are *brutal* to write by hand.

Look at the insertion sort example above. The algorithm is 6 lines. The proof that it's correct is 25 lines of careful case analysis, threading ordering witnesses through every branch, managing hypotheses, and coaxing the type checker into accepting each step. For merge sort, it's worse — you need termination proofs, helper predicates, and lemmas about list splitting. A working programmer looks at that and reasonably concludes: "I'll just write a test."

And they'd be right — in a world where humans write all the proofs. The cost-benefit ratio never made sense. Writing a specification is fast, but *constructing the proof* that an implementation satisfies it is slow, tedious, and requires deep expertise in both the domain and the proof assistant. For most software, tests and code review were "good enough," and formal verification was reserved for avionics, cryptography, and compilers — domains where bugs kill people or lose millions.

But there is a deeper reason too. The experience of working with a proof assistant is *adversarial*. Every line of code triggers a proof obligation. Every step must be justified. The compiler rejects your attempt, shows you a cryptic goal state, and waits. You tweak, retry, get rejected again. For a human programmer, this constant, unforgiving feedback is exhausting and demoralizing. It feels less like programming and more like arguing with a very patient, very pedantic bureaucrat. No wonder most developers preferred the lenient world of unit tests and "it works on my machine."

AI flips the economics entirely.

# A golden age

The proofs that took me an hour of back-and-forth to get right by hand? Claude generated them in seconds. Not perfectly on the first try — the merge sort proof required iteration, especially around termination arguments and well-founded recursion. But here is the crucial point: that adversarial feedback loop that *breaks* human programmers is exactly the environment where AI *thrives*.

AI doesn't get frustrated when the compiler rejects its proof for the fifteenth time. It doesn't lose motivation staring at an inscrutable goal state. It just reads the error, adjusts its approach, and tries again. The tight, unforgiving feedback from the type checker — the very thing that made formal verification impractical for humans — is precisely the kind of signal that makes AI effective. Where a human sees tedium, the AI sees a well-defined optimization problem: find the term that makes the type checker happy.

Proof construction is mechanical, pattern-heavy, and requires persistence more than creativity. The human states what they want (the type). The AI grinds through the proof obligations. The compiler catches every mistake the AI makes and sends it back for another try. And unlike a human, the AI never decides "close enough, let's ship it."

This is a closed, formal feedback loop — fundamentally different from the "prompt, eyeball, ship" cycle of vibe coding. The compiler is an impartial, tireless, mathematically rigorous reviewer. It doesn't get tired. It doesn't miss edge cases. It doesn't rubber-stamp a PR because it's Friday afternoon.

Lean 4, in particular, is well-positioned for this moment. It's a modern language with good tooling, a fast compiler, and a type system powerful enough to express real-world specifications. The Curry-Howard correspondence is not just a theoretical curiosity — it's the engineering principle. Every type is a theorem. Every program is a proof. Every compilation is a verification.

I think we'll look back at this moment and realize: vibe coding was the prototype. Type-driven development — where humans specify, AI implements, and the compiler verifies — is the production version.

The [full code](https://github.com/ngrislain/lean-lab/tree/main/type-driven-dev) is on GitHub.
