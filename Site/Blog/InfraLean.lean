import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "Terraform in Lean 4: If It Compiles, It Will Likely Deploy" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 09, day := 06 }
%%%

:::hero "A fleet declaration and the dependency graph it produces" "static/blog/infra-lean/thumbnail.png"
:::

I spent two weekends building [infra](https://github.com/typednotes/infra), an infrastructure-as-code tool in Lean 4. It does what Terraform does: you declare the resources you want, it looks at what your cloud accounts actually contain, and it reconciles the difference. Three clouds, fourteen resource kinds, around 15,000 lines of Lean, 107 commits.

It is not production software, and I will get to why. What I want to write about is what a real type system buys an IaC tool, because I think it generalises past this project.

Here is a complete deployment:

```
fleet exampleQueue in paris where
  resource scaleway queues "infra-example"
    { visibilityTimeoutSec := 30 }
```

That is the whole file, plus a one-line `main`. Now the part I did not expect to like as much as I do: `in paris` could be `in warsaw` here, and it would compile. In the file next door, which declares resources on both AWS and Scaleway, `in warsaw` is a compile error, because AWS has no region in Warsaw. Same word, same syntax. Whether it is legal depends on the rest of the file.

# Where the mistakes are caught

The loop is Terraform's: observe, diff, reconcile. What differs is where mistakes are caught. Sorting that out honestly turned out to be most of the design work, and the repo keeps the answer as a table:

:::pipeTable "Mistake | Caught | How\n---|---|---\nA reference to a resource that does not exist | compile time | there is nothing to write down: a reference can only be one of this file's own resources\nA resource that needs another and names none | compile time | the field has no default, so the resource is not finished without it\nUsing a service a cloud does not have | compile time | that cloud has no such resource type, so there is no name for it\nA plan whose shape depends on a value the cloud has not returned yet | compile time | the little expression language cannot branch on one\nAn instance size that does not exist | compile time | the compiler works out which sizes the family comes in, and checks\nA region a cloud is not in | compile time | the compiler works out which of your clouds have a region there\nA bucket name someone else already took | runtime | uniqueness is global, not a property of your file\nQuota, capacity, eventual consistency | runtime | not a property of the configuration at all"
:::

Two different things happen in those compile-time rows. In the first four the mistake has no spelling: there is no way to write the broken configuration down, so nothing has to be checked. In the next two you _can_ write it down, and the compiler decides by running a small function over what you wrote. (Lean people call that second kind an elaboration-time check. For the rest of this post it is just compilation.)

The last two rows are the honest half of any "types catch bugs" claim, and they are why the title is hedged. Compiling is not a promise that the apply will succeed. It is a promise about which failures are still on the table when you get there.

# Three things Terraform cannot say

## A reference that cannot dangle

In HCL:

```
resource "aws_instance" "web" {
  ami                    = "ami-0123456789abcdef0"
  instance_type          = "t3.nano"
  vpc_security_group_ids = [aws_security_group.web.id]
}
```

Terraform resolves that reference in its graph, so a typo is caught at plan time. Two things it cannot say: the field is not required, so deleting the line gives you an instance in the default security group rather than an error; and `.id` is a string by the time the provider sees it, so nothing objects if you pass a subnet id.

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

Three consequences, and none of them is a check that runs later. Leaving the field out does not compile. Naming a group that is not in this file does not compile, because the only things of that type are the groups declared above it. Passing a bucket does not compile either, because a reference carries the cloud and the kind of resource in its type, and a bucket is not a security group. That last one is the case a string could never catch: both resources are in AWS, both exist, and the names look alike.

The first error is my favourite, because of what it is not:

```
Application type mismatch: The argument
  fun securityGroup => Build.awsInstance … securityGroup
has type
  Expr ?m (?m ProviderId.aws Kind.securityGroup) → AwsInstanceSpec …
but is expected to have type
  SpecOf Kind.awsInstance keys.Key Partial (Expr keys.Key)
```

A missing required field leaves you holding a function. There is no validation pass that complains later, and no moment at which a group-less instance exists as a value.

## A size that does not exist, and a place a cloud is not in

In HCL, `instance_type = "t3.nanoo"` is a string. Plan succeeds; apply fails with `InvalidParameterValue`, after the security group it references has been created. `region = "eu-west-3"` is a string too, so a Scaleway code in an AWS provider fails at runtime, usually as a DNS error.

Neither is really a string. An instance type is a family and a size, both from small closed sets, and the *pair* is checked:

```
def InstanceType.of (f : InstanceFamily) (s : InstanceSize)
    (_h : Assert (f.sizes.contains s) := by decide) : InstanceType :=
  ⟨s!"{f.code}.{s.code}"⟩
```

That third argument is the check, and you never write it. `by decide` tells the compiler to settle the claim by computing it: true and it fills the argument in silently, false and there is nothing to fill it with. So `InstanceType.of .t3 .xlarge32` gives:

```
could not synthesize default value for parameter '_h' using tactics
Tactic `decide` proved that the proposition
  Assert (InstanceFamily.t3.sizes.contains InstanceSize.xlarge32)
is false
```

26 families and 17 sizes make 257 valid types, from a table small enough to keep true. It also catches what a curated list of strings gets wrong: gen-7 Intel skips `32xlarge` and jumps to `48xlarge`, while gen-6 AMD reaches 48 and its Intel sibling does not.

A place gets the same treatment, one level up. A locality is a place named before any cloud names it, and each cloud maps it to its own code or to nothing:

```
#guard Locality.paris.code .aws        = some "eu-west-3"
#guard Locality.paris.code .scaleway   = some "fr-par"
#guard Locality.warsaw.code .aws       = none
#guard Locality.ireland.code .scaleway = none
```

So one `in paris` places both clouds correctly, which a region string cannot. For a whole fleet the check is that every cloud it uses has a region there, which makes the set of legal placements something you compute rather than maintain:

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

# The rule Terraform has, and cannot state once

Some of what you declare does not exist yet: an endpoint the cloud assigns, a password you generate. Terraform handles that fine. Move the same unknown one position to the left, though, out of a field and into the question of how many things exist:

```
resource "aws_instance" "web" {
  for_each  = toset(aws_subnet.tier[*].id)   # created in this same apply
  subnet_id = each.value
}
```

That stops at plan time: Terraform cannot say how many instances there will be, so it cannot produce a plan, and it suggests applying part of your configuration first with `-target`.

So Terraform has the right rule (an unknown may fill a field, and may not decide how many things exist), but no way to state it once. It lives in the core and in the providers, you meet it one attribute at a time, and you meet it after the configuration is written.

Here the rule is the shape of what you are allowed to write. A declaration can hold a recipe for a value that does not exist yet, and there are five kinds:

```
inductive Expr (K : ProviderId → Kind → Type) : Type → Type 1 where
  | lit         : α → Expr K α
  | observed    (p : ProviderId) (k : Kind) : K p k → Expr K (ObservedOf k)
  | secretValue (p : ProviderId) : K p .secrets → Expr K String
  | map         : (α → β) → Expr K α → Expr K β
  | ap          : Expr K (α → β) → Expr K α → Expr K β
```

`K` is the parameter carrying the weight. It is this file's own family of resource names, and it appears in the two cases that read a value from somewhere: `observed` and `secretValue` both take a `K p k`. So a recipe can only read from a resource that exists in this file, which is where "a reference cannot dangle" comes from.

The interesting part is the case that is missing. There is deliberately no way to say "look at this value, then decide what to build". `map` and `ap` let an unknown value flow into a field; nothing lets you branch on one, so an unknown value cannot reach the question of how many resources exist. A declaration can hold three values it does not know. It can never hold an unknown _number_ of servers, because there is nowhere to write that down.

The practical difference is when you find out. Terraform's `for_each` restriction is a plan-time error about a configuration you already wrote. Here the mistake has no spelling, so a plan is always computable.

Writing those recipes out by hand is miserable, so there is a shorthand that looks like ordinary string interpolation:

```
resource scaleway secrets "db-password" as pw
  { valueFrom := fromEnv "DB_PASSWORD" }

resource scaleway postgres "main" as db
  { masterUsername := "dbadmin", maxCapacity := 4 }

resource scaleway secrets "db-url"
  { valueFrom := composed
      expr!"postgres://dbadmin:{secretValueOf pw}@{endpointOf db}/main" }
```

That expands to exactly the recipe you would have assembled by hand. The restriction is not relaxed, only hidden: there is still nowhere in the syntax to put a branch.

The two holes in that string are the two arrows in the graph:

![db-password and postgres main both feed db-url](static/blog/infra-lean/dag.svg)

Three resources, three creates, one apply, same as Terraform manages here. The order comes from those arrows: nothing in the file says the password goes first.

# Why dependent types actually help here

"Dependent types" means types that can mention values. Four separate things follow from that here, and only the first is the one people usually have in mind.

*A type can name a value.* A region is not a string, it is a region _of a particular cloud_, and the cloud is in its type: `Region .aws` and `Region .scaleway` are different types, so an AWS region cannot reach a Scaleway call. Same for references. Useful, and the least interesting item here.

*The compiler will run your own checks.* The one with no HCL equivalent, and the whole of it is four lines:

```
@[reducible] def Assert (b : Bool) : Prop := b = true
```

`Assert b` claims that `b` comes out true. Because a type can mention a value, that claim can be _about your configuration_, which is what the two checks above are. Anything a program can compute about a configuration can go there: that the dependency graph has no cycles, that you asked for at most twenty servers, that a name uses only the characters the cloud accepts. Without this you write those as a linter, which is a second implementation of what your configuration means, in another language, run at another time, free to disagree with the first. Here the check is an ordinary function next to the data it checks, and the compiler is what runs it.

The error messages are the payoff, and I did not write any of them:

```
Tactic `decide` proved that the proposition
  Assert (Locality.warsaw.covers keys)
is false
```

That is the compiler quoting my own check back at me, with my own file substituted into it.

The same move covers what HCL leaves to a runbook. Terraform stops managing a resource without destroying it via a `removed` block; here it is `forget scaleway queues "old-queue"`, and the compiler owns it: forgetting something you still declare does not compile, one fleet's releases cannot be handed to another because the type carries the fleet, and a release cannot be built by hand because the only constructor is the checked one.

*One table does three jobs.* The table of places maps each place to each cloud's own code. Autocomplete lists the places from it, the compile-time check reads it, and the assertions pin its entries. The list of valid region codes is computed from it rather than typed out again, so the two cannot drift. In HCL that list lives in the provider's Go source, in the documentation, and in your head, and those three disagree.

*A half-built resource is not a value.* A required field has no default and cannot be left unset, so a half-built resource is not an object with nulls in it. It is a function still waiting for an argument, which is why a missing security group reads as a type mismatch about a function. That is the shift I would keep, and it is not "the type system rejects bad configurations". It is that the set of things you can write can be made close to the set of things you could deploy.

One detail I think is load-bearing for anyone trying this: none of it is worth much if a stale table blocks you, and these tables are snapshots of catalogues that grow. `Region.raw` and `InstanceType.raw` take a string on trust, so falling behind a provider costs a more conspicuous spelling rather than a wall. Get that wrong and the first missing region turns the type system into the enemy.

# Being fair about it

What runs: five declarations in sequence, in CI, on all three clouds. Twelve resources on AWS, twelve on Scaleway, ten on Google Cloud, across thirteen of the fourteen kinds. The whole fleet, the same fleet scaled up, the same scaled back down, a version with two resources dropped, then one that declares nothing. After each stage the account must hold exactly what that stage declares, so a resource whose line is gone has to be destroyed rather than abandoned, and a container scaled back to a floor of zero instances has to actually scale back.

What does not: managed Postgres, which takes longer to create than a CI step allows. And plenty of `update` paths, since the ones that run are the ones the ramp moves.

The last two kinds got covered by removing the excuse rather than waiving it, which I mention because both excuses were mine and both were in this file's ancestor. An EC2 instance needed an image id, and an image id is region-specific and gets replaced whenever Amazon rebuilds it, so the test had a rotting constant in it. Now `imageId := "latest"` asks EC2 for the newest one. A Scaleway function needed deployable code, and takes it only as an uploaded archive, so the declaration carries the source inline and the backend zips it. That needed a CRC-32 and a ZIP writer, which is a strange thing to find in an IaC tool and the honest cost of covering the kind.

Not everything here is ahead of Terraform either. Deleting a resource from the file destroys it, which Terraform has always done, and getting there took two mistakes worth more than the feature. Something has to remember a resource after its line is gone; I put that record in git first, reasoning that what a fleet manages is intent. It is not. A row appears because a resource *was created*, an event at apply time on whatever machine ran the apply. That is why Terraform's state is remote and not committed, and I had to rediscover it. Then the record turned out to learn about a resource only through an *action*, so one that already existed and already matched was never recorded and could never be destroyed. Types helped with neither: both are questions about what happened, not about what is well-formed.

Nor is any of that what types are for. My favourite failure from the live runs:

```
InvalidParameterValue: Invalid security group description. Valid
descriptions are strings less than 256 characters from the following
set:  a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*
```

The description was "created and destroyed by infra's live test". An apostrophe is not in that set. Since descriptions are constants in the file, that would have failed every apply, for ever. Checking a character set is exactly what the compiler can do, and it does now. But I would never have thought to write it. A type system checks the constraints you know about, and the list of ones you do not is longer.

And some things stay at runtime whatever you do: whether a bucket name is globally unique, whether your quota covers the instance, whether the cloud has caught up with itself.

The scale gap is the real answer to "should you use this". Fourteen resource kinds against Terraform's thousands, three clouds instead of hundreds of providers. No module registry, no state locking, no team workflow. If you need to ship infrastructure this week, use Terraform.

What I would carry into a real tool is narrower than the tool: make the desired state a value whose type is narrow enough that undeployable configurations are hard to write, let the compiler run your own checks over it rather than maintaining a linter that can disagree, and give every lookup table a deliberately ugly way out. The remaining 15,000 lines are HTTP clients, and they are the part with bugs.

The code is at [github.com/typednotes/infra](https://github.com/typednotes/infra), and `docs/coverage.md` is the honest account of how far it has been run, including the embarrassing parts.
