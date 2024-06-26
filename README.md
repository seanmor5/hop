# Hop

Hop is a tiny web crawling framework for Elixir.

## Installation

Coming soon.

## Introduction

Hop's goal is to be simple and extensible, while still providing enough guardrails to get up and running quickly. Hop implements a simple, depth-limited, breadth-first crawler - and keeps track of already visited URLs for you. It also provides several utility functions for implementing crawlers with best practices.

You can crawl a webpage with just a few lines of code with Hop:

```elixir
url
|> Hop.new()
|> Hop.stream()
|> Enum.each(fn {url, _response, _state} ->
  IO.puts("Visited: #{url}")
end)
```

By default, Hop will perform a single-host, breadth-first crawl of all of the pages on the website. The `stream/2` execution function will return a stream of `{url, response, state}` tuples for each successfully visited page in the crawl. This is designed to make it easy to perform caching, extract items from a page, or do whatever other work deemed necessary.

The defaults are designed to get you up and running quickly; however, the power comes in with Hop's simple extensibility. Hop provides extensibility by allowing you to customize your crawler's behavior at 3 different steps:

  1. Prefetch
  2. Fetch
  3. Next

### Prefetch

The prefetch stage is a pre-request stage typically used for request validation. By default, during the prefetch stage, Hop will:

  1. Check that the URL has a populated scheme and host

  2. Check that the URL's scheme is acceptable. Default accepted schemes
  are http and https. This prevents Hop from attempting to visit `tel:`,
  `email:` and other links with non-HTTP schemes.

  3. Check that the host is actually valid, using `:inet.gethostbyname`

  4. Check that the host is an acceptable host to visit, e.g. not outside of
  the host the crawl started on.

  5. Perform a HEAD request to check that the content-length does not exceed
  the maximum specified content length and to check that the content-type matches
  one of the acceptable mime-types. This is useful for preventing Hop from spending
  time downloading large files you don't care about.

Most users should stick to using Hop's default pre-request logic. If you want to customize the behavior; however, you can pass your own `prefetch/3` function:

```elixir
url
|> Hop.new()
|> Hop.prefetch(fn url, _state, _opts -> {:ok, url} end)
|> Hop.stream()
|> Enum.each(fn {url, _response, _state} ->
  IO.puts("Visited: #{url}")
end)
```

This simple example performs no validation, and forwards all URLs to the fetch stage.

Your custom `prefetch/3` function should be an arity-3 function which takes a URL, the current Crawl state, and the current Hop's configuration options as input and returns `{:ok, url}` or an error value. Any non-`{:ok, url}` values will be ignored during fetch.

### Fetch

The fetch stage performs the actual requests during your crawl. By default, Hop uses Req and performs a GET request without retries on each URL. In other words, the default fetch function in Hop is:

```elixir
def fetch(url, state, opts) do
  req_options = opts[:req_options]

  with {:ok, response} <- Req.get(url, req_options) do
    {:ok, response, state}
  end
end
```

Notice you can customize the `Req` request options by passing `:req_options` as a part of your Hop's configuration.

This is simple and acceptable for many cases; however, certain applications require more advanced setups and customization options. For example, you might want to configure your fetch to proxy requests through Puppeteer to render javascript. You can do this easily:

```elixir
def custom_fetch(url, state, _opts) do
  # url to proxy that renders a page with puppeteer
  proxy_url = "http://localhost:3000/render"

  with {:ok, response} <- Req.post(url, json: %{url: url}) do
    {:ok, response, state}
  end
end
```

### Next

The next function dictates the next links to be crawled during execution. It takes as input the current URL, the response from fetch, the current state, and configuration options. By default, Hop returns all links on the current page as next in the queue to be crawled. You can customize this behaviour by implementing your own `next/4` function:

```elixir
def custom_next(url, response, state, _opts) do
  links =
    url
    |> Hop.fetch_links(response)
    |> Enum.reject(&String.contains?(&1, "wp-uploads"))

  {:ok, links, state}
end
```

This simple example ignores all URLs that contain `wp-uploads`. Hop provides a convenience `fetch_links/2` to fetch all of the absolute URLs on a webpage. This just uses Floki under-the-hood.

## License

TODO