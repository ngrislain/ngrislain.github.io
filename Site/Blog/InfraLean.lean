import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "Terraform in Lean 4: An Unrealisable Target Is a Compile Error" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 09, day := 06 }
%%%

:::hero "A fleet declaration and the dependency graph it produces" "static/blog/infra-lean/thumbnail.png"
:::

I spent two weekends building [infra](https://github.com/typednotes/infra), an infrastructure-as-code tool in Lean 4. It does what Terraform does: you declare the resources you want, it looks at what your cloud accounts actually contain, and it reconciles the difference. Three clouds, fourteen resource kinds, around 15,000 lines of Lean, 107 commits.

It is not production software, and I will get to why at the end. What I want to write about is the idea that made the two weekends worth spending, because it generalises past this project.

Here is a complete deployment:

```
fleet exampleQueue in paris where
  resource scaleway queues "infra-example"
    { visibilityTimeoutSec := 30 }
```

That is the whole file, plus a one-line `main`. Now the part I did not expect to like as much as I do: `in paris` could be `in warsaw` here, and it would compile. In the file next door, which declares resources on both AWS and Scaleway, `in warsaw` is a compile error, because AWS has no region in Warsaw. Same word, same syntax. Whether it is legal depends on the rest of the file.

# Where the mistakes are caught

The loop is Terraform's: observe, diff, reconcile. What differs is where mistakes are caught. Sorting that out honestly turned out to be most of the design work, and the repo keeps the answer as a table. Three tiers, and only the first two involve the compiler:

:::pipeTable "Mistake | Caught | By what\n---|---|---\nA reference to a resource that does not exist | structural | a reference is an index into this fleet's own keys, so there is no \"not found\" case\nA resource that needs another and names none | structural | the field is unwrapped, so the structure literal is incomplete\nUsing a service a cloud does not have | structural | that cloud's key type for that kind is empty\nA plan whose shape depends on a post-apply value | structural | `Expr` has no `bind`\nAn instance size the family does not come in | elaboration | `Assert (f.sizes.contains s) := by decide`\nA region a cloud is not in | elaboration | `Assert (l.covers κ) := by decide`\nA bucket name someone else already took | apply | uniqueness is global, not a property of your file\nQuota, capacity, eventual consistency | apply | not a property of the configuration at all"
:::

That bottom row is the honest half of any "types catch bugs" claim, and writing it down first is what kept the rest from being marketing.

# Five things Terraform cannot say

## A reference that cannot dangle

In HCL:

```
resource "aws_instance" "web" {
  ami                    = "ami-0123456789abcdef0"
  instance_type          = "t3.nano"
  vpc_security_group_ids = [aws_security_group.web.id]
}
```

Terraform resolves `aws_security_group.web` in its graph, so a typo in that name is caught at plan time. Two things it cannot say. The field is not required, so deleting the line gives you an instance in the default security group rather than an error. And `.id` is a string by the time the provider sees it, so nothing objects if you pass a subnet id instead.

In Lean:

```
resource aws securityGroup "web" as web
  { description := "http and https from anywhere, ssh from nowhere"
  , ingress     := ([(80, "0.0.0.0/0"), (443, "0.0.0.0/0")] : List (Nat × String)) }

resource aws awsInstance "web-1"
  { imageId       := al2023Paris
  , instanceType  := InstanceType.of .t3 .nano
  , securityGroup := web }
```

The field is declared once:

```
securityGroup : Field .required o f (K .aws .securityGroup)
```

Three consequences. Omitting it does not elaborate. Naming a group that is not in this fleet does not elaborate, because the type is an index into this fleet's own keys. Passing a bucket key does not elaborate, because `K` is indexed by cloud _and_ kind. The last one is the case a string could not catch at all: both resources are in AWS, both exist, and the names look alike.

The first error is my favourite, because of what it is not:

```
Application type mismatch: The argument
  fun securityGroup => Build.awsInstance (Expr.lit "no-group") … securityGroup
has type
  Expr ?m (?m ProviderId.aws Kind.securityGroup) → AwsInstanceSpec ?m Partial (Expr ?m)
but is expected to have type
  SpecOf Kind.awsInstance keys.Key Partial (Expr keys.Key)
```

A missing required field leaves you holding a function. There is no validation pass that runs later and complains, and no moment at which a group-less instance exists as a value.

## A spec that is portable, and one that admits it is not

HCL has no portable bucket. `aws_s3_bucket` and `scaleway_object_bucket` are different resource types with different attribute names, so "the same bucket on two clouds" means writing it twice and keeping the halves in sync by hand.

```
resource aws objectStore "typednotes-assets" as assetsAws
  { versioning := true
  , tags       := [("project", "typednotes"), ("tier", "hot")] }

resource scaleway objectStore "typednotes-assets" as assetsScaleway
  { versioning := true
  , tags       := [("project", "typednotes"), ("tier", "hot")] }
```

One spec type, two clouds. Specs are indexed by kind and never by provider, so the cloud enters only at apply time. When you want something only one cloud has, you reach for a provider-local kind, and the loss of portability becomes visible in what you wrote:

```
resource aws s3Bucket "typednotes-archive" as archive
  { objectLock := true }
```

A cloud that does not implement a kind gets the empty type for that pair, so there is no key to write down and nothing to mention:

```
#guard crossCloud.keys.count .aws .postgres  = 0
#guard crossCloud.keys.count .scaleway .s3Bucket = 0
```

## t3.32xlarge

In HCL, `instance_type = "t3.nanoo"` is a string. Plan succeeds. Apply fails with `InvalidParameterValue`, after the security group it references has already been created.

An instance type is not really a string. AWS names it family dot size, and both halves come from small closed sets:

```
def InstanceType.of (f : InstanceFamily) (s : InstanceSize)
    (_h : Assert (f.sizes.contains s) := by decide) : InstanceType :=
  ⟨s!"{f.code}.{s.code}"⟩
```

So `InstanceType.of .t3 .xlarge32` gives:

```
could not synthesize default value for parameter '_h' using tactics
Tactic `decide` proved that the proposition
  Assert (InstanceFamily.t3.sizes.contains InstanceSize.xlarge32)
is false
```

26 families and 17 sizes make 257 valid types, from a table small enough to keep true. It also catches the cases a curated list of strings gets wrong:

```
#guard (InstanceFamily.m7i.sizes.contains .xlarge32) = false
#guard (InstanceFamily.m7i.sizes.contains .xlarge48) = true
#guard (InstanceFamily.m6a.sizes.contains .xlarge48) = true
#guard (InstanceFamily.m6i.sizes.contains .xlarge48) = false
```

Gen-7 Intel skips `32xlarge` and jumps to `48xlarge`. Gen-6 AMD reaches 48 and its Intel sibling does not. Bare metal is spelled `metal` on some families and `metal-24xl` on others. Each of those is stated once in the table instead of three times in your head.

## A place a cloud is not in

HCL puts `region = "eu-west-3"` in the provider block. A Scaleway code in an AWS provider is a runtime failure, and usually a confusing one: the first thing that breaks is DNS.

A locality here is a place, named before any cloud names it. Each cloud maps it to its own code, or to nothing:

```
#guard Locality.paris.code .aws        = some "eu-west-3"
#guard Locality.paris.code .scaleway   = some "fr-par"
#guard Locality.warsaw.code .aws       = none
#guard Locality.ireland.code .scaleway = none
```

One `in paris` therefore places both clouds correctly, which a region string cannot do. For a whole fleet the check is that every cloud it uses has a region there:

```
#guard Locality.paris.covers crossCloud.keys   = true
#guard Locality.milan.covers crossCloud.keys   = true
#guard Locality.warsaw.covers crossCloud.keys  = false   -- Scaleway yes, AWS no
#guard Locality.ireland.covers crossCloud.keys = false   -- AWS yes, Scaleway no
```

Which makes the whole set of legal placements something you compute rather than maintain:

```
#guard (Finite.elems (α := Locality)).filter (·.covers crossCloud.keys)
     = [.paris, .milan]
```

That is the line I would show first. Nobody wrote that list down. It grew on its own when Scaleway opened Milan.

## A secret that cannot be committed

Nothing in HCL stops `password = "hunter2"`. Providers mark attributes sensitive, which redacts them from console output and writes them into the state file anyway.

A secret's value has a source, and the source has exactly two constructors:

```
inductive SecretSource
  | fromEnv  (varName : String)
  | composed (value   : String)
  deriving DecidableEq, BEq
```

No `Repr`, no `ToJson`, no `FromJson`, on purpose. The hand-written `Repr` prints `<redacted>`, so a composed value cannot reach a stray trace. A plan is then checked for whether every secret's source is sound, and it rejects the laundered version too:

```
#guard ¬ ({ name := "leak", valueFrom := .lit (.composed "hunter2") } :
  SecretsSpec composedKeys.Key Partial (Expr composedKeys.Key)).sourceIsSound

#guard ¬ ({ name := "leak", valueFrom := composed (.lit "hunter2") } :
  SecretsSpec composedKeys.Key Partial (Expr composedKeys.Key)).sourceIsSound
```

The second is the one worth having. Wrapping the literal in a `map`, so it is no longer a bare literal, does not get it past the check.

# The one idea I would keep

A target can hold values that do not exist yet. A database endpoint is assigned by the cloud; a password is generated. The type for that is a small expression language:

```
inductive Expr (K : ProviderId → Kind → Type) : Type → Type 1 where
  | lit      {α : Type} : α → Expr K α
  | observed (p : ProviderId) (k : Kind) : K p k → Expr K (ObservedOf k)
  | secretValue (p : ProviderId) : K p .secrets → Expr K String
  | map      {α β : Type} : (α → β) → Expr K α → Expr K β
  | ap       {α β : Type} : Expr K (α → β) → Expr K α → Expr K β
```

The interesting part is the constructor that is missing. There is deliberately no

```
bind : Expr K α → (α → Expr K β) → Expr K β
```

because `bind` would let the _shape_ of the plan depend on a value that is not known until apply, and then "plan" stops existing as a phase. With only `map` and `ap`, the dependency graph is static and unknown values flow along fixed edges. A fleet may have three unknown handles. It can never have an unknown number of instances.

The cost is that writing anything by hand is miserable, so there is a macro that reads like Lean's own string interpolation:

```
resource scaleway secrets "db-password" as pw
  { valueFrom := fromEnv "DB_PASSWORD" }

resource scaleway postgres "main" as db
  { masterUsername := "dbadmin", maxCapacity := 4 }

resource scaleway secrets "db-url"
  { valueFrom := composed
      expr!"postgres://dbadmin:{secretValueOf pw}@{endpointOf db}/main" }
```

It expands to exactly the `map` and `ap` chain you would have written. Nothing is added to `Expr`, and the restriction is not loosened, only made invisible: there is still no way to branch on an unknown value, because the syntax has nowhere to put a branch.

The two holes in that string are the two edges of the graph:

![db-password and postgres main both feed db-url](static/blog/infra-lean/dag.svg)

Three resources, three creates, one apply. In Terraform, a connection string built from a generated password and a cloud-assigned endpoint is the classic two-apply problem, with a human pasting a value in between.

# Deleting a line does not delete a resource

One design decision does more work than the rest. The target is a total function from this fleet's keys to a status, over a finite domain of keys. Total means no key can be forgotten, and it means `absent` is something you can say. So deletion is part of the target rather than an inference from omission.

The practical effect surprises people: removing a resource from the declaration does not delete it from the cloud. It has no key any more, so nothing mentions it, and it keeps running. Saying `.absent` is what turns "I no longer want this" into a delete. I find I trust it more than `terraform destroy` reading absence as intent.

# Why dependent types actually help here

Four distinct things are doing the work, and only the first is the one people usually mean.

*Types indexed by values.* `Key p k`, `Region p`, `Field s`. The index is not documentation, it changes what the type contains: `Region .aws` and `Region .scaleway` are different types, so an AWS region cannot reach Scaleway by construction. Useful, and the least interesting item here.

*Decidable propositions as default arguments.* This is the move with no HCL analogue, and it is four lines:

```
@[reducible] def Assert (b : Bool) : Prop := b = true
```

Written as `(h : Assert (f.sizes.contains s) := by decide)`, the caller writes nothing and a violation is a compile error. Any decidable property of a configuration can join in: acyclicity, `κ.count .aws .compute ≤ 20`, name character sets, region coverage. Without dependent types you write these as a linter, which is a second implementation of your configuration's semantics, in another language, run at another time, free to disagree with the first. Here the predicate is an ordinary function sitting next to the data, and the compiler evaluates it.

The error messages are the payoff, and I wrote none of them:

```
Tactic `decide` proved that the proposition
  Assert (Locality.warsaw.covers keys)
is false
```

That is the compiler quoting my own predicate back at me, with my own fleet substituted in.

*One table, three jobs.* The locality table maps a place to each cloud's code. Autocomplete lists the places, `covers` decides the check, and 348 `#guard` statements across the repo pin the entries. The list of known region codes is derived from the same table rather than written out twice, so the two cannot drift. In HCL, the region list lives in the provider's Go source, in the documentation, and in your head, and those three disagree.

*Incompleteness is not a value.* A required field is not wrapped in the partiality modality at all, so a half-built resource is not an object with nulls in it. It is a function still waiting for an argument. That is the shift I would keep, and it is not "the type system rejects bad configurations". It is that the type of a configuration can be made small enough that most of the things you can write in it are things you could actually build.

One more detail, which I think is load-bearing for anyone trying this. None of it is worth much if a stale table blocks you, and these tables are snapshots of catalogues that grow. So `Region.raw` and `InstanceType.raw` take a string on trust. A table falling behind its provider costs the author a more conspicuous spelling, never a wall. Get that wrong and the first missing region turns the type system into the enemy.

# Being fair about it

The repo keeps a document whose only job is to say how far this has actually been run, and it is blunter than anything I would write in a post. Correctness of request signing is established. Correctness of what is being signed mostly is not. A large part of the endpoint code has never been called against a real account. Three of the fourteen kinds cannot be live-tested at all: a Postgres instance takes five to fifteen minutes to create and as long to delete, an EC2 instance needs a region-specific image id that rots, and a serverless function needs deployable code there is no public equivalent to pull.

And none of the above is what types are for. My favourite failure from the first live runs is this one:

```
InvalidParameterValue: Invalid security group description. Valid
descriptions are strings less than 256 characters from the following
set:  a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*
```

The description was "created and destroyed by infra's live test". An apostrophe is not in that set. Since descriptions are compile-time constants, that one would have failed every apply, for ever. It is a decidable property of a literal, so it can be an `Assert`, and now it is. But I would never have thought to write it. A type system checks the constraints you know about. The list of constraints you do not know about is longer, and you find it by calling the API.

Then there is the tier that stays at runtime no matter what: whether a bucket name is globally unique, whether your quota covers the instance, whether the cloud has caught up with itself yet. No amount of indexing touches those.

The scale gap is the real answer to "should you use this". Fourteen resource kinds against Terraform's thousands, across three clouds instead of hundreds of providers. No module registry, no state locking, no team workflow. If you need to ship infrastructure this week, use Terraform.

What I would carry into a real tool is narrower than the tool itself. Make the target a value in a type small enough that unrealisable configurations are hard to write. Make decidable properties of that value default arguments the compiler discharges. Give every table a visibly ugly way out. The remaining 15,000 lines are HTTP clients, and they are the part that has bugs.

The code is at [github.com/typednotes/infra](https://github.com/typednotes/infra), and `docs/coverage.md` is the honest account of how far it has been run, including the embarrassing parts.
