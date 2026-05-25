+++
title = "Solving tool bloat in Agentic AI at the gateway layer" 
description = "In this article, I discuss how semantic tool filtering at the API gateway cuts token costs and improves tool-selection accuracy."
date = "2026-05-25"
+++

Large tool catalogs, although valuable, mean every request is more expensive, slower, and more likely to produce the wrong result, since each request contains all the tools there are. Every tool definition consumes tokens, irrespective of the query needing that tool or not. 

## On the tool bloat problem

Tool bloat affects an AI application on three fronts: cost, response quality, and latency.

### Cost

Each tool definition in an API request consumes input tokens. A name, a description, and a parameter schema together typically run between 50 and 150 tokens, depending on how detailed the schema is. So an application with, say, 60 tools, may therefore append anywhere from 3,000 to 9,000 tokens to every request, before the user's actual message appears in the payload.

The expense recurs on every call. These tokens lack any informational value relative to the user's intent, which you pay for regardless. At higher throughput, the overhead figure scales linearly. Input token cost is a function of payload size, and tool definitions *are* payload.

The problem compounds in heterogeneous tools. An application might integrate calendar management, email, database querying, code execution, and document retrieval into a single API surface. To say that the application has many tools would be a misperception; rather, it has tools that are almost never all relevant to any single query. For example, if you want to schedule a meeting, you neither need the code execution tools in that request nor the database query tools. Yet all of them appear in the request, and thereby billed.

### Quality

Cost aside, sending irrelevant tools to an LLM actively degrades its ability to designate the right one. A May 2025 paper, [RAG-MCP: Mitigating Prompt Bloat in LLM Tool Selection via Retrieval-Augmented Generation](https://arxiv.org/abs/2505.03275), measured tool-selection accuracy across varying tool pool sizes. It found that naive tool delivery, such as passing all available tools, produced a baseline accuracy of 13.62%. A retrieval-augmented approach that pre-filtered tools by semantic relevance raised that figure to 43.13%, more than tripling accuracy, while cutting prompt token usage by over 50%.

The mechanism behind this degradation is attention dilution. Transformer-based models allocate attention across all tokens in the context window. For a tool list long and mostly irrelevant, the model's attention distributes across entries that bear no relationship to the query. This increases the probability of selecting a tool that is plausible but wrong, one whose description overlaps superficially with the user's intent. It also exacerbates the risk of hallucinated parameter construction for tools the model has misidentified as applicable. Neither failure is easily caught without downstream validation. And both undermine the reliability of the system in ways that are, without careful instrumentation, difficult to attribute.

The issue becomes more concerning with tool descriptions that share vocabulary. For example, two tools may both respond to queries involving search, and an overloaded context makes the distinction harder for the model to maintain with accuracy.

### Latency

Larger inputs take longer to process. Take note of the fact that the model must attend to every token before generating output. So time-to-first-token—the interval between dispatching a request and receiving the start of a response—scales with input size. For interactive applications where a user waits for a response, this delay is user-visible. Excess tokens in the tool list contribute directly to it.

The latency effect is less acute than the cost or quality effects at moderate tool counts. It becomes significant, however, in high-volume, latency-sensitive environments, like real-time copilots, or systems where multiple LLM calls constitute a single user interaction. In those contexts, every nonessential token in the input is a compounding liability.

We can observe a common origin in these problems: a static tools array, while user intent remains specific. No query in a multi-domain agentic application requires access to every tool the application exposes. How to determine, per request and at runtime, the relevant tools, is the problem I will try to address in this post.

## The naive solutions and why they don't scale

So how to tackle these complications? The usual approaches, although natural and addressing the issues in some measure, don’t resolve the elementary problem, nor do they scale.

### Curating tools per-endpoint

Instinctively, you may want to curate the tools array manually: define which tools each endpoint receives and exclude everything else. It’s a sound strategy for narrow, well-defined endpoints with stable, predictable intent.

But what about an endpoint that serves varied intent, the architecture that agentic applications veer toward? In the cases of, for example, a general-purpose assistant or conversational interface, the tools any given query might require alters with the query itself. Manual curation therefore, in that context, is not as much a configuration decision you make once as it is a system upkeep. For every new tool now requires a review of every endpoint's curated list. Each modification to application behavior carries with it risks of discrepancies between what the endpoint receives and the query’s actual requirements.

We also observe a subtler failure where, by severely constraining an endpoint's tools, you unobtrusively debase capability. A tool mistakenly selected might result in a visible error, whereas a missing tool produces a response that simply does not invoke it, the latter being considerably harder to detect and diagnose.

### Application-level filtering

In a more dynamic approach, the application discharges the filtering at runtime. Before assembling the request, the application inspects the query, ascertains relevance, and duly constructs the tools array.

However, every team building on the platform must implement this logic individually, with no shared standard for determining relevance. As a result, you have a patchwork of implementations, each maintained separately and susceptible to drift.

Application-level filtering also conjoins tool selection strategy with business logic. At one point, and recurringly, the filtering approach needs to change, because, for example, the tool catalog has grown or relevance thresholds require calibration. Now you must coordinate that change across every service that has implemented its own version. The affiliated cost will be prohibitive if your platform serves many API consumers.

### Sending everything

The default, and by far the most common strategy, is to dispatch the full tools array on every request. It suffices for small tool sets, requiring no additional engineering,  maintenance, or coordination.

Its inadequacy at scale, however, follows from the previous section. Moreover, there is an additional liability in that applications that default to sending everything implicitly treat tool selection as the model's problem. Reliability remains stable for a few tools, but degrades as the number of tools increases. The application, to make matters worse, lacks a method to detect this. Erroneous tool invocations and degraded response quality appear as downstream symptoms, often misattributed to other determinants. 

## Tool selection as retrieval

Relevance is a relationship between a tool and a query, one that only materializes at runtime. So if relevance is a relationship between two pieces of text, we can express it as a geometric relationship between vectors. A text embedding model converts a string into a high-dimensional vector, where position in that space encodes meaning. Semantically related strings produce vectors that point in similar directions, and the cosine of the angle between them (cosine similarity) yields a value between \-1 and 1 that quantifies that alignment.

So to apply this to tool selection, a practical set of steps would be as follows: 

* Embed the user's query.  
* Embed each tool as a concatenation of its name and description.  
* Compute cosine similarity between the query vector and each tool vector, and pass only the highest-scoring tools to the model. 

Thus, not unlike RAG systems, semantic tool filtering retrieves only the tools the query actually needs, provided accurate, descriptive tool definitions.

## Why the gateway is the right place to solve this

So where does this *semantic filtering* actually execute? It might do so in the application, as discussed, but that reintroduces the foregoing coupling and fragmentation problems. 

The correct answer is the API gateway.

The gateway, located between the application and the LLM, can intercept the tools array, perform semantic filtering, rewrite the payload, and forward the optimal request to the model. 

This placement confers three distinct advantages. First, you define the filtering logic once; it applies uniformly across every API on the platform, precluding individual reimplementations across teams, services, and endpoints. Second, it is transparent to the application. Third benefit is unified governance; platform engineers can enforce it as infrastructure policy, as opposed to reliance on individual teams for consistent implementation.

The WSO2 AI Gateway in the WSO2 API Platform implements this motif through the [Semantic Tool Filtering policy, available through the WSO2 Policy Hub](https://wso2.com/api-platform/policy-hub/policies/semantic-tool-filtering). The policy intercepts any OpenAI-compatible request, applies vector-similarity filtering to the tools array, and rewrites the payload before it gets to the model, all of it in an orderly fashion within the gateway's request pipeline. You do not have to alter anything upstream or downstream.

## How the Semantic Tool Filtering policy works

### Step 1: Extract the query

The policy reads the user's latest message from the request body using a configurable `JSONPath` expression. The default, `$.messages[-1].content`, targets the last message in an OpenAI-style payload; but you can configure that to accommodate any request schema. Alternatively, if not structured JSON but embedded in a text, the policy extracts the query from a `<userq>` tag.

### Step 2: Extract tool definitions

A second `JSONPath` expression extracts the tools array. The policy accommodates three common schemas: 

* `$.tools` for a flat array  
* `$.tools[*].function` for OpenAI and Mistral-style function wrappers where each tool is an object with a nested `function` field  
* `$.tools[0].function_declarations` for Gemini-style payloads. 

For text-based payloads, the policy reads `<toolname>` and `<tooldescription>` tags from the request body and strips them from the forwarded payload afterward.

### Step 3: Generate embeddings

The policy embeds the user query and each tool, represented as `"<name>: <description>"`, using a configured embedding provider, namely, OpenAI, Mistral, and Azure OpenAI. You can configure each of these in the gateway's `config.toml` with an endpoint, model name, and API key. 

Tool embeddings are cached using an LRU cache keyed by a SHA-256 hash of the provider, model, and tool description. That means tool embeddings are computed once and reused across requests. Only the user query embedding is computed fresh on each call.

### Step 4: Score and filter

Cosine similarity scores the query vector against each tool vector. The policy then applies one of two selection modes:

| Mode | Behavior | Usage |
| ----- | ----- | ----- |
| **`By rank`** | Retains the top-K tools by score; the number of most relevant tools to include is configurable, the default being `5` | When a predictable, bounded tool count matters: cost control, latency targets |
| **`By threshold`** | Retains all tools scoring at or above a similarity threshold between `0.0` and `1.0`, the default being `0.7` | When tool count should adapt to query specificity; a precise query might return one tool but an ambiguous one several |

### Step 5: Rewrite and forward

The original tools array is replaced in-place with the filtered subset. The amended request proceeds to the LLM. From the model's perspective, these were the only tools it was ever given.

### The Embedding cache

The process described above calls an external embedding service on every request, or it would, without the built-in LRU cache. The cache makes the policy viable at production throughput, so let’s briefly discuss that.

We can make a simple observation: tool names and descriptions remain static between requests, unlike user queries. So tool embeddings are computed once and stored; subsequent requests for the same tool retrieve the cached vector. Only the query embedding—the variable part—is computed anew on each request. At steady state, the cost of an embedding call per request reduces to only the cost of embedding a single short query string.

Cache keys are computed as a SHA-256 hash of three components: the embedding provider, the model name, and the tool description. The policy binds the provider and model to the key to take into account vectors produced by different models; they occupy different semantic spaces and hence are incompatible. In case of a different embedding model, existing cache entries will not match the new key format and will not be served, precluding stale or incompatible vectors from contaminating the filtered results.

Eviction follows an LRU-like strategy across APIs and tools within each API. Upon reaching capacity, the least recently used entries are evicted first in the cache. And when caching a new batch of tools, the policy calculates available slots before writing and skips tools that would not fit. It thus avoids evictions of recently used entries to accommodate a large batch that may itself see little reuse.

### Format flexibility

The majority of LLM API interactions involve JSON payloads, but not all. So the policy offers another option for frameworks that embed tool definitions differently.

Some frameworks inject tool definitions directly into the text of a system or user message. The policy accommodates this through a text-tag format. Tool definitions are marked with `<toolname>` and `<tooldescription>` tags; the user query is marked with a `<userq>` tag—for example:

```
<toolname\>get\_weather\</toolname\>  
<tooldescription\>Get current weather and 7-day forecast for a location\</tooldescription\>  
<userq\>I'm planning a corporate retreat in Denver next weekend\</userq\>
```

You use the boolean parameters `userQueryIsJson` and `toolsIsJson` to specify the extraction mode the policy applies to each component independently. This means the two components need not share a format. A request can carry the user query as a JSON field while embedding tool definitions in text tags, or vice versa. The `JSONPath` parameters remain active for whichever component uses JSON extraction; for text-based components, those paths point to the field containing the raw text from which the policy extracts the tags.

Thus the policy does not prescribe a payload structure but adapts to the format the application already produces.

### Choosing a selection mode

How the policy behaves depends on the selection mode you opt for.

The primary benefit of `By Rank` is predictability. Token consumption for each request is bounded and thereby no room for surprises at high throughput.

However, rank is a relative measure. The top five tools can all score poorly against the query, because the query is ambiguous, the tool descriptions sparse, or the user's intent genuinely spans multiple domains. `By Rank` still dispatches five tools, including ones marginally relevant at best. The mode merely returns the best available options within the defined count.

In `By Threshold`, the tool count adapts to the query: a precise, well-scoped request may return a single tool; a broad or ambiguous one may return several. It means the forwarded context reflects the actual semantic proximity between the query and the tool catalog, as opposed to a fixed count that may over- or under-represent relevance.

The tradeoff is that you need to calibrate deliberately. A lenient threshold value offers little reduction from the unfiltered baseline. A higher value might drop tools that are legitimately applicable but described in vocabulary that diverges from the query's phrasing. The right value depends on the semantic density of the tool catalog, the consistency of its descriptions, and the variability of user query phrasing. Although `0.7` is a reasonable starting point, there is no default universal, and we suggest that production deployments perform empirical tuning against representative query samples.

### The role of tool descriptions

Across both modes, filtering quality is contingent on description quality, a point I’ve made earlier. Cosine similarity measures the angular distance between two embedding vectors; but it cannot recompense for descriptions that fail to encode what a tool actually does. A sound description produces a precise vector that scores strongly against queries about the sought property or objective and weakly against everything else.

## Wrapping up

Tool bloat can discreetly become a principal concern as applications accumulate capabilities, and compounds across cost, quality, and latency simultaneously. By dint of addressing it at the gateway, you can dispense the fix universally without affecting application code.


