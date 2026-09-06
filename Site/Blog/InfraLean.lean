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

It is not production software, and I will get to why at the end. What I want to write about is the idea that made the two weekends worth spending, because it generalises past this project.

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

Two different things are happening in those compile-time rows, and the difference is worth holding on to. In the first four, the mistake has no spelling. There is no way to write the broken configuration down, so nothing has to be checked. In the next two you _can_ write it down, and the compiler decides by running a small function over what you wrote.

(Lean people call the second kind an elaboration-time check, because it happens while the file is being turned into a program. For the rest of this post it is just compilation.)

The last two rows are the honest half of any "types catch bugs" claim. Writing them down first is what kept the rest from turning into marketing.

They are also why the title of this post is hedged. Compiling is not a promise that the apply will succeed. It is a promise about which kinds of failure are still on the table when you get there.

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

Three consequences, and none of them is a check that runs later. Leaving the field out does not compile. Naming a group that is not in this file does not compile, because the only things of that type are the groups declared above it. Passing a bucket does not compile either, because a reference carries the cloud and the kind of resource in its type, and a bucket is not a security group. That last one is the case a string could never catch: both resources are in AWS, both exist, and the names look alike.

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

One spec, two clouds. A spec belongs to a kind of resource and never to a cloud, so the cloud only shows up when it is time to apply. When you want something only one cloud has, you reach for a provider-local kind, and the loss of portability becomes visible in what you wrote:

```
resource aws s3Bucket "typednotes-archive" as archive
  { objectLock := true }
```

When a cloud does not implement a kind, there is simply no name for it, so nothing can refer to it:

```
#guard crossCloud.keys.count .aws .postgres  = 0
#guard crossCloud.keys.count .scaleway .s3Bucket = 0
```

`#guard` there is a compile-time assertion: the compiler evaluates the line and refuses to build if it is not true. The repo has 348 of them and they serve as its test suite, so everything I quote below is checked on every build.

## t3.32xlarge

In HCL, `instance_type = "t3.nanoo"` is a string. Plan succeeds. Apply fails with `InvalidParameterValue`, after the security group it references has already been created.

An instance type is not really a string. AWS names it family dot size, and both halves come from small closed sets:

```
def InstanceType.of (f : InstanceFamily) (s : InstanceSize)
    (_h : Assert (f.sizes.contains s) := by decide) : InstanceType :=
  ⟨s!"{f.code}.{s.code}"⟩
```

That third argument is the check, and you never write it. It claims `f.sizes.contains s`, the family comes in that size, and `by decide` tells the compiler to settle the claim by computing it. When the claim is true the compiler fills the argument in silently. When it is false there is nothing to fill it with, so `InstanceType.of .t3 .xlarge32` gives:

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

Say you want a secret holding a connection string, built from a password you generate and an endpoint the cloud assigns. Neither value exists when you write the file. In Terraform this works:

```
resource "random_password" "db" { length = 32 }

resource "aws_db_instance" "main" {
  username = "dbadmin"
  password = random_password.db.result
}

resource "aws_secretsmanager_secret_version" "url" {
  secret_id     = aws_secretsmanager_secret.url.id
  secret_string = format("postgres://dbadmin:%s@%s/main",
                         random_password.db.result,
                         aws_db_instance.main.endpoint)
}
```

Terraform prints `(known after apply)` for both, works out the order from the references, and fills the string in as it goes. One apply, no pasting.

Now move the same unknown one position to the left, out of a field and into the question of how many things exist:

```
resource "aws_instance" "web" {
  for_each  = toset(aws_subnet.tier[*].id)   # subnets created in this same apply
  subnet_id = each.value
}
```

That one stops at plan time. Terraform cannot say how many instances there will be, so it cannot produce a plan at all, and the error suggests applying part of your configuration first with `-target` and then applying the rest.

So Terraform already has the right rule: an unknown value may flow into a field, and may not decide how many things exist. What it does not have is a way to say that rule once. It lives in the core and in the providers, you meet it one attribute at a time, and you meet it after the configuration is written.

Here the rule is the shape of the value you are allowed to write. A declaration can hold a recipe for something that does not exist yet, and there are five kinds of recipe:

```
inductive Expr (K : ProviderId → Kind → Type) : Type → Type 1 where
  | lit         : α → Expr K α
  | observed    (p : ProviderId) (k : Kind) : K p k → Expr K (ObservedOf k)
  | secretValue (p : ProviderId) : K p .secrets → Expr K String
  | map         : (α → β) → Expr K α → Expr K β
  | ap          : Expr K (α → β) → Expr K α → Expr K β
```

`lit` is a value you already have. `observed` is something the cloud will report once the resource exists. `secretValue` is the value of one of this file's secrets. `map` and `ap` combine recipes into bigger recipes.

`K` is the parameter that carries the weight, so it is worth reading rather than skipping. It is this file's own family of resource names, sorted by cloud and by kind, and it turns up in the two cases that read a value from somewhere: `observed` and `secretValue` both take a `K p k`. The only thing a recipe can read from is a resource that exists in this file. That is where "a reference cannot dangle" comes from, and it is the reason this little language is parameterised by the file it belongs to instead of standing on its own.

(Two details for people who care: `α` and `β` are ordinary type variables, left implicit here. And the result is `Type 1` rather than `Type` because `map` and `ap` quantify over an intermediate type, which is a real consequence rather than a decoration: it is why every resource spec in the library has to be universe-polymorphic.)

The interesting part is the case that is missing. There is deliberately no way to say "look at this value, then decide what to build".

That is Terraform's rule again, but as a property of the language rather than a check. `map` and `ap` let an unknown value flow into a field, which is the connection string above. Nothing lets you branch on one, so an unknown value cannot reach the question of how many resources exist. A declaration can hold three values it does not know. It can never hold an unknown _number_ of servers, because there is no way to write that down.

The practical difference is when you find out. Terraform's `for_each` restriction is a plan-time error about the configuration you already wrote. Here the equivalent mistake has no spelling, so the plan is always computable, and "plan" stays a phase you can look at instead of a thing that sometimes cannot be produced.

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

That expands to exactly the recipe you would have assembled by hand. Nothing is added to the language, and the restriction is not relaxed, only hidden: there is still no way to branch on a value you do not have, because the syntax gives you nowhere to put a branch.

The two holes in that string are the two arrows in the graph:

![db-password and postgres main both feed db-url](static/blog/infra-lean/dag.svg)

Three resources, three creates, one apply, same as Terraform manages for the same case. The order comes from those arrows rather than from anything I wrote down: nothing in the file says the password comes first.

# What deleting a line does, and what it should do

One decision here does more work than the rest. Your declaration is not a list of resources. It is a verdict on every resource it knows the name of, and the names are a fixed, known set. Each one is either "should exist, like this", or "should not exist", or "not my business". You cannot leave one out, because leaving something out is not a thing the shape allows.

Writing `.absent` is what turns "I no longer want this" into a delete, and it is the path to use.

There is a gap here I should be straight about, because it is the one place where what shipped is not what was designed. Deleting a resource from the file does not delete it from the cloud. Once the line is gone the resource is not one of the names any more, so nothing can refer to it, and whatever is running stays running.

That is not the intent. The type has a switch for it: alongside the per-resource verdicts there is a single verdict on everything else, where "should not exist" means a closed world and anything undeclared gets collected. Nothing reads that switch. The `fleet` command hardcodes it to "not my business", so it cannot even be flipped from the declaration, and `docs/coverage.md` lists it as the known defect most likely to matter.

It is also not a five-minute fix, for a reason worth seeing. Membership is defined by the set of names, and deleting a line deletes the name. After that, "I used to manage this and changed my mind" and "this was never mine" are the same situation, and telling them apart needs a memory of what you managed before. The one candidate is the state cache, and the cache is deliberately not allowed to answer that question: it skips any name the current declaration does not mention, precisely so that pointing this at a populated account does not produce a screen of proposed deletions. That is the property that keeps other people's resources out of reach, and it is the same property that loses the information a closed world needs. The two goals are in tension, and the current code resolves the tension in favour of not touching things it was never given.

# Why dependent types actually help here

"Dependent types" means types that can mention values. Four separate things follow from that here, and only the first is the one people usually have in mind.

*A type can name a value.* A region is not a string, it is a region _of a particular cloud_, and the cloud is part of its type. `Region .aws` and `Region .scaleway` are two different types, so an AWS region cannot end up in a Scaleway call. Same for references: the cloud and the kind of resource are part of what a reference is, not a convention about how it is named. Useful, and the least interesting item here.

*The compiler will run your own checks.* This is the one with no HCL equivalent, and it is four lines:

```
@[reducible] def Assert (b : Bool) : Prop := b = true
```

`Assert b` is the claim that `b` comes out true. Because a type can mention a value, that claim can be _about your configuration_, and it can be attached to a function as an argument nobody types: `(h : Assert (f.sizes.contains s) := by decide)`. The compiler computes `b` and either fills the argument in or stops the build.

Anything a program can compute about a configuration can go there. That the dependency graph has no cycles. That you asked for at most twenty servers. That a name uses only the characters the cloud accepts. That every cloud you use has a region where you put it. Without this you write those as a linter, which means a second implementation of what your configuration means, in a different language, run at a different time, free to disagree with the first. Here the check is an ordinary function next to the data it checks, and the thing that runs it is the compiler.

The error messages are the payoff, and I did not write any of them:

```
Tactic `decide` proved that the proposition
  Assert (Locality.warsaw.covers keys)
is false
```

That is the compiler quoting my own check back at me, with my own file substituted into it.

*One table does three jobs.* The table of places maps each place to each cloud's own code for it. Your editor's autocomplete lists the places from it. The compile-time check reads it. The assertions pin its entries. The list of valid region codes is computed from it rather than typed out a second time, so the two cannot drift apart. In HCL that list lives in the provider's Go source, in the documentation, and in your head, and those three disagree.

*A half-built resource is not a value.* A required field has no default and cannot be left unset, so a half-built resource is not an object with nulls in it. It is a function still waiting for an argument, which is why the error for a missing security group was a type mismatch about a function. That is the shift I would keep, and it is not "the type system rejects bad configurations". It is that the set of things you can even write can be made close to the set of things you could actually deploy.

One more detail, which I think is load-bearing for anyone trying this. None of it is worth much if a stale table blocks you, and these tables are snapshots of catalogues that grow. So `Region.raw` and `InstanceType.raw` take a string on trust. A table falling behind its provider costs the author a more conspicuous spelling, never a wall. Get that wrong and the first missing region turns the type system into the enemy.

# Being fair about it

The repo keeps a document whose only job is to say how far this has actually been run, and it is blunter than anything I would write in a post. Correctness of request signing is established. Correctness of what is being signed mostly is not. A large part of the endpoint code has never been called against a real account. Three of the fourteen kinds cannot be live-tested at all: a Postgres instance takes five to fifteen minutes to create and as long to delete, an EC2 instance needs a region-specific image id that rots, and a serverless function needs deployable code there is no public equivalent to pull.

And none of the above is what types are for. My favourite failure from the first live runs is this one:

```
InvalidParameterValue: Invalid security group description. Valid
descriptions are strings less than 256 characters from the following
set:  a-zA-Z0-9. _-:/()#,@[]+=&;{}!$*
```

The description was "created and destroyed by infra's live test". An apostrophe is not in that set. Since descriptions are constants sitting in the file, that one would have failed every apply, for ever. Checking a character set is exactly the sort of thing the compiler can do for you, and it does now. But I would never have thought to write it. A type system checks the constraints you know about. The list of constraints you do not know about is longer, and you find it by calling the API.

Then there is the tier that stays at runtime no matter what: whether a bucket name is globally unique, whether your quota covers the instance, whether the cloud has caught up with itself yet. No amount of indexing touches those.

The scale gap is the real answer to "should you use this". Fourteen resource kinds against Terraform's thousands, across three clouds instead of hundreds of providers. No module registry, no state locking, no team workflow. If you need to ship infrastructure this week, use Terraform.

What I would carry into a real tool is narrower than the tool itself. Make the desired state a value whose type is narrow enough that configurations you could not deploy are hard to write down. Let the compiler run your own checks over it, so you are not maintaining a separate linter that can disagree. Give every lookup table a deliberately ugly way out. The remaining 15,000 lines are HTTP clients, and they are the part that has bugs.

The code is at [github.com/typednotes/infra](https://github.com/typednotes/infra), and `docs/coverage.md` is the honest account of how far it has been run, including the embarrassing parts.
