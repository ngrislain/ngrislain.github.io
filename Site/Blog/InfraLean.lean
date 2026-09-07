import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "Like Terraform, but in Lean 4" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 09, day := 06 }
%%%

:::hero "A fleet declaration and the dependency graph it produces" "static/blog/infra-lean/thumbnail.png"
:::

I spent two weekends building [infra](https://github.com/typednotes/infra), an infrastructure-as-code tool in Lean 4. It does what Terraform does: you declare the resources you want, it reads what your cloud accounts actually contain, and it reconciles the difference. Three clouds, fourteen resource kinds, about 18,000 lines of Lean, 126 commits.

It was an experiment with one question behind it. How many of the mistakes you normally discover halfway through an `apply` can be moved into the compiler, if the compiler has dependent types? And does that actually make the loop faster, or does it just move the pain earlier?

There is a second reason, and I will state it rather than pretend the first one was enough. Lean 4 is the language I most enjoy writing, and it is the best language I know for working with an AI. Not because it generates Lean well, it generates Python better. Because in Lean "it compiles" carries information. An agent writing Python gives you something plausible; an agent writing Lean gives you something the compiler has already argued with. The feedback loop is short, precise and machine-checkable, and I would rather spend my weekend inside that loop than reading a diff hoping it is right. Infrastructure code is a good place to test the idea, because infrastructure is where a plausible-looking mistake costs money and downtime instead of a stack trace.

Here is a complete deployment:

```
fleet exampleQueue in paris where
  resource scaleway queues "infra-example"
    { visibilityTimeoutSec := 30 }
```

That is the whole file, plus a one-line `main`. And the part I did not expect to like as much as I do: `in paris` could be `in warsaw` here, and it would compile. In the file next door, which declares resources on both AWS and Scaleway, `in warsaw` is a compile error, because AWS has no region in Warsaw. Same word, same syntax. Whether it is legal depends on the rest of the file.

# Where the mistakes are caught

The loop is Terraform's: observe, diff, reconcile. What differs is where mistakes are caught. Sorting that out honestly turned out to be most of the design work, and the repo keeps the answer as a table:

:::pipeTable "Mistake | Caught | How\n---|---|---\nA reference to a resource that does not exist | compile time | there is nothing to write down: a reference can only be one of this file's own resources\nA resource that needs another and names none | compile time | the field has no default, so the resource is not finished without it\nUsing a service a cloud does not have | compile time | that cloud has no such resource type, so there is no name for it\nA plan whose shape depends on a value the cloud has not returned yet | compile time | the little expression language cannot branch on one\nAn instance size that does not exist | compile time | the compiler works out which sizes the family comes in, and checks\nA region a cloud is not in | compile time | the compiler works out which of your clouds have a region there\nA bucket name someone else already took | runtime | uniqueness is global, not a property of your file\nQuota, capacity, eventual consistency | runtime | not a property of the configuration at all"
:::

Two different things happen in those compile-time rows. In the first four the mistake has no spelling: there is no way to write the broken configuration down, so nothing has to be checked. In the next two you _can_ write it down, and the compiler decides by running a small function over what you wrote. (Lean people call that second kind an elaboration-time check. For the rest of this post it is just compilation.)

The last two rows are the honest half of any "types catch bugs" claim. Compiling is not a promise that the apply will succeed. It is a promise about which failures are still on the table when you get there.

# The differences, listed

Before the code, the short version of what this buys over HCL:

:::pipeTable "| Terraform | infra\n---|---|---\nA reference | a string the graph resolves, typo caught at plan time | a value whose type carries the cloud and the kind, typo has no spelling\nA required reference | providers rarely enforce one, a missing field falls back to a default | no default exists, so the resource is a function still waiting for an argument\nOrdering | derived from expressions, `depends_on` by hand for the rest | derived from references, there is no `depends_on`\nRegion | a string per provider block, aliases for more than one | a place, mapped to each cloud's own code, one word places every cloud\nInstance type | a string | a family and a size, and the pair is checked\nSecrets | marked sensitive, redacted from output, written into state | a source, never a value, and no way to print one\nAn unknown deciding how many resources exist | a plan-time error you meet one attribute at a time | not expressible, so a plan is always computable\nYour own invariants | a separate linter, in another language, free to disagree | a Lean function the compiler runs while your file elaborates\nThe language | HCL | Lean, with its loops, functions, tests and abstraction\nProviders and ecosystem | thousands of resource types, modules, state locking, team workflow | fourteen kinds, three clouds, no registry"
:::

The last row is why you should use Terraform this week. The rest is what I think is worth stealing.

# Side by side

## A reference that cannot dangle

The right-hand pane below is not my invention. `toHcl` in the repo generates it from the fleet on the left, and I only aligned the `=` signs.

:::sideBySide "infra (Lean)" "fleet webTier in paris where\n  resource aws securityGroup \"web\" as web\n    { description := \"http and https, ssh from nowhere\" }\n\n  resource aws awsInstance \"web-1\"\n    { imageId       := \"ami-0123456789abcdef0\"\n    , instanceType  := InstanceType.of .t3 .nano\n    , securityGroup := web }" "main.tf (generated by toHcl)" "provider \"aws\" {\n  region = \"eu-west-3\"\n}\n\nresource \"aws_security_group\" \"web\" {\n  name        = \"web\"\n  description = \"http and https, ssh from nowhere\"\n  region      = \"eu-west-3\"\n}\n\nresource \"aws_instance\" \"web-1\" {\n  ami                    = \"ami-0123456789abcdef0\"\n  instance_type          = \"t3.nano\"\n  vpc_security_group_ids = [aws_security_group.web.id]\n  region                 = \"eu-west-3\"\n}"
:::

Terraform resolves `aws_security_group.web.id` in its graph, so a typo there is caught at plan time. Two things it cannot say. The field is not required, so deleting the line gives you an instance in the default security group rather than an error. And `.id` is a string by the time the provider sees it, so nothing objects if you pass a subnet id instead.

On the left the field is declared once:

```
securityGroup : Field .required o f (K .aws .securityGroup)
```

Three consequences, and none of them is a check that runs later. Leaving the field out does not compile. Naming a group that is not in this file does not compile, because the only things of that type are the groups declared above it. Passing a bucket does not compile either, because a reference carries the cloud and the kind in its type, and a bucket is not a security group. That last one is the case a string could never catch: both resources are in AWS, both exist, and the names look alike.

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

In HCL, `instance_type = "t3.nanoo"` is a string. Plan succeeds, apply fails with `InvalidParameterValue`, after the security group it references has been created. `region = "eu-west-3"` is a string too, so a Scaleway code in an AWS provider block fails at runtime, usually as a DNS error.

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

So one `in paris` places every cloud a fleet uses, which a region string cannot:

:::sideBySide "infra (Lean)" "fleet crossCloud in paris where\n  resource aws objectStore \"typednotes-assets\"\n    { versioning := true }\n\n  resource scaleway objectStore \"typednotes-assets\"\n    { versioning := true }" "main.tf (generated by toHcl)" "provider \"aws\" {\n  region = \"eu-west-3\"\n}\n\nprovider \"scaleway\" {\n  region = \"fr-par\"\n}\n\nresource \"aws_s3_bucket\" \"typednotes-assets\" {\n  bucket     = \"typednotes-assets\"\n  versioning = true\n  region     = \"eu-west-3\"\n}\n\nresource \"scaleway_object_bucket\" \"typednotes-assets\" {\n  bucket     = \"typednotes-assets\"\n  versioning = true\n  region     = \"fr-par\"\n}"
:::

The two region strings on the right are two chances to be wrong, and nothing relates them. On the left there is one word, and for a whole fleet the check is that every cloud it uses has a region there. That makes the set of legal placements something you compute rather than maintain:

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

# Dependencies you do not declare

This is the part I would put in a real tool first, because it is where the two tools diverge most and it has nothing to do with catching errors.

Some of what you declare does not exist yet: an endpoint the cloud assigns, a password you generate. Here a declaration can hold a recipe for such a value, and the shorthand looks like ordinary string interpolation:

```
resource scaleway secrets "db-password" as pw
  { valueFrom := fromEnv "DB_PASSWORD" }

resource scaleway postgres "main" as db
  { masterUsername := "dbadmin", maxCapacity := 4 }

resource scaleway secrets "db-url"
  { valueFrom := composed
      expr!"postgres://dbadmin:{secretValueOf pw}@{endpointOf db}/main" }
```

The two holes in that string are the two arrows in the graph:

![db-password and postgres main both feed db-url](static/blog/infra-lean/dag.svg)

Three resources, three creates, one apply. The order comes from those arrows: nothing in the file says the password goes first. There is no `depends_on` in the language, because a reference _is_ the dependency, so the graph cannot disagree with the code. Creation is Kahn's algorithm over the edges the references report, and deletion is the same graph transposed, so teardown is the reverse rather than a separate guess.

Arbitrary shapes are fine. Here is a fan-out, a fan-in of three with one redundant edge, and a four-deep chain, all in five secrets:

```
fleet secretGraph in paris where
  provider aws where
    resource secrets "db-base"      as base { valueFrom := fromEnv "DB_PASSWORD" }
    resource secrets "app-a"        as a    { valueFrom := composed expr!"a:{secretValueOf base}" }
    resource secrets "app-b"        as b    { valueFrom := composed expr!"b:{secretValueOf base}" }
    resource secrets "app-combined" as sink { valueFrom := composed
        expr!"{secretValueOf a}|{secretValueOf b}|{secretValueOf base}" }
    resource secrets "app-tail"           { valueFrom := composed expr!"t:{secretValueOf sink}" }
```

Nothing in it mentions ordering, and the plan comes out sorted:

```
would CREATE aws/secrets/db-base
would CREATE aws/secrets/app-a
would CREATE aws/secrets/app-b
would CREATE aws/secrets/app-combined
would CREATE aws/secrets/app-tail
```

Now ask HCL for the same fleet. The exporter has to give up on every one of the five:

:::sideBySide "the fleet, three of the five" "resource secrets \"db-base\" as base\n  { valueFrom := fromEnv \"DB_PASSWORD\" }\n\nresource secrets \"app-a\" as a\n  { valueFrom := composed\n      expr!\"a:{secretValueOf base}\" }\n\nresource secrets \"app-tail\"\n  { valueFrom := composed\n      expr!\"t:{secretValueOf sink}\" }" "main.tf (generated by toHcl)" "resource \"aws_secretsmanager_secret\" \"db-base\" {\n  name   = \"db-base\"\n  # TODO value: a secret's value is never in the\n  # declaration; wire it up in Terraform yourself\n  region = \"eu-west-3\"\n}\n\nresource \"aws_secretsmanager_secret\" \"app-a\" {\n  name   = \"app-a\"\n  # TODO value: a secret's value is never in the\n  # declaration; wire it up in Terraform yourself\n  region = \"eu-west-3\"\n}\n\nresource \"aws_secretsmanager_secret\" \"app-tail\" {\n  name   = \"app-tail\"\n  # TODO value: a secret's value is never in the\n  # declaration; wire it up in Terraform yourself\n  region = \"eu-west-3\"\n}"
:::

Those `# TODO` lines are the exporter refusing to guess, and I think they are the fairest picture of the gap. The names and the regions translate. The graph does not, because in HCL a secret's value is a second resource wired up by hand, and composing one from three others is yours to assemble and yours to order.

The same holds when a dependency crosses clouds. A Scaleway function reading an AWS bucket, and a function placed in a namespace this fleet also creates, come out ordered:

```
$ lake exe cross-cloud

would CREATE aws/object-store/typednotes-assets
would CREATE aws/s3-bucket/typednotes-archive
would CREATE scaleway/object-store/typednotes-assets
would CREATE scaleway/scaleway-function-namespace/typednotes
would CREATE scaleway/scaleway-function/reindex
```

The namespace before the function that lives in it, the bucket before the function that reads it, one apply, two clouds, and the reference is the only thing that says so. HCL gets the same edges when a value flows through an expression, and `depends_on` is for the rest: the dependency is real, nothing in the code carries it, and you have to remember. Here there is no rest. A reference is the only way to name another resource, so the graph cannot be less complete than the code.

## The rule Terraform has, and cannot state once

Terraform handles an unknown filling a field perfectly well. Move the same unknown one position to the left, out of a field and into the question of how many things exist, and it stops:

```
resource "aws_instance" "web" {
  for_each  = toset(aws_subnet.tier[*].id)   # created in this same apply
  subnet_id = each.value
}
```

Terraform cannot say how many instances there will be, so it cannot produce a plan, and it suggests applying part of your configuration first with `-target`. So it has the right rule (an unknown may fill a field, and may not decide how many things exist), but no way to state it once. The rule lives in the core and in the providers, you meet it one attribute at a time, and you meet it after the configuration is written.

Here the rule _is_ the shape of what you are allowed to write. A recipe for a value that does not exist yet has five kinds and no more:

```
inductive Expr (K : ProviderId → Kind → Type) : Type → Type 1 where
  | lit         : α → Expr K α
  | observed    (p : ProviderId) (k : Kind) : K p k → Expr K (ObservedOf k)
  | secretValue (p : ProviderId) : K p .secrets → Expr K String
  | map         : (α → β) → Expr K α → Expr K β
  | ap          : Expr K (α → β) → Expr K α → Expr K β
```

`K` is the parameter carrying the weight. It is this file's own family of resource names, and it appears in the two cases that read a value from somewhere: `observed` and `secretValue` both take a `K p k`. So a recipe can only read from a resource that exists in this file, which is where "a reference cannot dangle" comes from, and it is also what makes the dependency edges derivable: to find them you walk the expression and collect those two nodes.

The interesting part is the case that is missing. There is deliberately no way to say "look at this value, then decide what to build". `map` and `ap` let an unknown value flow into a field, and nothing lets you branch on one, so an unknown value cannot reach the question of how many resources exist. A declaration can hold values it does not know. It can never hold an unknown _number_ of servers, because there is nowhere to write that down.

The practical difference is when you find out. Terraform's `for_each` restriction is a plan-time error about a configuration you already wrote. Here the mistake has no spelling, so a plan is always computable.

# Why dependent types actually help here

"Dependent types" means types that can mention values. Four separate things follow from that here, and only the first is the one people usually have in mind.

*A type can name a value.* A region is not a string, it is a region _of a particular cloud_, and the cloud is in its type: `Region .aws` and `Region .scaleway` are different types, so an AWS region cannot reach a Scaleway call. Same for references. Useful, and the least interesting item here.

*The compiler will run your own checks.* The one with no HCL equivalent, and the whole of it is four lines:

```
@[reducible] def Assert (b : Bool) : Prop := b = true
```

`Assert b` claims that `b` comes out true. Because a type can mention a value, that claim can be _about your configuration_, which is what the instance-size and placement checks above are. Anything a program can compute about a configuration can go there: that the dependency graph has no cycles, that you asked for at most twenty servers, that a name uses only the characters the cloud accepts. Without this you write those as a linter, which is a second implementation of what your configuration means, in another language, run at another time, free to disagree with the first. Here the check is an ordinary function next to the data it checks, and the compiler is what runs it.

The error messages are the payoff, and I did not write any of them:

```
Tactic `decide` proved that the proposition
  Assert (Locality.warsaw.covers keys)
is false
```

That is the compiler quoting my own check back at me, with my own file substituted into it. The same move covers what HCL leaves to a runbook. Terraform stops managing a resource without destroying it via a `removed` block; here it is `forget scaleway queues "old-queue"`, and the compiler owns it: forgetting something you still declare does not compile, one fleet's releases cannot be handed to another because the type carries the fleet, and a release cannot be built by hand because the only constructor is the checked one.

*One table does three jobs.* The table of places maps each place to each cloud's own code. Autocomplete lists the places from it, the compile-time check reads it, and the assertions pin its entries. The list of valid region codes is computed from it rather than typed out again, so the two cannot drift. In HCL that list lives in the provider's Go source, in the documentation, and in your head, and those three disagree.

*A half-built resource is not a value.* A required field has no default and cannot be left unset, so a half-built resource is not an object with nulls in it. It is a function still waiting for an argument, which is why a missing security group reads as a type mismatch about a function. That is the shift I would keep, and it is not "the type system rejects bad configurations". It is that the set of things you can write can be made close to the set of things you could deploy.

One detail I think is load-bearing for anyone trying this: none of it is worth much if a stale table blocks you, and these tables are snapshots of catalogues that grow. `Region.raw` and `InstanceType.raw` take a string on trust, so falling behind a provider costs a more conspicuous spelling rather than a wall. Get that wrong and the first missing region turns the type system into the enemy.

# Being fair about it

What runs: five declarations in sequence, in CI, on all three clouds. Twelve resources on AWS, twelve on Scaleway, ten on Google Cloud, across thirteen of the fourteen kinds. The whole fleet, the same fleet scaled up, the same scaled back down, a version with two resources dropped, then one that declares nothing. After each stage the account must hold exactly what that stage declares, so a resource whose line is gone has to be destroyed rather than abandoned, and a container scaled back to a floor of zero instances has to actually scale back.

What does not: managed Postgres, which takes longer to create than a CI step allows. And plenty of `update` paths, since the ones that run are the ones the ramp moves.

Not everything here is ahead of Terraform either. Deleting a resource from the file destroys it, which Terraform has always done, and getting there took two mistakes worth more than the feature. Something has to remember a resource after its line is gone. I put that record in git first, reasoning that what a fleet manages is intent. It is not. A row appears because a resource *was created*, an event at apply time on whatever machine ran the apply. That is why Terraform's state is remote and not committed, and I had to rediscover it. Then the record turned out to learn about a resource only through an *action*, so one that already existed and already matched was never recorded and could never be destroyed. Types helped with neither: both are questions about what happened, not about what is well-formed.

Nor is any of that what types are for. My favourite failure from the live runs:

```
InvalidParameterValue: Invalid security group description. Valid
descriptions are strings less than 256 characters from the following
set:  a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*
```

The description was "created and destroyed by infra's live test". An apostrophe is not in that set. Since descriptions are constants in the file, that would have failed every apply, for ever. Checking a character set is exactly what the compiler can do, and it does now. But I would never have thought to write it. A type system checks the constraints you know about, and the list of ones you do not is longer.

And some things stay at runtime whatever you do: whether a bucket name is globally unique, whether your quota covers the instance, whether the cloud has caught up with itself.

The scale gap is the real answer to "should you use this". Fourteen resource kinds against Terraform's thousands, three clouds instead of hundreds of providers. No module registry, no state locking, no team workflow. If you need to ship infrastructure this week, use Terraform.

# What two weekends bought

On the original question, iterating faster: yes, and not in the way I expected. The compile-time checks are satisfying but they fire once each. What actually changed the loop is that a broken configuration usually has no spelling, so the file I am editing is either wrong in a way the editor underlines immediately or right in a way that reaches an apply. There is very little middle ground where something plausible sits waiting to fail after the fourth resource. That middle ground is where Terraform time goes.

It also made the AI part work. Two weekends and 18,000 lines is not me typing. Most of it was written in a loop where an agent proposes and the compiler judges, and the reason that loop converges is that the types carry the intent. When I say a reference must be a security group in this fleet, that is not a comment an agent can drift from, it is a constraint the next suggestion has to satisfy. The tighter the types, the less review the code needs, which is the opposite of what type systems are usually sold as costing.

What I would carry into a real tool is narrower than the tool. Make the desired state a value whose type is narrow enough that undeployable configurations are hard to write. Let references be typed indices into the declaration, so ordering is derived and `depends_on` never exists. Let the compiler run your own checks rather than maintaining a linter that can disagree with them. And give every lookup table a deliberately ugly way out. Almost all of the rest of those 18,000 lines are HTTP clients, and they are the part with bugs.

The code is at [github.com/typednotes/infra](https://github.com/typednotes/infra), and `docs/coverage.md` is the honest account of how far it has been run, including the embarrassing parts.
