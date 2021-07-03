---
date: "2021-07-04"
title: Closure traits
description: Closures in Rust implement a set of traits. In some cases there can more than one of these traits that a closure might implement.
---

A pretty interesting conversation took place on a [series of Tweets](https://twitter.com/Slctvdplcate/status/1404843998297018370?s=20) a while back on Rust closures. This was (and still is, although less than before) a confusing topic for me as a Rust newbie. So I was expecting some help from the Rust Twitter community. What I'm about to discuss today comes as a side effect out of that discussion; it wasn't my line of query initially.

My confusion centered around how closures implement the three traits `Fn`, `FnOnce`, and `FnMut`. From a slender look it looks fairly simple:

* You can call closures that implement `Fn` multiple times; you can't use them to mutate anything.
* `FnOnce` closures are callable only once. This is for scenarios where a piece of data could be *moved into* the closure. 
So after the first call, you can't call that closure again since it's been moved during the first call (unless the data type in question implements the `Clone`
trait).
* Closures that mutate the state implement `FnMut`. You can call this type of closure more than one time.

Let's look at an example:

```rust
fn main() {
    // this closure doesn't capture anything 
    let print_ = |film, rating| println!("{}: {}", film, rating);

    let film_ratings = [("Sunset Boulevard", 7), ("The Last", 6), ("Drive", 8)];
    
    for (film, rating) in film_ratings.iter() {
        print_(film, rating);
    }
}
```

The comment says it: this closure doesn't capture anything from the scope. So what trait does it implement?

Let's look at the [docs on `Fn`](https://doc.rust-lang.org/std/ops/trait.Fn.html):

> Fn is implemented automatically by closures which only take immutable references to captured variables or don’t capture anything at all...

So that's it then, right?

Hmm, I have trust issues so let's test that statement on our piece of code. [Jack](https://twitter.com/oconnor663) was kind enough to provide the following code snippet that checks what trait(s) the closure implements.

It uses [*trait objects*](https://doc.rust-lang.org/reference/types/trait-object.html) to create three variables of three types corresponding to each of the traits `Fn`, `FnOnce` and `FnMut`. Then they're assigned to the closure.

 ```rust
fn main() {
    let print_ = |film, rating| println!("{}: {}", film, rating);

    let film_ratings = [("Sunset Boulevard", 7), ("The Last", 6), ("Drive", 8)];

    for (film, rating) in film_ratings.iter() {
        print_(film, rating);
    }

    let _this_works: &dyn FnOnce(_, _) = &print_;
    let _this_works_too: &dyn FnMut(_, _) = &print_;
    let _all_of_these_work: &dyn Fn(_, _) = &print_;
}
```

This code compiles without so much as a warning...

So... the closure implements each trait. The question that arises now is why it ends up implementing all three (put pressure on the phrase "ends up").

I found a [Stack Overflow](https://stackoverflow.com/questions/30177395/when-does-a-closure-implement-fn-fnmut-and-fnonce#30232500) answer that started shedding some light on that question. 

It says that all closures implement `FnOnce`. Why? Because you should be able to call a closure at least once. Closures are functions, and if you can't call a function at least once it's not living up to its name is it?!

So our closure implements `FnOnce`. And according to the docs, since it doesn't capture anything, it also implements `Fn`. That's two out of three. What about the third one `FnMut`?

The following line [in the `Fn` docs](https://doc.rust-lang.org/std/ops/trait.Fn.html) tries to give something away:

> Since both FnMut and FnOnce are supertraits of Fn, any instance of Fn can be used as a parameter where a FnMut or FnOnce is expected.

Wait what? "Supertraits"?

Supertraits are Rust's way of achieving inheritance-like features. You can define a trait that uses some of the functionalities of another trait. The first trait then becomes the "supertrait" (or "parent trait", somewhat mirroring the OOP term "parent class"), and the second trait that depends on the first one becomes a "subtrait".

For a type that implements a subtrait, it also needs to implement its supertrait. That's enough, for now, to understand what's going on with our closures. I might delve into supertraits in another article in the future for my sanity (and clarity on it).

In our closure's case, so another way to explain its behavior is that since it implements `Fn`, it also implements the supertraits `FnOnce` and `FnMut`. This marks another claim made in that Stack Overflow answer:

> A closure |...| ... will automatically implement as many of those [traits] as it can.

Bottomline:
* All closures implement `FnOnce`. This has to happen since all closures can at least be called once.
* Our example closure doesn't capture anything from its sorrounding scope. Because of that, it implements `Fn`.
* In order to implement `Fn`, it also ends up implementing the spuertraits `FnOnce` and `FnMut`.

Oh `FnOnce` is also a supertrait of `Fnmut`...

That's it for today's ramblings. Hope you've found it useful in some way. Thanks for reading!

