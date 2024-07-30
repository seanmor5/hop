defmodule Hop do
  @moduledoc """
  Hop is a tiny web crawling framework for Elixir.

  Hop's goal is to be simple and extensible, while still providing
  enough guardrails to get up and running quickly. Hop implements a simple,
  depth-limited, breadth-first crawler - and keeps track of already visited
  URLs for you. It also provides several utility functions for implementing
  crawlers with best practices.

  You can crawl a webpage with just a few lines of code with Hop:

      url
      |> Hop.new()
      |> Hop.stream()
      |> Enum.each(fn {url, _response, _state} ->
        IO.puts("Visited: \#{url}")
      end)


  By default, Hop will perform a single-host, breadth-first crawl of all of the
  pages on the website. The `stream/2` execution function will return a stream of
  `{url, response, state}` tuples for each successfully visited page in the crawl.
  This is designed to make it easy to perform caching, extract items from a page,
  or do whatever other work deemed necessary.

  The defaults are designed to get you up and running quickly; however, the power comes
  in with Hop's simple extensibility. Hop provides extensibility by allowing you to
  customize your crawler's behavior at 3 different steps:

    1. Prefetch
    2. Fetch
    3. Next

  ### Prefetch

  The prefetch stage is a pre-request stage typically used for request validation.
  By default, during the prefetch stage, Hop will:

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

  Most users should stick to using Hop's default pre-request logic. If you want to
  customize the behavior; however, you can pass your own `prefetch/3` function:

      url
      |> Hop.new()
      |> Hop.prefetch(fn url, _state, _opts -> {:ok, url} end)
      |> Hop.stream()
      |> Enum.each(fn {url, _response, _state} ->
        IO.puts("Visited: \#{url}")
      end)

  This simple example performs no validation, and forwards all URLs to the fetch stage.

  Your custom `prefetch/3` function should be an arity-3 function which takes a URL, the
  current Crawl state, and the current Hop's configuration options as input and returns
  `{:ok, url}` or an error value. Any none `{:ok, url}` values will be ignored during fetch.

  ### Fetch

  The fetch stage performs the actual requests during your crawl. By default, Hop
  uses Req and performs a GET request without retries on each URL. In other words,
  the default fetch function in Hop is:

      def fetch(url, state, opts) do
        req_options = opts[:req_options]

        with {:ok, response} <- Req.get(url, req_options) do
          {:ok, response, state}
        end
      end

  Notice you can customize the `Req` request options by passing `:req_options` as
  a part of your Hop's configuration.

  This is simple and acceptable for many cases; however, certain applications require
  more advanced setups and customization options. For example, you might want to configure
  your fetch to proxy requests through Puppeteer to render javascript. You can do this easily:

      def custom_fetch(url, state, _opts) do
        # url to proxy that renders a page with puppeteer
        proxy_url = "http://localhost:3000/render"

        with {:ok, response} <- Req.post(url, json: %{url: url}) do
          {:ok, response, state}
        end
      end

  ### Next

  The next function dictates the next links to be crawled during execution.
  It takes as input the current URL, the response from fetch, the current state,
  and configuration options. By default, Hop returns all links on the current page
  as next in the queue to be crawled. You can customize this behaviour by implementing
  your own `next/4` function:

      def custom_next(url, response, state, _opts) do
        links =
          url
          |> Hop.fetch_links(response)
          |> Enum.reject(&String.contains?(&1, "wp-uploads"))

        {:ok, links, state}
      end

  This simple example ignores all URLs that contain `wp-uploads`. Hop provides a convenience
  `fetch_links/2` to fetch all of the absolute URLs on a webpage. This just uses Floki under-the-hood. 
  """
  @default_max_depth 5
  @default_max_content_length 1_000_000_000
  @default_accepted_schemes ["http", "https"]
  @default_accepted_mime_types [
    "text/html",
    "text/plain",
    "application/xhtml+xml",
    "application/xml",
    "application/rss+xml",
    "application/atom+xml"
  ]

  @config_keys [
    :max_depth,
    :max_content_length,
    :accepted_mime_types,
    :accepted_schemes,
    :crawl_query?,
    :crawl_fragment?,
    :req_options
  ]

  alias __MODULE__, as: Hop

  defstruct [:url, :prefetch, :fetch, :next, :config]

  ## State

  defmodule State do
    @moduledoc false

    defstruct [
      :last_crawled_url,
      depth: 0,
      visited: MapSet.new(),
      hostnames: MapSet.new(),
      state: %{}
    ]
  end

  ## Builder

  @doc """
  Creates a new Hop starting at the given URL(s).
  """
  @doc type: :builder
  def new(url, opts \\ []) when is_binary(url) or is_list(url) do
    opts = Keyword.validate!(opts, [:prefetch, :fetch, :next, :config])

    opts
    |> Enum.into(default_hop(url))
    |> then(&struct(Hop, &1))
  end

  defp default_hop(url) do
    %{
      url: url,
      prefetch: &default_prefetch/3,
      fetch: &default_fetch/3,
      next: &default_next/4,
      config: Enum.map(@config_keys, fn key -> {key, default_config(key)} end)
    }
  end

  defp default_prefetch(url, state, opts) do
    {:ok, url}
    |> validate_hostname(state, opts)
    |> validate_scheme(state, opts)
    |> validate_content(state, opts)
  end

  defp default_fetch(url, state, opts) do
    req_options = opts[:req_options]

    with {:ok, response} <- Req.get(url, req_options) do
      {:ok, response, state}
    end
  end

  defp default_next(url, %{body: body}, state, opts) do
    links =
      fetch_links(url, body,
        crawl_query?: opts[:crawl_query?],
        crawl_fragment?: opts[:crawl_fragment?]
      )

    {:ok, links, state}
  end

  @doc """
  Sets this hop's fetch function.

  The fetch function is what is used to actually make requests. By
  default, Hop uses `&Req.get(&1, retry: false)`. If you want to
  change the options passed to Req, you can do so here.

  Your `fetch/1` function should accept a URL and return a tuple of
  `{:ok, response}`.

  Note that Hop is HTTP-Client agnostic. The `response` object is
  simply forwarded to the `process` function. This means you can
  swap for a new HTTP-client if necessary.
  """
  @doc type: :builder
  def fetch(%Hop{} = hop, fetch) when is_function(fetch, 3) do
    %{hop | fetch: fetch}
  end

  @doc """
  Sets this hop's prefetch function.

  The prefetch function is essentially meant to be a pre-request
  validation stage. This could serve the purpose of validating that
  a given URL is valid, that the content is valid (e.g. via a HEAD
  request), that the request matches a site's Robots.txt, etc.
  Most clients will want to leave this as-is.
  """
  @doc type: :builder
  def prefetch(%Hop{} = hop, prefetch) when is_function(prefetch, 3) do
    %{hop | prefetch: prefetch}
  end

  @doc """
  Sets this hop's next function.

  The next function dictates which links are meant to be crawled
  next after the current page.
  """
  @doc type: :builder
  def next(%Hop{} = hop, next) when is_function(next, 4) do
    %{hop | next: next}
  end

  ## Configuration

  @doc """
  Puts the given configuration value for the given key
  in the given hop.
  """
  @doc type: :configuration
  def put_config(%Hop{config: config} = hop, key, value) do
    %{hop | config: Keyword.put(config, key, value)}
  end

  @doc """
  Returns the current configuration value set for the given
  key in the Hop.
  """
  @doc type: :configuration
  def config(%Hop{config: config}, key) do
    config[key] || default_config(key)
  end

  @doc false
  def default_config(key)
  def default_config(:max_depth), do: @default_max_depth
  def default_config(:max_content_length), do: @default_max_content_length
  def default_config(:accepted_schemes), do: @default_accepted_schemes
  def default_config(:accepted_mime_types), do: @default_accepted_mime_types
  def default_config(:crawl_query?), do: true
  def default_config(:crawl_fragment?), do: false
  def default_config(:req_options), do: [connect_options: [timeout: 15_000], retry: false]

  ## Execution / Implementation

  @doc """
  Returns a stream that represents the execution of the given Hop.

  This function will perform a limited-depth, breadth-first crawl from
  the given start URL, and lazily return tuples of `{url, response, state}`
  for each successfully visited page.
  """
  @doc type: :execution
  def stream(%Hop{url: url} = hop, state \\ %State{}) do
    max_depth = config(hop, :max_depth)

    urls = List.wrap(url)
    hostnames = Enum.reduce(urls, state.hostnames, &MapSet.put(&2, hostname(&1)))

    state = %{state | hostnames: hostnames}
    start = Enum.map(urls, &{&1, 0})

    Stream.unfold({start, state}, fn {urls, state} ->
      {_visited, leftover} =
        Enum.split_while(urls, fn {url, _} ->
          MapSet.member?(state.visited, url)
        end)

      case leftover do
        [] ->
          nil

        [{_, depth}] when depth > max_depth ->
          nil

        [{url, depth} | rest] ->
          {response, next_links, state} = do_visit(hop, url, state)
          new_links = rest ++ Enum.map(next_links, &{&1, depth + 1})
          state = visit(state, url)

          {{url, response, state}, {new_links, state}}
      end
    end)
    |> Stream.reject(fn {_url, response, _} -> is_nil(response) end)
  end

  defp do_visit(%Hop{config: config} = hop, url, state) do
    with {:ok, url} <- hop.prefetch.(url, state, config),
         {:ok, response, state} <- hop.fetch.(url, state, config),
         {:ok, links, state} <- hop.next.(url, response, state, config) do
      {response, links, state}
    else
      _error ->
        {nil, [], state}
    end
  end

  ## Validators

  @doc """
  Validates that the given URL has not already been visited.

  The Crawl state contains a member `:visited` that is populated with
  a set of URLs that have already been visited.
  """
  @doc type: :validator
  def validate_visited({:ok, url}, %{visited: visited} = _state, _opts) when is_binary(url) do
    if MapSet.member?(visited, url) do
      {:error, :already_visited}
    else
      {:ok, url}
    end
  end

  def validate_visited(value, _state, _opts), do: value

  @doc """
  Validates that the given URL's scheme is valid for the crawl.

  Validates that the scheme is populated, correct, and falls within
  one of the configured accepted schemes according to the `:accepted_schemes`
  configuration option.
  """
  @doc type: :validator
  def validate_scheme({:ok, url}, _state, opts) do
    accepted_schemes = opts[:accepted_schemes]
    %URI{scheme: scheme} = URI.parse(url)

    if Enum.any?(accepted_schemes, &(&1 == scheme)) do
      {:ok, url}
    else
      {:error, :invalid_scheme}
    end
  end

  def validate_scheme(value, _state, _opts), do: value

  @doc """
  Validates that the given URL's hostname is valid for the crawl.

  Validates that the hostname is populated, correct, and falls within
  the set of hostnames allowed according to the crawl state.
  """
  @doc type: :validator
  def validate_hostname({:ok, url}, %{hostnames: hostnames} = _state, _opts) do
    with %URI{host: host} <- URI.parse(url),
         {:ok, _} <- :inet.gethostbyname(to_charlist(host)),
         true <- MapSet.member?(hostnames, hostname(url)) do
      {:ok, url}
    else
      _ ->
        {:error, :invalid_host}
    end
  end

  def validate_hostname(value, _state, _opts), do: value

  @doc """
  Validates that the given URL's content is valid for the crawl.

  This function attempts to perform a HEAD request to the given URL to
  check if the response content-type is one of the accepted mime types
  and that the max content length is below the specified max content length
  for the crawl.

  If the given server does not support HEAD requests, it will simply
  accept the URL as valid.
  """
  @doc type: :validator
  def validate_content({:ok, url}, _state, opts) do
    accepted_mime_types = opts[:accepted_mime_types]
    max_content_length = opts[:max_content_length]

    case Req.head(url, retry: false) do
      {:ok, %{status: status, headers: headers}} when status in 200..299 ->
        content_type = Map.get(headers, "Content-Type") || Map.get(headers, "content-type")
        content_length = Map.get(headers, "Content-Length") || Map.get(headers, "Content-Length")

        cond do
          not accept_mime_type?(content_type, accepted_mime_types) ->
            {:error, :invalid_mime_type}

          not accept_content_length?(content_length, max_content_length) ->
            {:error, :request_too_large}

          true ->
            {:ok, url}
        end

      _error ->
        {:ok, url}
    end
  end

  def validate_content(value, _state, _opts), do: value

  @doc """
  Fetches all of the links on a given page.

  This function takes the current URL and merges it with the given
  anchor link to generate a fully-qualified URL.

  ## Options

      * `:crawl_query?` - whether or not to treat query parameters
      as unique links to crawl. Defaults to `true`

      * `:crawl_fragment?` - whether or not to treat fragments as
      unique links to crawl. Defaults to `false`  
  """
  @doc type: :html
  def fetch_links(url, body, opts \\ []) do
    opts = Keyword.validate!(opts, crawl_query?: true, crawl_fragment?: false)
    crawl_query? = opts[:crawl_query?]
    crawl_fragment? = opts[:crawl_fragment?]

    case Floki.parse_document(body) do
      {:ok, doc} ->
        doc
        |> Floki.find("a")
        |> Floki.attribute("href")
        |> Enum.map(fn href ->
          merged = URI.merge(url, href)
          merged = if crawl_query?, do: merged, else: %{merged | query: nil}
          merged = if crawl_fragment?, do: merged, else: %{merged | fragment: nil}

          URI.to_string(merged)
        end)
        |> Enum.uniq()

      _error ->
        []
    end
  end

  ## State Manipulation

  @doc """
  Marks the given URL as visited.

  This will update the set of visited URLs, and also mark this URL
  as the last crawled URL in the state struct.
  """
  @doc type: :state
  def visit(%State{visited: visited} = state, url) do
    %{state | visited: MapSet.put(visited, url), last_crawled_url: url}
  end

  ## Private Helpers

  defp accept_mime_type?(nil, _), do: true

  defp accept_mime_type?(mime_type, accepted_mime_types) do
    Enum.any?(mime_type, fn mime_type ->
      [mime_type | _] = String.split(mime_type, ";")
      Enum.any?(accepted_mime_types, &(&1 == mime_type))
    end)
  end

  defp accept_content_length?(nil, _), do: true

  defp accept_content_length?(content_length, max_content_length) do
    content_length <= max_content_length
  end

  defp hostname(url) do
    if host = URI.parse(url).host do
      case String.split(host, ".") do
        [_host, _tld] = split_host -> Enum.join(split_host, ".")
        [_sub | rest] -> Enum.join(rest, ".")
      end
    end
  end
end
