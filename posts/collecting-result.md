---
date: "2021-08-08"
title: "On Collecting Result Types in Rust" 
description: The collect method in Rust can create collections from iterators. This post discusses how collecting Result types works.
---

There's a good chance that today's topic being somewhat complex, I will end up explaining some stuff poorly. If it is and leaves something important off the discussion, I apologize beforehand. As someone new to Rust, I'm trying not to get too overwhelmed but at the same time squeezing out all the fun I'm able to. So I'm not exploring too deep for now so that I don't get lost in confusion. For readers who are also fairly new to Rust, I hope this post helps your understanding, maybe piques your interest too, without casting an ominous shadow of fear about the language.

## So... iterators...

Iterators are awesome! They're really handy when you're looping over a sequence of data. Iterators play a huge role in Rust and chances are that even in a trivial Rust program that you've written, there are iterators.

Rust has only one trait that a type needs to implement so that it's possible to iterate over a sequence of data belonging to those types.

Meet the [`Iterator`](https://doc.rust-lang.org/std/iter/trait.Iterator.html) trait:

```rust
pub trait Iterator {
    type Item;
    // Lots of methods below...
}
```

It has a bunch of functionalities. We'll look at only one of these: `collect()`.

Let's look at the signature:

```rust
fn collect<B: FromIterator<Self::Item>>(self) -> B
where
	Self: Sized,
{
    FromIterator::from_iter(self)
}
```

The signature, using [trait bounds](https://doc.rust-lang.org/reference/trait-bounds.html), tells us that this method works on any type `B` provided that it implements the [`FromIterator` trait](https://doc.rust-lang.org/std/iter/trait.FromIterator.html). Under the hood, it calls the `from_iter` function of the `FromIterator`.

This trait only has one method:

```rust
pub trait FromIterator<A> {
    pub fn from_iter<T>(iter: T) -> Self
    where
        T: IntoIterator<Item = A>;
}
```

This method is widely used to "collect" data that we're iterating over into a collection. If you read between the lines, you'll understand that you can use it to convert one collection into another type of collection.

Take the f[ollowing example from the docs](https://doc.rust-lang.org/std/iter/trait.Iterator.html#examples-28) where it iterates over an array (a collection) and turns it into a vector (another type of collection):

```rust
let a = [1, 2, 3];

let doubled: Vec<i32> = a.iter()
                         .map(|&x| x * 2)
                         .collect();

assert_eq!(vec![2, 4, 6], doubled);
```

## Collecting `Result`s

What about collections that are not your run-of-the-mill collections, like arrays and vectors? What about a vector of [`Result` types](https://doc.rust-lang.org/std/result/enum.Result.html)?

> `collect()` can also create instances of types that are not typical collections. For example, a `String` can be built from chars, and an iterator of `Result<T, E>` items can be collected into `Result<Collection<T>, E>`...

According to the docs, you can do that, because `Result` types implement the `FromIterator` trait.

## Down the rabbit hole...

Now let's turn our eyes to the example that's at the heart of today's rant here:

```rust
let results = [Ok(1), Err("nope"), Ok(3), Err("bad")];

let result: Result<Vec<_>, &str> = results.iter().cloned().collect();

// gives us the first error
assert_eq!(Err("nope"), result);

let results = [Ok(1), Ok(3)];

let result: Result<Vec<_>, &str> = results.iter().cloned().collect();

// gives us the list of answers
assert_eq!(Ok(vec![1, 3]), result);
```

Here we have an array of `Result` types, containing both `Ok` and `Err` variants. Using `collect()`, we're *trying* to collect that into a `Result`...

Hmm, that feels.. awkward...

We're not collecting into a vector of `Result`s, but rather into a `Result` that has a `Vector` variant.

So what? It does implement `FromIterator`, so `collect()` should work. Period.

Let's take a step back and try to deduce from what we know so far:

* `Result` is an enum. So a `Result` type can only have one variant at a time, either `Ok`, or `Err`.
* So after the operation on line 2, the `result` variable *should* contain only one variant, either the `Vec` variant (like the second `result` variable in the example ) or the `&str` variant representing the `Err`.

It does end up having only one variant in each case, (the `Ok` variant with the vector, and the `Err` variant with an `&str`), but how is it only yielding the first `Err` variant?

### Searching for answers

The magic happens inside the [implementation of `FromIterator` for `Result` types](https://doc.rust-lang.org/std/result/enum.Result.html#impl-FromIterator%3CResult%3CA%2C%20E%3E%3E).

As I said at the beginning, I'm not going to dive too deep into the mystery behind this magic because that'd be something out of my depth (it is... for now). But we can go pretty far at understanding what's happening under the hood.

Let's take a look at the relevant part of the source code of that implementation:

```rust
impl<A, E, V: FromIterator<A>> FromIterator<Result<A, E>> for Result<V, E> {
    /// Takes each element in the `Iterator`: if it is an `Err`, no further
    /// elements are taken, and the `Err` is returned. Should no `Err` occur, a
    /// container with the values of each `Result` is returned.
    fn from_iter<I: IntoIterator<Item = Result<A, E>>>(iter: I) -> Result<V, E> {
        iter::process_results(iter.into_iter(), |i| i.collect())
    }
}
```

The comments mention the behavior we've just observed in the previous example. At the first encounter of an `Err` variant, it returns that variant and stops collecting. Otherwise, it collects all the values into a container (collection) and returns that instead.

We already know that `FromIterator` has a single method that a type needs to define in order to implement the trait, and that's `from_iter`; every type that implements it does so in different ways. 

For `Result`, we see that it calls another utility function called `process_results` that does the actual job. `process_results` is tailored to work on `Result` type values.

Let's try to break it down as much as we can. Only keep in mind for now that *we're iterating over `Result` types*.

* From the signature, the single argument in `from_iter` has to implement the `IntoIterator` trait. If you scroll back a bit, we called `cloned()` before calling `collect()` on the array. And the r[eturn value type of `cloned()` implements `IntoIterator`](https://doc.rust-lang.org/std/iter/struct.Cloned.html#impl-IntoIterator).
  * `cloned()` creates a new iterator that clones (makes copies of) the underlying elements, i.e. the `Result` types. The clones aren't of type `&T` but type `T`.
* `process_results` takes two arguments: a closure and an iterator. Since `cloned()` yields type `T`, `into_iter()` is used on `iter` so that it's possible to iterate over `T` types (refer to the [docs on the `iter` module](https://doc.rust-lang.org/std/iter/index.html#the-three-forms-of-iteration) if you're confused; it summarizes the types of iteration existing in Rust).

Here's the whole [`process_results` function](https://github.com/rust-lang/rust/blob/6830052c7b87217886324129bffbe096e485d415/library/core/src/iter/adapters/mod.rs#L138-L147):

```rust
fn process_results<I, T, E, F, U>(iter: I, mut f: F) -> Result<U, E>
where
    I: Iterator<Item = Result<T, E>>,
    for<'a> F: FnMut(ResultShunt<'a, I, E>) -> U,
{
    let mut error = Ok(());
    let shunt = ResultShunt { iter, error: &mut error };
    let value = f(shunt);
    error.map(|()| value)
}
```

Looks like the closure works on a type called `ResultShunt`... what the heck is that?

`ResultShunt` is another iterator that wraps the first iterator `iter` passed to the function. [Here's how `ResultShunt` looks like](https://github.com/rust-lang/rust/blob/6830052c7b87217886324129bffbe096e485d415/library/core/src/iter/adapters/mod.rs#L130-L133):

```rust
/// An iterator adapter that produces output as long as the underlying
/// iterator produces `Result::Ok` values.
///
/// If an error is encountered, the iterator stops and the error is
/// stored.
struct ResultShunt<'a, I, E> {
    iter: I,
    error: &'a mut Result<(), E>,
}
```

At this point, let's think through a couple of things:

* The closure is iterating over `ResultShunt` types. That could only mean that `ResultShunt` type implements the `Iterator` trait.
* The doc comments describe the behavior we're investigating.
  * Quite intuitively, the `error` field only cares about the `E` type of a `Result` since it has to stop at the first encounter of an `Err` variant.

The return type of `process_results` is a `Result<U,E>` type, whereas the closure it takes as a parameter returns only the `Ok` value `U`. *That's how the `collect` method in the closure ends up collecting the `Ok` variants if there are no errors.*

We don't need to go over all of [this implementation](https://github.com/rust-lang/rust/blob/6830052c7b87217886324129bffbe096e485d415/library/core/src/iter/adapters/mod.rs#L149-L197). For now, notice the type parameters that show up in the `impl` signature:

```rust
impl<I, T, E> Iterator for ResultShunt<'_, I, E>
where
    I: Iterator<Item = Result<T, E>>,
{
    type Item = T;
...
```

Here `I` is the old iterator over `Result` types. But notice the associated type here:

```rust
...
type Item = T;
...
```

This indicates the *type* of elements being iterated over. So `collect` is actually collecting this `T` type, which already has a `FromIterator`  implementation (in our case, it's an integer). That explains how it yielded the vector containing all `Ok` variants in our example.

The implementation [has a try_fold method](https://github.com/rust-lang/rust/blob/6830052c7b87217886324129bffbe096e485d415/library/core/src/iter/adapters/mod.rs#L168-L183). Again, only the following bit of code is relevant for now:

```rust
Err(e) => {
    *error = Err(e);
    ControlFlow::Break(try { acc })
}
```

We can disregard the feeling of "understanding everything", which is impossible, in favor of how much we've been able to dig up incrementally and make a sense out of. And seeing the above bit of code will make a click sound in your brain...

*  At the encounter of an `Err`, its value is stored in the `error` field of the `ResultShunt` type. Then it just stops iterating, as advertised.
*  `process_results` makes a return with either success values or the error value (the last two lines):

```rust
let value = f(shunt);
error.map(|()| value)
```

This is the last stretch of explanation that we need to wrap this up. Let's break it down:

* Remember the closure signature we observed earlier in `process_results`. It returns the `Ok` value. So the `value` above is just that (a string, integer whatever, but specifically in the example of ours it's an integer).
* Next we're `map`ping over the `error` variable, which is a `Result` type. [This is how `map` works on `Result` types](https://doc.rust-lang.org/std/result/enum.Result.html#method.map):
  * It doesn't touch the `Err` value, but applies the closure to the `Ok` value, transforming the initial `Result` into another. The closure argument is [the "unit" type](https://doc.rust-lang.org/std/primitive.unit.html), meaning it's taking no argument and mapping the `Ok` values to `value`.
* Now if the program encountered an error, the `error` variable already contains it, and the `map` operation above wouldn't matter because it only touches the `Ok` values. That's how we get `Err("nope")`  in the first case of our example. 
* Otherwise, `collect` collects the `Ok` values into a collection, and we're getting `Ok(vec![1, 3])` in the second case of our example.

Phew! 😌 That was a wild ride but we've managed to solve much of the mystery! I'm going to scream with joy into my pillow and then pet my cat... 🎉🎉💪

## Parting words

Thanks for reading up to this point and descent into a bit of madness with me. Feel free to hit me up on [Twitter](https://twitter.com/Slctvdplcate) with any feedback that you might have. I hope you find it useful in some way. 

This article could not have been possible without the following fine people and communities:

* The amazing community of [Togglebit](https://www.twitch.tv/togglebit/about) where I started the initial discussion around the topics.
* [Jake Goulding](https://github.com/shepmaster) for jumping in on the Rust Discord server so quickly and being patient with my questions.
